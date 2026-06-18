//
//  SearchService.swift
//  Óculo
//
//  Orquesta el índice rápido: lo reconstruye desde las bibliotecas + la bóveda
//  (emparejando cada documento con su nota) y resuelve las consultas rápidas.
//  El índice es caché regenerable.
//

import Foundation
import Observation

/// Una propuesta de la afinada: documento + trazabilidad (por qué + páginas).
struct RefinedHit: Identifiable, Sendable {
    let doc: SearchHit
    let why: String
    let pages: [Int]
    var id: String { doc.id }
}

/// Resultado de afinar: propuestas rankeadas o no disponible (con motivo).
enum AfinadaResult: Sendable {
    case done([RefinedHit])
    case unavailable(String)
}

@MainActor
@Observable
final class SearchService {
    private(set) var isIndexing = false
    private(set) var indexedCount = 0
    /// id de nota → su documento. Resuelve los `id` que devuelve la afinada.
    private(set) var docByNoteID: [String: SearchHit] = [:]
    /// ruta → id de nota. Para clavar recientes/tags a id al abrir.
    private(set) var noteIDByPath: [String: String] = [:]

    /// id de nota del documento en esa ruta, si está digerido.
    func noteID(forPath path: String) -> String? { noteIDByPath[path] }

    private let database: SearchDatabase?
    private let refiner: SearchRefiner

    init(refiner: SearchRefiner = OllamaRefiner()) {
        self.refiner = refiner
        database = try? SearchDatabase()
    }

    /// Reconstruye el índice: enumera documentos de cada biblioteca y los empareja
    /// con su nota de bóveda (por content_hash, con caché de hash) e indexa los
    /// tags propios del usuario (`usertags`).
    func rebuild(libraries: [Library], vault: VaultStore, tags: TagStore) async {
        guard let database else { return }
        isIndexing = true
        defer { isIndexing = false }

        var rows: [SearchRow] = []
        var idMap: [String: SearchHit] = [:]
        var pathMap: [String: String] = [:]
        for library in libraries {
            let urls = await Task.detached { SearchIndexer.documents(in: library.url) }.value
            for url in urls {
                let note = await vault.note(forDocumentAt: url)
                let path = url.standardizedFileURL.path
                rows.append(SearchRow(path: path, library: library.name, name: url.lastPathComponent, note: note))
                if let id = note?.id, !id.isEmpty {
                    idMap[id] = SearchHit(
                        path: path, library: library.name, name: url.lastPathComponent,
                        title: note?.title ?? "", score: 0
                    )
                    pathMap[path] = id
                }
            }
        }

        // Tags propios por ruta viva (id si está digerido; si no, ruta guardada).
        let userTags = Self.userTagsByPath(tags: tags) { ref in
            if let id = ref.noteID, let hit = idMap[id] { return hit.path }
            return ref.path
        }
        for i in rows.indices { rows[i].usertags = userTags[rows[i].path] ?? "" }

        try? await database.replaceAll(rows)
        indexedCount = rows.count
        docByNoteID = idMap
        noteIDByPath = pathMap
    }

    /// Refresca solo `usertags` (al añadir/quitar tags), sin re-enumerar archivos.
    func refreshUserTags(from tags: TagStore) async {
        guard let database else { return }
        let map = Self.userTagsByPath(tags: tags) { ref in
            if let id = ref.noteID, let hit = docByNoteID[id] { return hit.path }
            return ref.path
        }
        await database.refreshUserTags(map)
    }

    /// ruta viva → nombres de tags del usuario (separados por espacio).
    private static func userTagsByPath(tags: TagStore, liveURL: (DocRef) -> String) -> [String: String] {
        var map: [String: [String]] = [:]
        for tag in tags.tags {
            for member in tag.members {
                map[liveURL(member), default: []].append(tag.name)
            }
        }
        return map.mapValues { $0.joined(separator: " ") }
    }

    /// Búsqueda rápida (BM25F), acotada por `scope` (biblioteca, tag/Favoritos, o todo).
    func search(_ query: String, scope: SearchScope = .all) -> [SearchHit] {
        database?.search(query, scope: scope) ?? []
    }

    /// Búsqueda afinada (exhaustiva): pasa la consulta + metadata de bóveda al
    /// refinador y resuelve sus `id` a documentos. Acotada por `scope`. Degradación elegante.
    func refine(_ query: String, notes: [VaultNote], scope: SearchScope = .all, model: String, endpoint: String) async -> AfinadaResult {
        // Compartimenta las notas según el scope activo.
        let scopedNotes: [VaultNote]
        switch scope {
        case .all:
            scopedNotes = notes
        case .library(let name):
            scopedNotes = notes.filter { docByNoteID[$0.id]?.library == name }
        case .paths(let paths):
            scopedNotes = notes.filter { if let p = docByNoteID[$0.id]?.path { return paths.contains(p) }; return false }
        }
        guard !scopedNotes.isEmpty else { return .unavailable(T("No vault notes in this scope.", "No hay notas de bóveda en este ámbito.")) }
        switch await refiner.refine(query: query, notes: scopedNotes, model: model, endpoint: endpoint) {
        case .unavailable(let reason):
            return .unavailable(reason)
        case .refined(let results):
            // Verificación determinista contra la verdad que ya tenemos: solo páginas
            // declaradas en el `topic_pages` real de la nota; lo demás es alucinación y
            // se descarta. Si la nota no tiene topic_pages → sin páginas. (ids ya filtrados.)
            var validPages: [String: Set<Int>] = [:]
            for note in scopedNotes where !note.id.isEmpty {
                validPages[note.id] = Set(note.topicPages.flatMap(\.pages))
            }
            let allowedIDs = Set(scopedNotes.map(\.id))
            let hits = results.compactMap { r -> RefinedHit? in
                guard allowedIDs.contains(r.id), let doc = docByNoteID[r.id] else { return nil }   // fuera de la biblioteca o id inventado
                let allowed = validPages[r.id] ?? []
                let pages = r.pages.filter { allowed.contains($0) }     // descarta páginas inventadas
                return RefinedHit(doc: doc, why: r.why, pages: pages)
            }
            return .done(hits)
        }
    }
}
