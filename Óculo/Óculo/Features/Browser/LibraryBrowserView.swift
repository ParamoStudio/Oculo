//
//  LibraryBrowserView.swift
//  Óculo
//
//  T1a — Biblioteca navegable: sidebar con las bibliotecas abiertas y, en el
//  detalle, navegación drill-down con rejilla de bolsillos-categoría y
//  tarjetas-tipo de documento. Estilo básico; el pase estético fino es T1b.
//

import SwiftUI
import QuickLook
import AppKit
import PDFKit

struct LibraryBrowserView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppearanceStore.self) private var appearance
    @Environment(VaultStore.self) private var vault
    @Environment(SearchService.self) private var search
    @Environment(SettingsStore.self) private var settings
    @Environment(TagStore.self) private var tags
    @Environment(CoverStore.self) private var covers
    @Environment(GridSelection.self) private var gridSel

    @State private var showingSearch = false
    @State private var searchGlobal = false          // el botón/⌘K busca en TODAS las bibliotecas
    @State private var showingRecents = false
    @State private var showingAbout = false
    @State private var tagPrompt: TagPrompt?
    @State private var tagPickerDocs: [DocRef]?
    @State private var coverPickEntry: LibraryEntry?

    // Incluye `isLoaded`: no reconstruimos (y borramos) el índice persistido
    // mientras la bóveda aún se lee, o perderíamos los aciertos por bóveda.
    private var indexKey: String { "\(store.libraries.count)#\(vault.noteCount)#\(vault.isLoaded)" }

    /// Cambia cuando cambia cualquier tag (nombre o miembros) → refresca usertags.
    private var tagsSignature: String {
        tags.tags.map { "\($0.name):\($0.members.map(\.id).sorted().joined(separator: ","))" }.joined(separator: ";")
    }

    /// Ámbito de búsqueda según la selección (decisión del usuario: por contexto).
    private var searchScope: SearchScope {
        switch store.selection {
        case .library: return store.selectedLibrary.map { .library($0.name) } ?? .all
        case .favorites: return .paths(livePaths(tags.tags.flatMap(\.members)))
        case .tag(let id): return .paths(livePaths(tags.tag(id)?.members ?? []))
        case .none: return .all
        }
    }

    /// Fila bajo el topbar con el contexto (biblioteca/tag/favoritos): glass + tono.
    private func contextBar(_ context: String) -> some View {
        Text(context)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(appearance.tone.accent.opacity(0.18))
                }
            }
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    /// Contexto actual mostrado bajo el wordmark (centrado).
    private var contextTitle: String? {
        switch store.selection {
        case .library: return store.selectedLibrary.map { T("Library: ", "Biblioteca: ") + $0.name }
        case .favorites: return T("Favorites", "Favoritos")
        case .tag(let id): return tags.tag(id).map { "Tag: \($0.name)" }
        case .none: return nil
        }
    }

    /// Etiqueta del ámbito para el placeholder del buscador.
    private var scopeLabel: String? {
        switch store.selection {
        case .library: return store.selectedLibrary?.name
        case .favorites: return T("Favorites", "Favoritos")
        case .tag(let id): return tags.tag(id)?.name
        case .none: return nil
        }
    }

    private func livePaths(_ members: [DocRef]) -> Set<String> {
        Set(members.map { ref in
            if let id = ref.noteID, let hit = search.docByNoteID[id] { return hit.path }
            return ref.path
        })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let context = contextTitle { contextBar(context) }
                }
        }
        .tint(appearance.tone.accent)
        .environment(\.locale, Localization.shared.locale)   // fechas/números en el idioma elegido
        .toolbar { toolbarContent }
        .overlay { searchOverlay }
        .overlay { recentsOverlay }
        .overlay { aboutOverlay }
        .overlay { tagPromptOverlay }
        .overlay { tagPickerOverlay }
        .overlay { coverPickOverlay }
        .environment(\.requestTagPrompt) { tagPrompt = $0 }
        .environment(\.requestAddToTag) { tagPickerDocs = $0 }
        .environment(\.requestCoverPick) { coverPickEntry = $0 }
        .animation(.easeOut(duration: 0.12), value: showingSearch)
        .animation(.easeOut(duration: 0.12), value: showingRecents)
        .animation(.easeOut(duration: 0.12), value: showingAbout)
        .animation(.easeOut(duration: 0.12), value: tagPrompt)
        .animation(.easeOut(duration: 0.12), value: tagPickerDocs)
        .animation(.easeOut(duration: 0.12), value: coverPickEntry?.id)
        .background(KeyMonitorView(handler: handleGlobalKey))   // teclas configurables (buscador / recientes)
        .task(id: indexKey) {
            guard vault.isLoaded else { return }   // espera a la bóveda; no borres el índice bueno
            await search.rebuild(libraries: store.libraries, vault: vault, tags: tags)
        }
        .task(id: tagsSignature) {
            await search.refreshUserTags(from: tags)   // al cambiar tags: solo actualiza usertags
        }
    }

    private var sidebar: some View {
        List {
            Section(T("Tools", "Herramientas")) {
                aboutRow
                recentsRow
                favoritesRow
            }
            Section(T("Libraries", "Bibliotecas")) {
                ForEach(Array(store.libraries.enumerated()), id: \.element.id) { index, library in
                    libraryRow(library)
                    if index < store.libraries.count - 1 {
                        Divider()
                            .opacity(0.4)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 4)
        .scrollContentBackground(.hidden)
        .navigationTitle("Óculo")
        .frame(minWidth: 200)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await store.openLibrary() }
            } label: {
                Label(T("Open library…", "Abrir biblioteca…"), systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.22), lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func libraryRow(_ library: Library) -> some View {
        Label(library.name, systemImage: "books.vertical")
            .sidebarRow(isSelected: store.selection == .library(library.id))
            .onTapGesture { store.selection = .library(library.id) }
            .contextMenu {
                Button(T("Remove from Óculo", "Quitar de Óculo"), role: .destructive) {
                    store.removeLibrary(id: library.id)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
    }

    /// "About": abre un panel superpuesto con el ethos, atajos y créditos.
    private var aboutRow: some View {
        Label(T("About", "Acerca de"), systemImage: "info.circle")
            .sidebarRow(isSelected: showingAbout)
            .onTapGesture { showingAbout = true }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
    }

    /// "Recientes": no es un detalle, abre un panel centrado superpuesto (como el buscador).
    private var recentsRow: some View {
        Label(T("Recents", "Recientes"), systemImage: "clock")
            .sidebarRow(isSelected: showingRecents)
            .onTapGesture { showingRecents = true }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
    }

    /// "Favoritos": abre la sección de tags (el "+" para crear vive dentro de ella).
    private var favoritesRow: some View {
        Label(T("Favorites", "Favoritos"), systemImage: "star")
            .sidebarRow(isSelected: store.selection == .favorites)
            .onTapGesture { store.selection = .favorites }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .library:
            if let library = store.selectedLibrary {
                LibraryContentView(library: library)
                    .id(library.id)   // reconstruye al cambiar de biblioteca
                    .environment(\.searchActive, showingSearch || showingRecents)
            } else {
                emptyDetail
            }
        case .favorites:
            FavoritesView()
                .environment(\.searchActive, showingSearch || showingRecents)
        case .tag(let id):
            if let tag = tags.tag(id) {
                TagDetailView(tag: tag)
                    .id(tag.id)
                    .environment(\.searchActive, showingSearch || showingRecents)
            } else {
                emptyDetail
            }
        case .none:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView(
            T("No library", "Sin biblioteca"),
            systemImage: "books.vertical",
            description: Text(T("Open a folder to start.", "Abre una carpeta para empezar."))
        )
        .background { LibraryBackground(mode: appearance.mode, tone: appearance.tone) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if case .tag = store.selection {
            ToolbarItem(placement: .navigation) {
                Button { store.selection = .favorites } label: { Image(systemName: "chevron.left") }
                    .help(T("Back to Favorites", "Volver a Favoritos"))
            }
        }
        ToolbarItem(placement: .principal) {
            EmbossedWordmark()
        }
        if !gridSel.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button { gridSel.selectAll() } label: { Image(systemName: "checklist") }
                    .help(T("Select all", "Seleccionar todo"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { gridSel.clear() } label: { Image(systemName: "xmark.circle") }
                    .help(T("Deselect (\(gridSel.count))", "Deseleccionar (\(gridSel.count))"))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { searchGlobal = true; showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                .help(T("Search all libraries (⌘K)", "Buscar en todas las bibliotecas (⌘K)"))
                .keyboardShortcut("k", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            AppearanceControl()
        }
    }

    @ViewBuilder
    private var searchOverlay: some View {
        if showingSearch {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { showingSearch = false }
                SearchPaletteView(
                    isPresented: $showingSearch,
                    scope: searchGlobal ? .all : searchScope,
                    scopeLabel: searchGlobal ? "todas las bibliotecas" : scopeLabel
                )
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var recentsOverlay: some View {
        if showingRecents {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { showingRecents = false }
                RecentsPaletteView(isPresented: $showingRecents)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var aboutOverlay: some View {
        if showingAbout {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { showingAbout = false }
                AboutPanelView(onClose: { showingAbout = false })
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var tagPromptOverlay: some View {
        if let prompt = tagPrompt {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { tagPrompt = nil }
                TagNamePromptView(
                    title: prompt.isRename ? T("Rename tag", "Renombrar tag") : T("New tag", "Nuevo tag"),
                    confirmLabel: prompt.isRename ? T("Rename", "Renombrar") : T("Create", "Crear"),
                    initialName: prompt.currentName,
                    onConfirm: { name in applyTagPrompt(prompt, name: name); tagPrompt = nil },
                    onCancel: { tagPrompt = nil }
                )
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var tagPickerOverlay: some View {
        if let docs = tagPickerDocs {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { tagPickerDocs = nil }
                TagPickerView(docs: docs, onClose: { tagPickerDocs = nil })
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var coverPickOverlay: some View {
        if let entry = coverPickEntry {
            let key = search.noteID(forPath: entry.resolvedURL.standardizedFileURL.path) ?? entry.resolvedURL.standardizedFileURL.path
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { coverPickEntry = nil }
                CoverPickerView(
                    url: entry.resolvedURL,
                    initialPage: covers.page(for: key),
                    onUse: { covers.setPage($0, for: key); coverPickEntry = nil },
                    onClose: { coverPickEntry = nil }
                )
            }
            .transition(.opacity)
        }
    }

    private func applyTagPrompt(_ prompt: TagPrompt, name: String) {
        switch prompt {
        case .create(let docs):
            let tag = tags.create(name)
            if !docs.isEmpty { tags.add(docs, to: tag.id) }
        case .rename(let id, _):
            tags.rename(id, to: name)
        }
    }

    /// Atajos sin modificadores y fuera de campos de texto: búsqueda, recientes, volver.
    private func handleGlobalKey(_ event: NSEvent) -> Bool {
        guard !isEditingText() else { return false }
        guard event.modifierFlags.intersection([.command, .option, .control, .function]).isEmpty else { return false }

        // Volver atrás desde un tag (← o Esc), si no hay ningún panel abierto.
        let noOverlay = !showingSearch && !showingRecents && tagPrompt == nil && tagPickerDocs == nil && coverPickEntry == nil
        if noOverlay, case .tag = store.selection, event.keyCode == 123 || event.keyCode == 53 {
            store.selection = .favorites
            return true
        }

        let char = event.charactersIgnoringModifiers?.lowercased()

        let recentsKey = settings.recentsKey.lowercased()
        if !showingSearch, !recentsKey.isEmpty, char == recentsKey {
            showingRecents.toggle()    // R abre y cierra
            return true
        }
        let searchKey = settings.searchKey.lowercased()
        if !showingSearch, !showingRecents, !searchKey.isEmpty, char == searchKey {
            searchGlobal = false        // la tecla S busca en el contexto actual
            showingSearch = true
            return true
        }
        return false
    }
}

/// True si el primer respondedor es un editor de texto (no robar teclas al escribir).
@MainActor
func isEditingText() -> Bool {
    NSApp.keyWindow?.firstResponder is NSText
}

private struct SearchActiveKey: EnvironmentKey {
    static let defaultValue = false
}

/// Marcos de las tarjetas en el espacio "docgrid", para la marquesina de selección.
private struct CardFramesKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]
    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension EnvironmentValues {
    var searchActive: Bool {
        get { self[SearchActiveKey.self] }
        set { self[SearchActiveKey.self] = newValue }
    }
}

/// Petición de nombrar/crear/renombrar un tag (la resuelve el popup de cristal
/// que vive en `LibraryBrowserView`). `create` puede traer documentos a añadir.
enum TagPrompt: Equatable {
    case create([DocRef])
    case rename(UUID, String)

    var isRename: Bool { if case .rename = self { return true }; return false }
    var currentName: String { if case .rename(_, let name) = self { return name }; return "" }
}

private struct RequestTagPromptKey: EnvironmentKey {
    static let defaultValue: (TagPrompt) -> Void = { _ in }
}

private struct RequestAddToTagKey: EnvironmentKey {
    static let defaultValue: ([DocRef]) -> Void = { _ in }
}

private struct RequestCoverPickKey: EnvironmentKey {
    static let defaultValue: (LibraryEntry) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Lanza el popup de cristal para nombrar un tag desde cualquier vista anidada.
    var requestTagPrompt: (TagPrompt) -> Void {
        get { self[RequestTagPromptKey.self] }
        set { self[RequestTagPromptKey.self] = newValue }
    }

    /// Lanza el selector de tag (buscable) para añadir esos documentos a un tag.
    var requestAddToTag: ([DocRef]) -> Void {
        get { self[RequestAddToTagKey.self] }
        set { self[RequestAddToTagKey.self] = newValue }
    }

    /// Lanza el selector de página de portada para un documento.
    var requestCoverPick: (LibraryEntry) -> Void {
        get { self[RequestCoverPickKey.self] }
        set { self[RequestCoverPickKey.self] = newValue }
    }
}

/// Estilo común de fila del sidebar: selección con tono, y un realce dinámico
/// al pasar el ratón (fondo suave + ligero rebote), como en apps de Apple.
private struct SidebarRowStyle: ViewModifier {
    @Environment(AppearanceStore.self) private var appearance
    var isSelected: Bool
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14.5, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(appearance.tone.accent)
                          : AnyShapeStyle(hover ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
            .scaleEffect(hover && !isSelected ? 1.015 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hover)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .onHover { hover = $0 }
    }
}

extension View {
    func sidebarRow(isSelected: Bool = false) -> some View {
        modifier(SidebarRowStyle(isSelected: isSelected))
    }
}

/// Botón redondo "+" con rebote suave en hover y clic (para crear tag).
private struct BouncyAddButton: View {
    @Environment(AppearanceStore.self) private var appearance
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(appearance.tone.accent))
                .shadow(color: .black.opacity(0.28), radius: 7, y: 3)
        }
        .buttonStyle(BouncyButtonStyle())
        .scaleEffect(hover ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: hover)
        .onHover { hover = $0 }
        .help(T("New tag", "Nuevo tag"))
    }
}

private struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// Logotipo textual "óculo" con relieve de cristal (grabado). Si existe un asset
/// de imagen llamado "Wordmark" lo usa; si no, dibuja el texto estilizado.
private struct EmbossedWordmark: View {
    var body: some View {
        Group {
            if let ns = NSImage(named: "Wordmark") {
                Image(nsImage: ns).resizable().scaledToFit().frame(height: 22).opacity(0.85)
            } else {
                Text("óculo")
                    .font(.system(size: 24, weight: .ultraLight, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.primary.opacity(0.7))   // negro suave en claro, blanco suave en oscuro
                    .padding(.horizontal, 8)                  // holgura dentro de la cápsula de cristal
            }
        }
        .fixedSize()
        // Relieve grabado sutil: sombra arriba (hueco) + luz abajo (canto).
        .shadow(color: .black.opacity(0.30), radius: 0.5, x: 0, y: -0.5)
        .shadow(color: .white.opacity(0.18), radius: 0.5, x: 0, y: 0.5)
        .help("Óculo")
    }
}

/// Botón claro/oscuro (clic = alterna). Al mantener el ratón ~1 s se despliega
/// el picker de tono, para que no esté siempre a la vista.
private struct AppearanceControl: View {
    @Environment(AppearanceStore.self) private var appearance
    @State private var showingTones = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button {
            appearance.toggleMode()
        } label: {
            Image(systemName: appearance.mode == .mist ? "moon" : "sun.max")
        }
        .help(T("Light/dark · hold for tones", "Claro/oscuro · mantén para tonos"))
        .onHover { inside in
            hoverTask?.cancel()
            if inside {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(1000))
                    if !Task.isCancelled { showingTones = true }
                }
            }
        }
        .popover(isPresented: $showingTones, arrowEdge: .bottom) {
            HStack(spacing: 11) {
                ForEach(Tone.all) { tone in
                    Button {
                        appearance.setTone(tone.id)
                        showingTones = false
                    } label: {
                        Circle()
                            .fill(tone.accent)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().strokeBorder(
                                    .primary.opacity(appearance.toneIndex == tone.id ? 0.9 : 0),
                                    lineWidth: 2
                                )
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(tone.name)
                }
            }
            .padding(12)
        }
    }
}

/// Detalle de una biblioteca: pila de navegación que entra en subcarpetas.
private struct LibraryContentView: View {
    let library: Library
    @State private var path: [URL] = []

    var body: some View {
        NavigationStack(path: $path) {
            FolderView(url: library.url, title: library.name, libraryRoot: library.url, libraryName: library.name,
                       onOpenFolder: { path.append($0) })
                .navigationDestination(for: URL.self) { folderURL in
                    FolderView(url: folderURL, title: folderURL.lastPathComponent, libraryRoot: library.url, libraryName: library.name,
                               onOpenFolder: { path.append($0) })
                }
        }
    }
}

/// Una carpeta de una biblioteca: escanea y delega en `DocumentGrid`.
private struct FolderView: View {
    let url: URL
    let title: String
    let libraryRoot: URL
    let libraryName: String
    var onOpenFolder: ((URL) -> Void)? = nil

    @State private var entries: [LibraryEntry] = []

    var body: some View {
        DocumentGrid(
            entries: entries,
            libraryRoot: { _ in libraryRoot },
            libraryName: { _ in libraryName },
            onOpenFolder: onOpenFolder
        )
        .navigationTitle("")
        .task(id: url) {
            entries = await Task.detached { LibraryScanner.scan(directory: url) }.value
        }
    }
}

/// Sección "Favoritos": los tags mostrados como carpetas a las que entrar.
/// (La estética fina de las tarjetas-carpeta es de T4.)
private struct FavoritesView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(TagStore.self) private var tags
    @Environment(SearchService.self) private var search
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.requestTagPrompt) private var requestTagPrompt

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 26)]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if tags.tags.isEmpty {
                    ContentUnavailableView(T("No tags", "Sin tags"), systemImage: "star",
                                           description: Text(T("Create a tag with the + button at the top right.", "Crea un tag con el botón + de arriba a la derecha.")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                            ForEach(tags.tags) { tag in
                                TagCard(tag: tag, sampleURLs: sampleURLs(tag))
                                    .contentShape(Rectangle())
                                    .onTapGesture { store.selection = .tag(tag.id) }
                                    .contextMenu {
                                        Button(T("Rename…", "Renombrar…")) { requestTagPrompt(.rename(tag.id, tag.name)) }
                                        Button(T("Delete tag", "Eliminar tag"), role: .destructive) { tags.delete(tag.id) }
                                    }
                                    .hoverLift()
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BouncyAddButton { requestTagPrompt(.create([])) }
                .padding(22)
        }
        .background { LibraryBackground(mode: appearance.mode, tone: appearance.tone) }
        .navigationTitle("")
    }

    /// Hasta 4 documentos vivos y existentes del tag, para las mini-portadas.
    private func sampleURLs(_ tag: Tag) -> [URL] {
        tag.members.prefix(10).compactMap { ref -> URL? in
            let url = (ref.noteID.flatMap { search.docByNoteID[$0]?.url }) ?? ref.url
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        .prefix(4)
        .map { $0 }
    }
}

/// Tarjeta de un tag en Favoritos: mismo bolsillo que las carpetas (`PocketCardView`).
private struct TagCard: View {
    let tag: Tag
    var sampleURLs: [URL] = []

    @State private var thumbs: [NSImage] = []

    var body: some View {
        PocketCardView(title: tag.name, count: tag.members.count, icon: "tag.fill", thumbs: thumbs)
            .task(id: sampleURLs.map(\.path)) {
                var imgs: [NSImage] = []
                for url in sampleURLs {
                    if let img = await ThumbnailLoader.page(0, of: url, size: CGSize(width: 90, height: 116), scale: 2) {
                        imgs.append(img)
                    }
                }
                thumbs = imgs
            }
    }
}

/// Panel "About": ethos del proyecto, atajos, ajustes y créditos (cristal).
private struct AboutPanelView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.openSettings) private var openSettings
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 5) {
                EmbossedWordmark()
                Text(T("The light that reveals the wisdom you already hold.", "La luz que ilumina la sabiduría que ya tienes."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Text(T("Óculo is a lens with no truth of its own: it points at your folders and presents them as a calm, read-only library. It doesn't move, store, upload or modify anything. Free, open source, no data collection. Forever. Able to use a local LLM to refine your searches even further. (More info on Git).",
                   "Óculo es una lente sin verdad propia: apunta a tus carpetas y las presenta como una biblioteca calmada, de solo lectura. No mueve, guarda, sube ni modifica nada. Gratis, open source, sin recolección de datos. Para siempre. Capaz de usar un LLM local para afinar aún más tus búsquedas. (Más info en Git)."))
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(T("Shortcuts", "Atajos")).font(.headline)
                shortcut("S", T("Search the current context", "Buscar en el contexto actual"))
                shortcut(T("⌘K · search icon", "⌘K · lupa"), T("Search all libraries", "Buscar en todas las bibliotecas"))
                shortcut("⇥", T("Refined (Ollama) after typing; ⏎ fast", "Afinada (Ollama) tras escribir; ⏎ rápida"))
                shortcut("R", T("Recents", "Recientes"))
                shortcut("↑ ↓ · ⏎ · space", T("Move · open · Quick Look", "Mover · abrir · Quick Look"))
                shortcut("← → · F · T", T("Quick Look / Finder · Finder · tag", "Quick Look / Finder · Finder · tag"))
                shortcut(T("⌘-click · ⌘-drag", "⌘-clic · ⌘-arrastrar"), T("Multiple selection", "Selección múltiple"))
            }

            Divider()

            HStack(alignment: .bottom) {
                Button(T("Open Settings…", "Abrir Ajustes…")) { openSettings(); onClose() }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Páramo").font(.caption).foregroundStyle(.secondary)
                    Link("github.com/ParamoStudio", destination: URL(string: "https://github.com/ParamoStudio")!)
                        .font(.caption)
                }
            }
        }
        .padding(22)
        .frame(width: 460)
        .background { MaterialBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 32, y: 16)
        .tint(appearance.tone.accent)
        .onExitCommand { onClose() }
    }

    private func shortcut(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 150, alignment: .leading)
            Text(desc).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Popup de cristal para nombrar/renombrar un tag (mismo formato que el
/// buscador/recientes), en vez del NSAlert de Apple.
private struct TagNamePromptView: View {
    @Environment(AppearanceStore.self) private var appearance
    let title: String
    let confirmLabel: String
    let initialName: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField(T("Tag name", "Nombre del tag"), text: $name)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit(confirm)
            HStack(spacing: 10) {
                Spacer()
                Button(T("Cancel", "Cancelar"), role: .cancel) { onCancel() }
                Button(confirmLabel, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background { MaterialBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 32, y: 16)
        .tint(appearance.tone.accent)
        .onAppear { name = initialName; focused = true }
        .onExitCommand { onCancel() }
    }

    private func confirm() {
        let t = trimmed
        if !t.isEmpty { onConfirm(t) }
    }
}

/// Selector de tag buscable (popup de cristal): escribe para filtrar, navega con
/// flechas, ⏎ añade. Si el nombre no existe, ofrece crearlo. Para añadir uno o
/// varios documentos a un tag sin tener que recorrer una lista larga.
private struct TagPickerView: View {
    @Environment(TagStore.self) private var tags
    @Environment(AppearanceStore.self) private var appearance
    let docs: [DocRef]
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [Tag] {
        let q = trimmedQuery.lowercased()
        return q.isEmpty ? tags.tags : tags.tags.filter { $0.name.lowercased().contains(q) }
    }

    private var canCreate: Bool {
        !trimmedQuery.isEmpty && !tags.tags.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    private var rowCount: Int { filtered.count + (canCreate ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            field
            Text(T("↑↓ move · ⏎ add · esc close", "↑↓ mover · ⏎ añadir · esc cerrar"))
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 12)
            if rowCount > 0 {
                Divider()
                list
            }
        }
        .frame(width: 460)
        .background { MaterialBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 32, y: 16)
        .tint(appearance.tone.accent)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onExitCommand { onClose() }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag").foregroundStyle(.secondary)
            TextField(docs.count > 1 ? T("Tag \(docs.count) documents…", "Añadir tag a \(docs.count) documentos…") : T("Add tag…", "Añadir tag…"), text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.return) { assign(selection); return .handled }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        row(index).id(index)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
            .onChange(of: selection) { _, value in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(_ index: Int) -> some View {
        let isSelected = index == selection
        HStack(spacing: 11) {
            if index < filtered.count {
                Image(systemName: "tag").foregroundStyle(isSelected ? .white : .secondary).frame(width: 18)
                Text(filtered[index].name).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(filtered[index].members.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            } else {
                Image(systemName: "plus").foregroundStyle(isSelected ? .white : appearance.tone.accent).frame(width: 18)
                Text(T("Create “\(trimmedQuery)”", "Crear «\(trimmedQuery)»")).lineLimit(1)
                Spacer(minLength: 8)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? appearance.tone.accent.opacity(0.92) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { selection = index } }
        .onTapGesture { assign(index) }
    }

    private func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        selection = max(0, min(rowCount - 1, selection + delta))
    }

    private func assign(_ index: Int) {
        if index < filtered.count {
            tags.add(docs, to: filtered[index].id)
        } else if canCreate {
            let tag = tags.create(trimmedQuery)
            tags.add(docs, to: tag.id)
        }
        onClose()
    }
}

/// Selector de página de portada (popup de cristal): navega las páginas del PDF
/// con ← → y elige cuál se usa como miniatura. No produce datos nuevos.
private struct CoverPickerView: View {
    @Environment(AppearanceStore.self) private var appearance
    let url: URL
    let initialPage: Int
    let onUse: (Int) -> Void
    let onClose: () -> Void

    @State private var page = 0
    @State private var pageCount = 1
    @State private var thumb: NSImage?
    @FocusState private var focused: Bool

    private let size = CGSize(width: 220, height: 285)

    var body: some View {
        VStack(spacing: 12) {
            Text(T("Cover", "Portada")).font(.headline).frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 12) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(page <= 0)
                Text(T("Page \(page + 1) of \(pageCount)", "Página \(page + 1) de \(pageCount)")).font(.callout).monospacedDigit().frame(minWidth: 140)
                Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(page >= pageCount - 1)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Spacer()
                Button(T("Cancel", "Cancelar"), role: .cancel) { onClose() }
                Button(T("Use this page", "Usar esta página")) { onUse(page) }.buttonStyle(.borderedProminent)
            }
            Text(T("← → change · ⏎ use · esc close", "← → cambiar · ⏎ usar · esc cerrar")).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 300)
        .background { MaterialBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 32, y: 16)
        .tint(appearance.tone.accent)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            page = initialPage
            focused = true
            Task { pageCount = await Self.countPages(url); await load() }
        }
        .onChange(of: page) { _, _ in Task { await load() } }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.return) { onUse(page); return .handled }
        .onExitCommand { onClose() }
    }

    private func step(_ delta: Int) { page = max(0, min(pageCount - 1, page + delta)) }
    private func load() async { thumb = await ThumbnailLoader.page(page, of: url, size: size, scale: 2) }

    private static func countPages(_ url: URL) async -> Int {
        await Task.detached { PDFDocument(url: url)?.pageCount ?? 1 }.value
    }
}

/// Detalle de un tag: sus documentos (multi-biblioteca) resueltos a ruta viva.
/// Reutiliza `DocumentGrid`. Vacío si el tag no tiene miembros existentes.
private struct TagDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(SearchService.self) private var search
    @Environment(AppearanceStore.self) private var appearance
    @Environment(TagStore.self) private var tags
    let tag: Tag

    private var entries: [LibraryEntry] {
        tag.members.compactMap { ref in
            let url = liveURL(for: ref)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return LibraryEntry(
                displayURL: url, resolvedURL: url.resolvingSymlinksInPath(),
                isDirectory: false, docType: DocumentType(extension: url.pathExtension), modified: modified
            )
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(T("Empty tag", "Tag vacío"), systemImage: "tag",
                                       description: Text(T("Add documents from a document's popup or by right-click.", "Añade documentos desde el popup de un documento o por clic derecho.")))
            } else {
                DocumentGrid(
                    entries: entries,
                    libraryRoot: { library(for: $0)?.url ?? $0.resolvedURL.deletingLastPathComponent() },
                    libraryName: { library(for: $0)?.name ?? "" },
                    onRemoveFromTag: { removed in
                        let ids = Set(removed.map { refID(for: $0) })
                        tags.remove(ids, from: tag.id)
                    }
                )
            }
        }
        .background { LibraryBackground(mode: appearance.mode, tone: appearance.tone) }
        .navigationTitle("")
    }

    private func liveURL(for ref: DocRef) -> URL {
        if let id = ref.noteID, let hit = search.docByNoteID[id] { return hit.url }
        return ref.url
    }

    /// id de DocRef para un documento (misma lógica con que se guardó: id de nota o ruta).
    private func refID(for entry: LibraryEntry) -> String {
        let path = entry.resolvedURL.standardizedFileURL.path
        return search.noteID(forPath: path) ?? path
    }

    private func library(for entry: LibraryEntry) -> Library? {
        store.libraries.first { entry.resolvedURL.path.hasPrefix($0.url.path) }
    }
}

/// Rejilla de documentos (y carpetas) reutilizable: hover→panel, atajos, Quick Look,
/// apertura. La usan tanto `FolderView` como las colecciones virtuales (Recientes/Tags).
private struct DocumentGrid: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(VaultStore.self) private var vault
    @Environment(SearchService.self) private var search
    @Environment(RecentsStore.self) private var recents
    @Environment(TagStore.self) private var tags
    @Environment(CoverStore.self) private var covers
    @Environment(\.requestAddToTag) private var requestAddToTag
    @Environment(\.requestCoverPick) private var requestCoverPick
    @Environment(\.searchActive) private var searchActive
    @Environment(GridSelection.self) private var gridSel

    let entries: [LibraryEntry]
    let libraryRoot: (LibraryEntry) -> URL
    let libraryName: (LibraryEntry) -> String
    /// Si se provee (vista de tag), el menú ofrece "Quitar de este tag".
    var onRemoveFromTag: (([LibraryEntry]) -> Void)? = nil
    /// Entrar en una subcarpeta (solo bibliotecas; navega el NavigationStack).
    var onOpenFolder: ((URL) -> Void)? = nil

    @State private var cursor: URL?                         // foco de teclado/hover en modo lista
    @State private var keyboardNav = false                  // solo el teclado auto-scrollea la lista
    @State private var lastScrollAt = Date.distantPast      // margen tras el scroll para no abrir popups
    @State private var lastSelected: URL?
    @State private var cardFrames: [URL: CGRect] = [:]
    @State private var marquee: CGRect?
    @State private var dragBase: Set<URL> = []
    @State private var commandHeld = false                  // solo entonces calculamos marcos (perf scroll)
    @State private var quickLookURL: URL?
    @State private var hoveredEntry: LibraryEntry?          // documento bajo el cursor
    @State private var previewEntry: LibraryEntry?          // documento con panel abierto
    @State private var window: NSWindow?
    @State private var openTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?
    @State private var preview = PreviewWindowController()

    /// Ancho mínimo de tarjeta según el slider de tamaño (acotado al rango válido).
    private var columns: [GridItem] {
        let size = min(max(appearance.cardSize, Self.cardSizeRange.lowerBound), Self.cardSizeRange.upperBound)
        return [GridItem(.adaptive(minimum: size, maximum: size * 1.35), spacing: 26)]
    }

    static let cardSizeRange: ClosedRange<Double> = 110...190

    /// Entrada "enfocada" para atajos de teclado (en lista manda el cursor).
    private var focusedDoc: LibraryEntry? { previewEntry ?? hoveredEntry ?? cursorEntry }
    private var cursorEntry: LibraryEntry? { entries.first { $0.id == cursor } }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                if appearance.viewMode == .list {
                    listBody
                } else {
                    gridBody
                }
                if appearance.viewMode == .grid, let marquee {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(appearance.tone.accent.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(appearance.tone.accent.opacity(0.7)))
                        .frame(width: marquee.width, height: marquee.height)
                        .offset(x: marquee.minX, y: marquee.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "docgrid")
            // El gesto va DENTRO del espacio docgrid: así su posición y los marcos
            // de las tarjetas comparten origen y la marquesina acierta tras hacer scroll.
            .simultaneousGesture(marqueeGesture)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { gridSel.clear() }   // doble clic fuera de un documento → deseleccionar (todo el viewport)
        .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background {
            LibraryBackground(mode: appearance.mode, tone: appearance.tone)
        }
        .background(WindowReader { newWindow in
            newWindow?.acceptsMouseMovedEvents = true
            window = newWindow
        })
        .background(KeyMonitorView(handler: handleKey))     // atajos fiables (sin foco)
        .background(MouseMonitor(handler: handleMouse))     // cierre por geometría + clic-fuera
        .onChange(of: previewEntry?.id) { _, _ in updatePanel() }
        .onChange(of: searchActive) { _, active in
            if active { openTask?.cancel(); closeTask?.cancel(); previewEntry = nil }
        }
        .quickLookPreview($quickLookURL)
        .onAppear { gridSel.available = entries.filter { !$0.isDirectory }.map(\.id); gridSel.clear() }
        .onChange(of: entries.map(\.id)) { _, _ in
            gridSel.available = entries.filter { !$0.isDirectory }.map(\.id)
        }
        .onDisappear {
            openTask?.cancel(); closeTask?.cancel()
            previewEntry = nil
            preview.hide()
            gridSel.clear()
        }
    }

    private var folderEntries: [LibraryEntry] { entries.filter(\.isDirectory) }
    private var docEntries: [LibraryEntry] { entries.filter { !$0.isDirectory } }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !folderEntries.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(folderEntries) { entry in
                        cell(for: entry).onHover { inside in handleHover(entry, inside) }
                    }
                }
            }
            if !folderEntries.isEmpty && !docEntries.isEmpty {
                Divider().padding(.vertical, 2)   // separador carpetas / documentos sueltos
            }
            if !docEntries.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(docEntries) { entry in
                        cell(for: entry).onHover { inside in handleHover(entry, inside) }
                    }
                }
            }
        }
        .padding(24)
    }

    private var listBody: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 3) {
                ForEach(folderEntries) { entry in
                    entryListRow(entry).id(entry.id)
                }
                if !folderEntries.isEmpty && !docEntries.isEmpty {
                    Divider().padding(.vertical, 4)
                }
                ForEach(docEntries) { entry in
                    entryListRow(entry).id(entry.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .onChange(of: cursor) { _, value in
                guard keyboardNav, let value else { return }   // el hover NO arrastra la lista
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func entryListRow(_ entry: LibraryEntry) -> some View {
        let isCursor = cursor == entry.id
        let isSelected = gridSel.selected.contains(entry.id)
        return listRowContent(entry)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? appearance.tone.accent.opacity(0.22)
                          : (isCursor ? Color.primary.opacity(0.08) : Color.clear))   // feedback de hover/cursor
            )
            .contentShape(Rectangle())     // toda la fila es clicable
            .onHover { inside in
                if inside { keyboardNav = false; cursor = entry.id }
                handleHover(entry, inside)
            }
            .onTapGesture(count: 2) { activate(entry) }
            .onTapGesture { entry.isDirectory ? activate(entry) : selectTapped(entry) }
            .contextMenu { if !entry.isDirectory { documentMenu(for: entry) } }
    }

    private func listRowContent(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                .foregroundStyle(entry.isDirectory ? Color.secondary : (entry.docType?.accentColor ?? .secondary))
                .frame(width: 22)
            Text(entry.name).lineLimit(1)
            Spacer(minLength: 8)
            if let label = entry.docType?.label {
                Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let date = entry.modified {
                Text(date.formatted(.relative(presentation: .named).locale(Localization.shared.locale)))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 110, alignment: .trailing)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
    }

    /// Activa una entrada: carpeta → entrar; documento → abrir.
    private func activate(_ entry: LibraryEntry) {
        if entry.isDirectory { onOpenFolder?(entry.resolvedURL) } else { open(entry) }
    }

    private func moveCursor(_ delta: Int) {
        guard !entries.isEmpty else { return }
        keyboardNav = true
        let ids = entries.map(\.id)
        let current = cursor.flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = max(0, min(ids.count - 1, current + delta))
        cursor = ids[next]
    }

    /// Barra inferior: contador + slider de tamaño (solo rejilla) + conmutador rejilla/lista.
    private var bottomBar: some View {
        @Bindable var appearance = appearance
        return HStack(spacing: 14) {
            Text(countLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if appearance.viewMode == .grid {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.3x3.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    Slider(value: $appearance.cardSize, in: Self.cardSizeRange)
                        .frame(width: 120).controlSize(.small)
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $appearance.viewMode) {
                Image(systemName: "square.grid.2x2").tag(GridViewMode.grid)
                Image(systemName: "list.bullet").tag(GridViewMode.list)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 84)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var countLabel: String {
        let folders = entries.filter(\.isDirectory).count
        let docs = entries.count - folders
        var parts: [String] = []
        if folders > 0 { parts.append("\(folders) \(folders == 1 ? T("folder", "carpeta") : T("folders", "carpetas"))") }
        parts.append("\(docs) \(docs == 1 ? T("document", "documento") : T("documents", "documentos"))")
        return parts.joined(separator: " · ")
    }

    /// ⌘ + arrastrar → marquesina para seleccionar varios de una pasada.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("docgrid"))
            .onChanged { value in
                guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return }
                if marquee == nil { dragBase = gridSel.selected }   // arranca: conserva lo ya marcado
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marquee = rect
                let hits = cardFrames.filter { $0.value.intersects(rect) }.map(\.key)
                gridSel.selected = dragBase.union(hits)
            }
            .onEnded { _ in marquee = nil }
    }

    @ViewBuilder
    private func cell(for entry: LibraryEntry) -> some View {
        if entry.isDirectory {
            NavigationLink(value: entry.resolvedURL) {
                PocketCard(entry: entry)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .hoverLift()
        } else {
            DocCard(entry: entry, coverPage: covers.page(for: docKey(entry)))
                .overlay {
                    if gridSel.selected.contains(entry.id) {
                        // Lavado de acento (no borde): marca la selección sin comerse el documento.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(appearance.tone.accent.opacity(0.22))
                    }
                }
                .background {
                    if commandHeld {   // marcos solo durante ⌘ (marquesina); fuera de eso, sin coste en scroll
                        GeometryReader { geo in
                            Color.clear.preference(key: CardFramesKey.self,
                                                   value: [entry.id: geo.frame(in: .named("docgrid"))])
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { open(entry) }
                .onTapGesture { selectTapped(entry) }
                .contextMenu { documentMenu(for: entry) }
                .hoverLift()
        }
    }

    // MARK: Selección múltiple (⌘ alterna · ⇧ rango · clic simple limpia)

    private func selectTapped(_ entry: LibraryEntry) {
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        if mods.contains(.command) {
            if gridSel.selected.contains(entry.id) { gridSel.selected.remove(entry.id) } else { gridSel.selected.insert(entry.id) }
        } else if mods.contains(.shift), let last = lastSelected {
            let docs = entries.filter { !$0.isDirectory }.map(\.id)
            if let a = docs.firstIndex(of: last), let b = docs.firstIndex(of: entry.id) {
                gridSel.selected.formUnion(docs[min(a, b)...max(a, b)])
            } else {
                gridSel.selected.insert(entry.id)
            }
        } else {
            gridSel.selected = [entry.id]
        }
        lastSelected = entry.id
    }

    /// Documentos sobre los que actúa una acción por lotes: la selección si el
    /// clic-derecho cae sobre ella (y hay varios), si no solo el documento clicado.
    private func tagTargets(_ entry: LibraryEntry) -> [LibraryEntry] {
        if gridSel.selected.contains(entry.id), gridSel.selected.count > 1 {
            return entries.filter { gridSel.selected.contains($0.id) }
        }
        return [entry]
    }

    private func docRef(for entry: LibraryEntry) -> DocRef {
        let path = entry.resolvedURL.standardizedFileURL.path
        return DocRef(url: entry.resolvedURL, library: libraryName(entry), noteID: search.noteID(forPath: path))
    }

    /// Clave estable del documento (id de nota si está digerido, si no ruta).
    private func docKey(_ entry: LibraryEntry) -> String {
        let path = entry.resolvedURL.standardizedFileURL.path
        return search.noteID(forPath: path) ?? path
    }

    /// Abre el selector de tag asegurando que quede ENCIMA: oculta antes el popup
    /// de hover (NSPanel) para que no tape al selector.
    private func addTag(_ targets: [LibraryEntry]) {
        openTask?.cancel(); closeTask?.cancel()
        previewEntry = nil
        requestAddToTag(targets.map(docRef(for:)))
    }

    /// Abre el panel al pasar el ratón sobre un DOCUMENTO con retardo (~600 ms).
    /// Las carpetas no muestran panel.
    private func handleHover(_ entry: LibraryEntry, _ inside: Bool) {
        guard !searchActive, !entry.isDirectory else { return }
        // Con ⌘ (selección múltiple) no abrimos popups: interferirían con marcar archivos.
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            openTask?.cancel(); previewEntry = nil
            return
        }
        if inside {
            hoveredEntry = entry
            closeTask?.cancel()
            openTask?.cancel()
            // Margen tras el scroll: si acabas de desplazarte, no abras el popup solo por parar encima.
            guard Date().timeIntervalSince(lastScrollAt) > 0.45 else { return }
            let target = entry
            openTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { previewEntry = target }
            }
        } else {
            if hoveredEntry?.id == entry.id { hoveredEntry = nil }
            openTask?.cancel()
            scheduleClose()
        }
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            if hoveredEntry == nil && !preview.screenFrame.contains(NSEvent.mouseLocation) {
                previewEntry = nil
            }
        }
    }

    /// Movimiento → mantener si el cursor está sobre el panel o sobre una tarjeta
    /// (`hoveredEntry`), si no cerrar. Clic izquierdo fuera del panel → cerrar.
    private func handleMouse(_ event: NSEvent) {
        // ⌘ pulsado: activa el cálculo de marcos (para la marquesina). Siempre se rastrea.
        if event.type == .flagsChanged {
            commandHeld = event.modifierFlags.contains(.command)
            return
        }
        guard !searchActive else { return }

        // El scroll se registra SIEMPRE (haya o no popup abierto) para el margen anti-popup.
        if event.type == .scrollWheel {
            lastScrollAt = Date()
            openTask?.cancel(); closeTask?.cancel()
            previewEntry = nil
            return
        }

        guard previewEntry != nil else { return }
        let inPanel = preview.screenFrame.contains(NSEvent.mouseLocation)
        switch event.type {
        case .mouseMoved:
            if inPanel || hoveredEntry != nil { closeTask?.cancel() } else { scheduleClose() }
        case .leftMouseDown:
            if !inPanel {
                openTask?.cancel(); closeTask?.cancel()
                previewEntry = nil
            }
        default:
            break
        }
    }

    /// Sincroniza el NSPanel con `previewEntry` (solo documentos), junto al cursor.
    private func updatePanel() {
        guard let entry = previewEntry, !entry.isDirectory, let window else {
            preview.hide()
            return
        }
        let content = AnyView(DocumentPreviewPanel(
            entry: entry,
            libraryRoot: libraryRoot(entry),
            libraryName: libraryName(entry),
            vaultStore: vault,
            recents: recents,
            requestAddToTag: { docs in previewEntry = nil; requestAddToTag(docs) },
            onQuickLook: { previewEntry = nil; quickLookURL = entry.resolvedURL },
            onClose: { previewEntry = nil }
        ))
        preview.show(content: content, near: NSEvent.mouseLocation, parent: window, dark: appearance.mode == .dusk)
    }

    /// ↑↓ mueven el cursor (lista) · Espacio Quick Look · Return entra/abre · F Finder · T tag.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard !searchActive, !isEditingText() else { return false }

        if appearance.viewMode == .list {
            if event.keyCode == 125 { moveCursor(1); return true }    // ↓
            if event.keyCode == 126 { moveCursor(-1); return true }   // ↑
        }

        // Espacio alterna Quick Look: si está abierto, lo cierra.
        if event.keyCode == 49 {
            if quickLookURL != nil { quickLookURL = nil; return true }
            if let entry = focusedDoc, !entry.isDirectory { quickLookURL = entry.resolvedURL; return true }
            return false
        }

        guard let entry = focusedDoc else { return false }
        switch event.keyCode {
        case 36, 76:        // Return → entrar (carpeta) / abrir (documento)
            activate(entry)
            return true
        case 3:             // F → Finder
            DocumentActions.revealInFinder(entry.resolvedURL)
            return true
        case 17:            // T → añadir tag (solo documentos)
            guard !entry.isDirectory else { return false }
            addTag(tagTargets(entry))
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func documentMenu(for entry: LibraryEntry) -> some View {
        let targets = tagTargets(entry)
        let countSuffix = targets.count > 1 ? " (\(targets.count))" : ""

        Button(T("Open", "Abrir")) { open(entry) }
        Button("Quick Look") { quickLookURL = entry.resolvedURL }
        Divider()
        Button(T("Add tag…", "Añadir tag…") + countSuffix) { addTag(targets) }
        if let onRemoveFromTag {
            Button(T("Remove from this tag", "Quitar de este tag") + countSuffix, role: .destructive) { onRemoveFromTag(targets) }
        }
        if entry.docType == .pdf {
            Divider()
            Button(T("Choose cover…", "Elegir portada…")) { requestCoverPick(entry) }
        }
        Divider()
        Button(T("Show in Finder", "Mostrar en Finder")) { DocumentActions.revealInFinder(entry.resolvedURL) }
    }

    /// Abre un documento: lo registra en recientes (clavado a id si está digerido) y lo abre.
    private func open(_ entry: LibraryEntry) {
        let path = entry.resolvedURL.standardizedFileURL.path
        recents.record(url: entry.resolvedURL, library: libraryName(entry), noteID: search.noteID(forPath: path))
        DocumentActions.openInNativeApp(entry.resolvedURL)
    }
}

/// Tarjeta de una subcarpeta: nombre · contador de documentos · recencia.
/// Bolsillo presentacional reutilizable (carpetas y tags): proporción apaisada
/// fija, portadas asomando contenidas, frente de cristal con la info inscrita.
private struct PocketCardView: View {
    @Environment(AppearanceStore.self) private var appearance
    let title: String
    let count: Int
    var subtitle: String? = nil
    var icon: String = "folder.fill"
    let thumbs: [NSImage]

    private let aspect: CGFloat = 1.34   // ancho : alto

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { GeometryReader { geo in art(geo.size) } }
    }

    private func art(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        let scale = min(max(w / 190, 0.78), 1.15)   // suelo para que la fuente no se vuelva ilegible
        let docW = w * 0.30, docH = h * 0.62
        let radius = 14 * scale

        return ZStack(alignment: .bottom) {
            HStack(spacing: -docW * 0.58) {
                ForEach(Array(thumbs.enumerated()), id: \.offset) { i, img in
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: docW, height: docH)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.06)))
                        .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
                        .rotationEffect(.degrees(Double(i) * 7 - Double(thumbs.count - 1) * 3.5), anchor: .bottom)
                }
            }
            .padding(.top, h * 0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            front(width: w, height: h * 0.62, scale: scale)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10 * scale, y: 6 * scale)
    }

    private func front(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Image(systemName: icon)
                .font(.system(size: 14 * scale))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 4 * scale)
            Text(title)
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .help(title)
            HStack(spacing: 6 * scale) {
                Text("[\(String(format: "%03d", count))]")
                if let subtitle { Text("· \(subtitle)") }
            }
            .font(.system(size: 11 * scale, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(13 * scale)
        .frame(width: width, height: height, alignment: .topLeading)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(0.30)
                Rectangle().fill(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                Rectangle().fill(appearance.tone.accent.opacity(0.10))
                Rectangle().fill(LinearGradient(colors: [.clear, .black.opacity(0.30)], startPoint: .center, endPoint: .bottom))
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.28)).frame(height: 1) }
    }
}

