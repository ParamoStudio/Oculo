//
//  SearchPaletteView.swift
//  Óculo
//
//  Buscador ⌘K: popup centrado que contiene todo (campo + resultados).
//  Al teclear → búsqueda rápida (BM25F). Tab → afinada (T3d). No se cierra al
//  abrir documentos ni con Quick Look; solo al pulsar fuera (o Esc).
//

import SwiftUI
import AppKit
import QuickLook

struct SearchPaletteView: View {
    @Environment(SearchService.self) private var search
    @Environment(AppearanceStore.self) private var appearance
    @Environment(SettingsStore.self) private var settings
    @Environment(VaultStore.self) private var vault
    @Environment(RecentsStore.self) private var recents

    @Binding var isPresented: Bool
    /// Ámbito de la búsqueda (biblioteca, tag/Favoritos, o todo) + su etiqueta.
    var scope: SearchScope = .all
    var scopeLabel: String?

    /// Fase de la afinada (exhaustiva con Ollama). `none` = modo rápida.
    enum Afinada: Equatable {
        case none
        case running
        case done([RefinedHit])
        case unavailable(String)

        static func == (l: Afinada, r: Afinada) -> Bool {
            switch (l, r) {
            case (.none, .none), (.running, .running): return true
            case let (.done(a), .done(b)): return a.map(\.id) == b.map(\.id)
            case let (.unavailable(a), .unavailable(b)): return a == b
            default: return false
            }
        }
    }

    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var afinada: Afinada = .none
    @State private var afinadaTask: Task<Void, Never>?
    @State private var selection = 0
    @State private var quickLookURL: URL?
    @State private var keyboardNav = false   // solo el teclado auto-scrollea
    @State private var qlMonitor: Any?       // mientras Quick Look está abierto, ← lo cierra
    @FocusState private var focused: Bool

