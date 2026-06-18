//
//  HashCache.swift
//  Óculo
//
//  Caché regenerable (ruta, tamaño, mtime) → hash, para no re-hashear en cada
//  arranque. Vive en Application Support; borrarla solo obliga a re-hashear.
//

import Foundation

@MainActor
final class HashCache {
    private struct Entry: Codable { var size: Int; var mtime: Double; var hash: String }

    private var entries: [String: Entry]
    private let fileURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("hash-cache.json")
        entries = Self.load(from: fileURL)
    }

    /// Metadatos de archivo usados como llave de invalidación.
    static func fileMeta(_ url: URL) -> (size: Int, mtime: Double) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (values?.fileSize ?? -1, values?.contentModificationDate?.timeIntervalSince1970 ?? -1)
    }

    /// Hash cacheado si (tamaño, mtime) no han cambiado; si no, `nil` (hay que re-hashear).
    func cachedHash(path: String, size: Int, mtime: Double) -> String? {
        guard let e = entries[path], e.size == size, e.mtime == mtime else { return nil }
        return e.hash
    }

    func store(path: String, size: Int, mtime: Double, hash: String) {
        entries[path] = Entry(size: size, mtime: mtime, hash: hash)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
