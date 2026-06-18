//
//  VaultReader.swift
//  Óculo
//
//  Recorre la carpeta plana de la bóveda y parsea cada nota `.md`.
//  Solo lectura; nunca escribe la bóveda.
//

import Foundation

enum VaultReader {
    nonisolated static func read(vault url: URL) -> [VaultNote] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var notes: [VaultNote] = []
        for fileURL in contents where fileURL.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let frontmatter = Frontmatter.parse(text)
            if frontmatter.isEmpty { continue }
            notes.append(VaultNote(frontmatter: frontmatter))
        }
        return notes
    }
}
