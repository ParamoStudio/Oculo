//
//  CoverStore.swift
//  Óculo
//
//  Qué página de cada documento se usa como portada (miniatura). Personalización
//  ligera: NO produce datos nuevos, solo elige qué página renderizar. Almacén
//  propio (`covers.json` en Application Support, exportable), clavado a id de
//  nota cuando existe; si no, a ruta. Página 0 = por defecto (no se guarda).
//

import Foundation
import Observation

@MainActor
@Observable
final class CoverStore {
    private(set) var pages: [String: Int] = [:]   // clave de documento → página (0-based)

    private let fileURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("covers.json")
        pages = Self.load(from: fileURL)
    }

    func page(for key: String) -> Int { pages[key] ?? 0 }

    /// Reemplaza todas las portadas (import de configuración).
    func replaceAll(_ map: [String: Int]) {
        pages = map
        persist()
    }

    func setPage(_ index: Int, for key: String) {
        if index <= 0 { pages[key] = nil } else { pages[key] = index }   // página 1 = por defecto: no ensucia el almacén
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(pages) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: Int] {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return map
    }
}
