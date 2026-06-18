//
//  VaultStore.swift
//  Óculo
//
//  Estado vivo de la bóveda: carga las notas y empareja documentos por
//  content_hash (con caché de hash). Solo lectura; todo es regenerable.
//

import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private(set) var index = VaultIndex(notes: [])
    /// `false` mientras una bóveda configurada aún se está leyendo. El índice de
    /// búsqueda espera a que sea `true` para no reconstruirse sin la bóveda.
    private(set) var isLoaded = false
    private let cache = HashCache()
    private var vaultURL: URL?

    var noteCount: Int { index.count }
    /// Notas con `id` para la afinada (toda la bóveda digerida).
    var allNotes: [VaultNote] { index.identified }

    /// (Re)carga la bóveda desde la carpeta dada (de Ajustes).
    func load(from url: URL?) {
        vaultURL = url
        guard let url else {
            index = VaultIndex(notes: [])
            isLoaded = true            // sin bóveda: "cargado" (vacío) de inmediato
            return
        }
        isLoaded = false
        Task {
            let notes = await Task.detached { VaultReader.read(vault: url) }.value
            index = VaultIndex(notes: notes)
            isLoaded = true
        }
    }

    /// Nota emparejada con el documento por content_hash (o `nil`).
    func note(forDocumentAt url: URL) async -> VaultNote? {
        guard !index.isEmpty else { return nil }
        let (size, mtime) = HashCache.fileMeta(url)
        let path = url.standardizedFileURL.path

        if let cached = cache.cachedHash(path: path, size: size, mtime: mtime) {
            return index.note(forHash: cached)
        }
        guard let hash = await Task.detached(priority: .utility, operation: {
            ContentHasher.sha256(of: url)
        }).value else { return nil }

        cache.store(path: path, size: size, mtime: mtime, hash: hash)
        return index.note(forHash: hash)
    }

    /// Nota por id (para conexiones / recientes / favoritos).
    func note(forID id: String) -> VaultNote? { index.note(forID: id) }
}
