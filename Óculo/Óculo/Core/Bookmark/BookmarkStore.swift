//
//  BookmarkStore.swift
//  Óculo
//
//  Persiste los bookmarks de las bibliotecas en Application Support.
//  Esto es estado propio (permiso, no datos): exportable y prescindible.
//  Vaciarlo no pierde ningún documento.
//

import Foundation

/// Registro persistido de una biblioteca: identidad, nombre y bookmark.
struct LibraryRecord: Codable, Identifiable {
    let id: UUID
    var name: String
    var bookmark: Data
}

@MainActor
final class BookmarkStore {
    private let fileURL: URL

    nonisolated init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory

        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("libraries.json")
    }

    func load() -> [LibraryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([LibraryRecord].self, from: data)) ?? []
    }

    func save(_ records: [LibraryRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
