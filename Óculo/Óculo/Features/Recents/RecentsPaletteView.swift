//
//  RecentsPaletteView.swift
//  Óculo
//
//  Panel centrado de Recientes (mismo formato que el buscador, sin campo de
//  texto): los últimos documentos abiertos en su app definitiva. Se navega con
//  flechas (↑↓ mover · ← Quick Look · → Finder · ⏎ abrir). Abre/cierra con la
//  tecla configurable (por defecto R) o Esc.
//

import SwiftUI
import AppKit
import QuickLook

struct RecentsPaletteView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(SearchService.self) private var search
    @Environment(RecentsStore.self) private var recents
    @Environment(AppearanceStore.self) private var appearance

    @Binding var isPresented: Bool

    @State private var selection = 0
    @State private var quickLookURL: URL?
    @State private var keyboardNav = false
    @State private var qlMonitor: Any?
    @FocusState private var focused: Bool

    private let maxShown = 10

    private struct RecentItem: Identifiable {
        let entry: RecentEntry
        let url: URL
        let library: String?
        var id: String { entry.id }
    }

    /// Últimas aperturas vivas y existentes (resueltas por id si están digeridas).
    private var items: [RecentItem] {
        recents.entries.compactMap { e -> RecentItem? in
            let url = liveURL(for: e.ref)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return RecentItem(entry: e, url: url, library: libraryName(for: url) ?? e.ref.library)
        }
        .prefix(maxShown)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            hintBar
            if items.isEmpty {
                Text(T("Documents you open will appear here.", "Los documentos que abras aparecerán aquí."))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                Divider()
                list
            }
        }
        .frame(width: 560)
        .background { MaterialBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 32, y: 16)
        .tint(appearance.tone.accent)
        .quickLookPreview($quickLookURL)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onDisappear { removeQLMonitor() }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.leftArrow) { quickLookSelected(); return .handled }
        .onKeyPress(.rightArrow) { revealSelected(); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onChange(of: quickLookURL) { _, url in
            url != nil ? installQLMonitor() : removeQLMonitor()
        }
        .onExitCommand { isPresented = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock").foregroundStyle(.secondary)
            Text(T("Recents", "Recientes")).font(.title3)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private var hintBar: some View {
        Text(T("↑↓ move · ← Quick Look · → Finder · ⏎ open", "↑↓ mover · ← Quick Look · → Finder · ⏎ abrir"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        row(item, index: index).id(index)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 420)
            .onChange(of: selection) { _, value in
                guard keyboardNav else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func row(_ item: RecentItem, index: Int) -> some View {
        let isSelected = index == selection
        let docType = DocumentType(extension: item.url.pathExtension)
        return HStack(spacing: 11) {
            Text(docType?.label ?? "DOC")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? .white : (docType?.accentColor ?? .gray))
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1)
                if let library = item.library, !library.isEmpty {
                    Text(library)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.entry.openedAt.formatted(.relative(presentation: .numeric).locale(Localization.shared.locale)))
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            if isSelected {
                Button { quickLookURL = item.url } label: { Image(systemName: "eye") }
                    .buttonStyle(.plain).help("Quick Look")
                Button { DocumentActions.revealInFinder(item.url) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help(T("Show in Finder", "Mostrar en Finder"))
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? appearance.tone.accent.opacity(0.92) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { keyboardNav = false; selection = index } }
        .onTapGesture { open(item) }
    }

    // MARK: Acciones

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        keyboardNav = true
        selection = max(0, min(items.count - 1, selection + delta))
    }

    private func openSelected() {
        guard items.indices.contains(selection) else { return }
        open(items[selection])
    }

    private func quickLookSelected() {
        guard items.indices.contains(selection) else { return }
        quickLookURL = items[selection].url
    }

    private func revealSelected() {
        guard items.indices.contains(selection) else { return }
        DocumentActions.revealInFinder(items[selection].url)
    }

    /// Abre en la app definitiva, re-registra (sube a lo más reciente) y cierra el panel.
    private func open(_ item: RecentItem) {
        recents.record(url: item.url, library: item.library, noteID: search.noteID(forPath: item.url.standardizedFileURL.path))
        DocumentActions.openInNativeApp(item.url)
        isPresented = false
    }

    // MARK: Resolución

    private func liveURL(for ref: DocRef) -> URL {
        if let id = ref.noteID, let hit = search.docByNoteID[id] { return hit.url }
        return ref.url
    }

    private func libraryName(for url: URL) -> String? {
        store.libraries.first { url.standardizedFileURL.path.hasPrefix($0.url.path) }?.name
    }

    // MARK: Quick Look — cerrar con ←

    private func installQLMonitor() {
        removeQLMonitor()
        qlMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 123 { quickLookURL = nil; return nil }   // ← cierra
            return event
        }
    }

    private func removeQLMonitor() {
        if let qlMonitor { NSEvent.removeMonitor(qlMonitor) }
        qlMonitor = nil
    }
}
