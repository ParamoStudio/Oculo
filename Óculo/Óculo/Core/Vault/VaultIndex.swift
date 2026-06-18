//
//  VaultIndex.swift
//  Óculo
//
//  Índices derivados de las notas: content_hash → nota e id → nota.
//  Es caché regenerable (se reconstruye leyendo la bóveda).
//

import Foundation

struct VaultIndex: Sendable {
    private let byHash: [String: VaultNote]
    private let byID: [String: VaultNote]
    /// Notas con `id` (entrada de la afinada exhaustiva sobre toda la bóveda).
    let identified: [VaultNote]
    let count: Int

    init(notes: [VaultNote]) {
        var hash: [String: VaultNote] = [:]
        var ids: [String: VaultNote] = [:]
        for note in notes {
            if !note.contentHash.isEmpty { hash[note.contentHash] = note }
            if !note.id.isEmpty { ids[note.id] = note }
        }
        byHash = hash
        byID = ids
        identified = notes.filter { !$0.id.isEmpty }
        count = notes.count
    }

    var isEmpty: Bool { byHash.isEmpty && byID.isEmpty }

    func note(forHash hash: String) -> VaultNote? { byHash[hash] }
    func note(forID id: String) -> VaultNote? { byID[id] }
}