    /// Documentos sobre los que actúan teclado/selección según el modo activo.
    private var activeHits: [SearchHit] {
        if case .done(let hits) = afinada { return hits.map(\.doc) }
        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            hintBar
            content
        }
        .frame(width: 580)
        .background { MaterialBackdrop() }     // misma translucidez que el panel de hover
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 32, y: 16)
        .tint(appearance.tone.accent)
        .quickLookPreview($quickLookURL)
        .onAppear { focused = true }
        .onDisappear { removeQLMonitor(); afinadaTask?.cancel() }
        .onChange(of: query) { _, q in
            afinadaTask?.cancel()
            afinada = .none                    // volver a teclear vuelve a la rápida
            results = search.search(q, scope: scope)
            selection = 0
        }
        .onChange(of: quickLookURL) { _, url in
            url != nil ? installQLMonitor() : removeQLMonitor()   // ← cierra QL (como Espacio en la vista normal)
        }
        .onExitCommand { isPresented = false }
    }

    @ViewBuilder
    private var content: some View {
        switch afinada {
        case .running:
            Divider()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(T("Refining… finding deeper connections (may take a while)", "Afinando… busca conexiones más finas (puede tardar)"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

        case .done(let hits):
            Divider()
            if hits.isEmpty {
                Text(T("Refined search found no clear connections.", "La afinada no encontró conexiones claras."))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                refinedList(hits)
            }

        case .unavailable(let reason):
            Divider()
            unavailableBanner(reason)
            if !results.isEmpty { resultsList }   // fallback: la rápida sigue ahí

        case .none:
            if !results.isEmpty {
                Divider()
                resultsList
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                Text(T("No results", "Sin resultados"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private func unavailableBanner(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.slash").foregroundStyle(.orange)
            Text(T("Refined search unavailable · \(reason)", "Afinada no disponible · \(reason)"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(scopeLabel.map { T("Search in \($0)…", "Buscar en \($0)…") } ?? T("Search everything…", "Buscar en todo…"), text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onKeyPress(.tab) { startAfinada(); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.leftArrow) { quickLookSelected(); return .handled }
                .onKeyPress(.rightArrow) { revealSelected(); return .handled }
                .onKeyPress(.return) { openSelected(); return .handled }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// Atajos en su propia fila bajo el campo: caben en una sola línea.
    private var hintBar: some View {
        Text(T("↑↓ move · ← Quick Look · → Finder · ⏎ open · ⇥ refine", "↑↓ mover · ← Quick Look · → Finder · ⏎ abrir · ⇥ afinada"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Identidad posicional (no por ruta): al cambiar la consulta,
                    // cada fila se redibuja con su hit actual y no queda obsoleta.
                    ForEach(Array(results.enumerated()), id: \.offset) { index, hit in
                        resultRow(hit, index: index).id(index)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)
            .onChange(of: selection) { _, value in
                guard keyboardNav else { return }   // el hover no arrastra la lista
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func resultRow(_ hit: SearchHit, index: Int) -> some View {
        let isSelected = index == selection
        return HStack(spacing: 11) {
            Image(systemName: "doc.text")
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.displayTitle).lineLimit(1)
                Text("\(hit.library) · \(hit.name)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSelected {
                Button { quickLookURL = hit.url } label: { Image(systemName: "eye") }
                    .buttonStyle(.plain).help("Quick Look")
                Button { DocumentActions.revealInFinder(hit.url) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help(T("Show in Finder", "Mostrar en Finder"))
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? appearance.tone.accent.opacity(0.92) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { keyboardNav = false; selection = index } }
        .onTapGesture { open(hit) }   // abre; NO cierra el buscador
    }

    // MARK: Lista afinada (propuestas rankeadas con why + páginas)

    private func refinedList(_ hits: [RefinedHit]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(hits.enumerated()), id: \.offset) { index, hit in
                        refinedRow(hit, index: index).id(index)
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

    private func refinedRow(_ hit: RefinedHit, index: Int) -> some View {
        let isSelected = index == selection
        let doc = hit.doc
        return HStack(alignment: .top, spacing: 11) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.displayTitle).lineLimit(1)
                if !hit.why.isEmpty {
                    Text(hit.why)                                   // motivo de la elección (trazabilidad)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text("\(doc.library) · \(doc.name)")
                        .lineLimit(1)
                    if !hit.pages.isEmpty {
                        pageChips(hit.pages, selected: isSelected)
                    }
                }
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            }
            Spacer(minLength: 8)
            if isSelected {
                Button { quickLookURL = doc.url } label: { Image(systemName: "eye") }
                    .buttonStyle(.plain).help("Quick Look")
                Button { DocumentActions.revealInFinder(doc.url) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help(T("Show in Finder", "Mostrar en Finder"))
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? appearance.tone.accent.opacity(0.92) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { keyboardNav = false; selection = index } }
        .onTapGesture { open(doc) }
    }

    private func pageChips(_ pages: [Int], selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text.magnifyingglass").font(.caption2)
            Text(T("pp. ", "págs ") + pages.map(String.init).joined(separator: ", "))
        }
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(
            Capsule().fill(selected ? Color.white.opacity(0.18) : appearance.tone.accent.opacity(0.14))
        )
    }

    private func move(_ delta: Int) {
        guard !activeHits.isEmpty else { return }
        keyboardNav = true
        selection = max(0, min(activeHits.count - 1, selection + delta))
    }

    private func openSelected() {
        guard activeHits.indices.contains(selection) else { return }
        open(activeHits[selection])   // abre; NO cierra el buscador
    }

    /// Abre un documento: lo registra en recientes (clavado a id si está digerido) y lo abre.
    private func open(_ hit: SearchHit) {
        recents.record(url: hit.url, library: hit.library, noteID: search.noteID(forPath: hit.path))
        DocumentActions.openInNativeApp(hit.url)
    }

    private func quickLookSelected() {
        guard activeHits.indices.contains(selection) else { return }
        quickLookURL = activeHits[selection].url
    }

    private func revealSelected() {
        guard activeHits.indices.contains(selection) else { return }
        DocumentActions.revealInFinder(activeHits[selection].url)
    }

    // MARK: Afinada (Tab)

    private func startAfinada() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        guard afinada != .running else { return }
        selection = 0
        afinada = .running
        afinadaTask?.cancel()
        afinadaTask = Task {
            let result = await search.refine(
                q, notes: vault.allNotes, scope: scope,
                model: settings.ollamaModel, endpoint: settings.ollamaEndpoint
            )
            if Task.isCancelled { return }
            switch result {
            case .done(let hits): afinada = .done(hits)
            case .unavailable(let reason): afinada = .unavailable(reason)
            }
        }
    }

    // MARK: Quick Look — cerrar con ←

    private func installQLMonitor() {
        removeQLMonitor()
        qlMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 123 {        // 123 = flecha izquierda
                quickLookURL = nil           // cierra (vuelve atrás)
                return nil                   // consume
            }
            return event
        }
    }

    private func removeQLMonitor() {
        if let qlMonitor { NSEvent.removeMonitor(qlMonitor) }
        qlMonitor = nil
    }
}

/// Vidrio dentro de la ventana (mismo material que el panel de hover).
/// Compartido por el buscador y el panel de Recientes.
struct MaterialBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}
