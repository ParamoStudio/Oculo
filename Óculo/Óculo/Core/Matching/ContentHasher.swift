//
//  ContentHasher.swift
//  Óculo
//
//  Huella sha256 de los bytes de un documento (por streaming, para PDFs grandes).
//  Formato "sha256:<hex>" para casar con el contrato de la bóveda.
//

import Foundation
import CryptoKit

enum ContentHasher {
    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20  // 1 MB
        while true {
            let data = try? handle.read(upToCount: chunkSize)
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