/// Carpeta: escanea contador/recencia/muestras y los pinta en `PocketCardView`.
private struct PocketCard: View {
    let entry: LibraryEntry
    @State private var stats: FolderStats?
    @State private var thumbs: [NSImage] = []

    var body: some View {
        PocketCardView(
            title: entry.name,
            count: stats?.documentCount ?? 0,
            subtitle: stats?.latestModified?.relativeShort,
            icon: "folder.fill",
            thumbs: thumbs
        )
        .task(id: entry.resolvedURL) {
            stats = await Task.detached { LibraryScanner.stats(for: entry.resolvedURL) }.value
            let urls = await Task.detached { LibraryScanner.sampleDocuments(in: entry.resolvedURL, limit: 3) }.value
            var imgs: [NSImage] = []
            for url in urls {
                if let img = await ThumbnailLoader.page(0, of: url, size: CGSize(width: 90, height: 116), scale: 2) {
                    imgs.append(img)
                }
            }
            thumbs = imgs
        }
    }
}

/// Tarjeta de un documento: portada tipo con badge de formato, un soft-preview
/// tenue de la primera página de fondo, y nombre + recencia.
private struct DocCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let entry: LibraryEntry
    var coverPage: Int = 0
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                // Relleno barato (queda tapado por la portada): evita un blur por tarjeta al desplazar.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)

                // Soft-preview: primera página tenue, bajo la portada-tipo.
                // .fit: los apaisados se ven enteros y no se salen de la tarjeta.
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.92)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Velo solo arriba (para el badge); el resto del documento queda brillante.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0.30), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // Acento suave del tono elegido.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(appearance.tone.accent.opacity(0.10))

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.docType?.label ?? "")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.docType?.accentColor ?? .gray)
                        .frame(width: 28, height: 2)
                }
                .padding(12)
            }
            .aspectRatio(3.0 / 3.7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)

            Text(entry.name)
                .font(.subheadline)
                .lineLimit(2)
                .help(entry.name)

            if let date = entry.modified {
                Text(date.relativeShort)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(entry.resolvedURL.path)#\(coverPage)") {
            thumbnail = await ThumbnailLoader.page(
                coverPage,
                of: entry.resolvedURL,
                size: CGSize(width: 200, height: 250),
                scale: 2
            )
        }
    }
}

// MARK: - Apoyos de presentación (capa de UI; no contaminan el modelo)

/// Monitor local de teclas (independiente del foco de SwiftUI). El handler
/// devuelve true para consumir la tecla.
private struct KeyMonitorView: NSViewRepresentable {
    var handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.handler = handler
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                (self?.handler?(event) == true) ? nil : event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Monitor local de ratón (movimiento + clic) para gestionar el cierre del panel.
private struct MouseMonitor: NSViewRepresentable {
    var handler: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.handler = handler
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handler: ((NSEvent) -> Void)?
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .scrollWheel, .flagsChanged]) { [weak self] event in
                self?.handler?(event)
                return event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Micro-rebote al pasar el ratón (selección suave estilo Apple).
private struct HoverLift: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.035 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: hovering)
            .onHover { hovering = $0 }
    }
}

private extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}

private extension Date {
    /// Recencia legible en el idioma actual, p. ej. "yesterday" / "ayer".
    @MainActor var relativeShort: String {
        formatted(.relative(presentation: .named).locale(Localization.shared.locale))
    }
}
