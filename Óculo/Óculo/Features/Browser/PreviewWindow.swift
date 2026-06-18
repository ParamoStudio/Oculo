//
//  PreviewWindow.swift
//  Óculo
//
//  Panel flotante propio (NSPanel) para el popup de preview: vidrio gris
//  refractivo neutro, sin flecha, con tracking AppKit fiable (hover/cierre).
//

import SwiftUI
import AppKit
import Observation

/// Lee la NSWindow que hospeda la vista, para convertir coordenadas a pantalla.
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

@MainActor
@Observable
final class PreviewWindowController {
    /// `true` mientras el ratón está sobre el panel (observable).
    var panelHovered = false
    @ObservationIgnored private var panel: NSPanel?

    /// Frame del panel en coordenadas de pantalla (vacío si no se muestra).
    var screenFrame: CGRect { panel?.isVisible == true ? (panel?.frame ?? .zero) : .zero }

    /// Muestra `content` junto al cursor (`cursor` en coords de pantalla, origen abajo-izq).
    func show(content: AnyView, near cursor: CGPoint, parent: NSWindow, dark: Bool) {
        let panel = ensurePanel(parent: parent)
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        guard let container = panel.contentView as? PanelContainerView else { return }
        let host = NSHostingView(rootView: content)
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        size.width = min(max(size.width, 320), 520)
        size.height = min(max(size.height, 120), 620)

        container.setHost(host)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(cursor: cursor, size: size, on: parent.screen))

        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.order(.above, relativeTo: parent.windowNumber)
        container.animateAppearance()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel(parent: NSWindow) -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.hidesOnDeactivate = true
        p.acceptsMouseMovedEvents = true
        p.animationBehavior = .utilityWindow
        let container = PanelContainerView()
        container.onHoverChange = { [weak self] inside in self?.panelHovered = inside }
        p.contentView = container
        panel = p
        return p
    }

    private func origin(cursor: CGPoint, size: NSSize, on screen: NSScreen?) -> NSPoint {
        let gap: CGFloat = 18
        let visible = (screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: cursor.x, y: cursor.y, width: size.width, height: size.height)
        // A la derecha del cursor; si no cabe, a la izquierda.
        var x = cursor.x + gap
        if x + size.width > visible.maxX { x = cursor.x - gap - size.width }
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        // Centrado verticalmente en el cursor.
        var y = cursor.y - size.height / 2
        y = max(visible.minY + 8, min(y, visible.maxY - size.height - 8))
        return NSPoint(x: x, y: y)
    }
}

/// Contenedor del panel: vidrio refractivo neutro + tracking de ratón + host SwiftUI.
final class PanelContainerView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var host: NSView?
    private var trackingArea: NSTrackingArea?
    private let effect = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        effect.material = .hudWindow          // gris refractivo neutro
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no usado") }

    func setHost(_ newHost: NSView) {
        host?.removeFromSuperview()
        newHost.frame = bounds
        newHost.autoresizingMask = [.width, .height]
        addSubview(newHost)
        host = newHost
    }

    override func layout() {
        super.layout()
        effect.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    /// Aparición con bounce suave: escala desde 0.95 con muelle + fade corto.
    /// El panel es borderless (contentView ocupa todo), así que centrar el
    /// anchorPoint y la position no descoloca.
    func animateAppearance() {
        guard let layer else { return }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.removeAnimation(forKey: "pop")
        layer.removeAnimation(forKey: "fade")

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.95
        pop.toValue = 1.0
        pop.damping = 16
        pop.stiffness = 280
        pop.mass = 1
        pop.initialVelocity = 0
        pop.duration = pop.settlingDuration

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.16

        layer.add(pop, forKey: "pop")
        layer.add(fade, forKey: "fade")
    }
}
