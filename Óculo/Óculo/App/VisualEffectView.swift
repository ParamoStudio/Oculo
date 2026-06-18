//
//  VisualEffectView.swift
//  Óculo
//
//  Frost translúcido real (NSVisualEffectView). Con blending "behind window" y
//  la ventana no-opaca, deja ver el escritorio difuminado tras la app.
//

import SwiftUI
import AppKit

/// NSVisualEffectView que vuelve su ventana no-opaca en cuanto se incorpora a
/// ella (más fiable que hacerlo de forma asíncrona desde updateNSView).
private final class FrostingView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = FrostingView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
    }
}
