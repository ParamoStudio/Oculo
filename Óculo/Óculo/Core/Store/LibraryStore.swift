//
//  LibraryStore.swift
//  Óculo
//
//  Estado vivo de la sesión: las bibliotecas abiertas y la selección actual.
//  Reconstruye las bibliotecas desde los bookmarks en cada arranque (test de
//  pureza): el árbol de documentos siempre se deriva del filesystem.
//

import Foundation
import Observation

/// Qué muestra el detalle: una biblioteca, la vista Favoritos (rejilla de tags),
/// o un tag concreto (sus documentos). Recientes NO está aquí: es un panel.
enum SidebarSelection: Hashable {
    case library(UUID)
    case favorites
    case tag(UUID)
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var libraries: [Library] = []
    var selection: SidebarSelection?

    private let access: FileAccessProvider
    private let bookmarks: BookmarkStore
    private var records: [LibraryRecord] = []

    init(
        access: FileAccessProvider = MacFileAccessProvider(),
        bookmarks: BookmarkStore = BookmarkStore()
    ) {
        self.access = access
        self.bookmarks = bookmarks
        restore()
    }

    /// La biblioteca seleccionada actualmente, si la selección es una biblioteca.
    var selectedLibrary: Library? {
        guard case .library(let id) = selection else { return nil }
        return libraries.first { $0.id == id }
    }

    /// Reconstruye las bibliotecas resolviendo los bookmarks persistidos.
    private func restore() {
        records = bookmarks.load()
        libraries = records.compactMap { record in
            guard let resolved = try? access.resolveBookmark(record.bookmark) else { return nil }
            // El acceso queda abierto mientras viva la app (sin sandbox es un no-op).
            access.startAccess(to: resolved.url)
            return Library(
                id: record.id,
                name: record.name,
                url: resolved.url,
                isStale: resolved.isStale
            )
        }
        if selection == nil { selection = libraries.first.map { .library($0.id) } }
    }

    /// Pide al usuario una carpeta y la añade como biblioteca.
    func openLibrary() async {
        guard let url = await access.pickFolder() else { return }
        guard let bookmark = try? access.makeBookmark(for: url) else { return }

        let record = LibraryRecord(id: UUID(), name: url.lastPathComponent, bookmark: bookmark)
        records.append(record)
        bookmarks.save(records)

        access.startAccess(to: url)
        let library = Library(id: record.id, name: record.name, url: url, isStale: false)
        libraries.append(library)
        selection = .library(library.id)
    }

    /// Reemplaza todas las bibliotecas por las importadas (por ruta). Devuelve las
    /// rutas que no existen en este equipo (se omiten; el resto se añade con bookmark fresco).
    func replaceLibraries(_ items: [(name: String, path: String)]) -> [String] {
        for library in libraries { access.stopAccess(to: library.url) }
        records.removeAll()
        libraries.removeAll()

        var missing: [String] = []
        for item in items {
            guard FileManager.default.fileExists(atPath: item.path) else { missing.append(item.path); continue }
            let url = URL(fileURLWithPath: item.path)
            guard let bookmark = try? access.makeBookmark(for: url) else { missing.append(item.path); continue }
            let record = LibraryRecord(id: UUID(), name: item.name, bookmark: bookmark)
            records.append(record)
            access.startAccess(to: url)
            libraries.append(Library(id: record.id, name: item.name, url: url, isStale: false))
        }
        bookmarks.save(records)
        selection = libraries.first.map { .library($0.id) }
        return missing
    }

    /// Quita una biblioteca de Óculo. No toca la carpeta ni los documentos.
    func removeLibrary(id: UUID) {
        if let library = libraries.first(where: { $0.id == id }) {
            access.stopAccess(to: library.url)
        }
        records.removeAll { $0.id == id }
        libraries.removeAll { $0.id == id }
        bookmarks.save(records)
        if selection == .library(id) { selection = libraries.first.map { .library($0.id) } }
    }
}
