//
//  RecentsStore.swift
//  Óculo
//
//  Documentos abiertos recientemente EN SU APP DEFINITIVA (ni Quick Look ni
//  Finder: solo abrir es señal de interés real). Almacén propio `recents.json`
//  en Application Support, exportable y desechable. Clavados a id de nota cuando
//  existe; si no, a ruta. Tope fijo; el más reciente primero.
//

import Foundation
import Observation

/// Una apertura registrada: la referencia al documento + cuándo se abrió.
nonisolated struct RecentEntry: Codable, Sendable, Identifiable {
    let ref: DocRef
    let openedAt: Date
    var id: String { ref.id }
}

@MainActor
@Observable
final class RecentsStore {
    private(set) var entries: [RecentEntry] = []

    private let fileURL: URL
    private let cap = 30

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("recents.json")
        entries = Self.load(from: fileURL)
    }

    /// Registra una apertura: la pone primera, sin duplicados, respetando el tope.
    func record(_ ref: DocRef) {
        entries.removeAll { $0.id == ref.id }
        entries.insert(RecentEntry(ref: ref, openedAt: Date()), at: 0)
        if entries.count > cap { entries = Array(entries.prefix(cap)) }
        persist()
    }

    /// Conveniencia: registra por URL (con etiqueta de biblioteca e id si se conocen).
    func record(url: URL, library: String?, noteID: String?) {
        record(DocRef(url: url, library: library, noteID: noteID))
    }

    func clear() {
        entries = []
        persist()
    }

    /// Reemplaza los recientes (import de configuración).
    func replaceAll(_ list: [RecentEntry]) {
        entries = Array(list.prefix(cap))
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [RecentEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([RecentEntry].self, from: data) else { return [] }
        return list
    }
}
