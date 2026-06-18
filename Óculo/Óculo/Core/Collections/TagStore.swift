//
//  TagStore.swift
//  Óculo
//
//  Tags (la evolución de "Favoritos"): carpetas virtuales en el almacén propio
//  de Óculo (`tags.json` en Application Support, exportable). NO tocan los
//  documentos originales. Cada tag agrupa `DocRef` clavados a id de nota cuando
//  existe (sobreviven a mover/renombrar); si no, a ruta.
//

import Foundation
import Observation

nonisolated struct Tag: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var members: [DocRef]

    init(id: UUID = UUID(), name: String, members: [DocRef] = []) {
        self.id = id
        self.name = name
        self.members = members
    }
}

@MainActor
@Observable
final class TagStore {
    private(set) var tags: [Tag] = []

    private let fileURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tags.json")
        tags = Self.load(from: fileURL)
    }

    func tag(_ id: UUID) -> Tag? { tags.first { $0.id == id } }

    /// Reemplaza todos los tags (import de configuración).
    func replaceAll(_ newTags: [Tag]) {
        tags = newTags
        sortAndPersist()
    }

    @discardableResult
    func create(_ name: String) -> Tag {
        let tag = Tag(name: name)
        tags.append(tag)
        sortAndPersist()
        return tag
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[i].name = name
        sortAndPersist()
    }

    func delete(_ id: UUID) {
        tags.removeAll { $0.id == id }   // no toca los documentos
        persist()
    }

    /// Añade documentos a un tag (sin duplicar por identidad de DocRef).
    func add(_ refs: [DocRef], to id: UUID) {
        guard let i = tags.firstIndex(where: { $0.id == id }) else { return }
        let existing = Set(tags[i].members.map(\.id))
        tags[i].members.append(contentsOf: refs.filter { !existing.contains($0.id) })
        persist()
    }

    /// Quita documentos de un tag por identidad.
    func remove(_ refIDs: Set<String>, from id: UUID) {
        guard let i = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[i].members.removeAll { refIDs.contains($0.id) }
        persist()
    }

    private func sortAndPersist() {
        tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tags) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [Tag] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Tag].self, from: data) else { return [] }
        return list
    }
}
