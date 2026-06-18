//
//  SidecarMetadata.swift
//  Óculo
//
//  Lee la metadata del sidecar `<documento.ext>.md` (frontmatter YAML simple).
//  Solo lectura; si no hay sidecar, no hay metadata. Óculo no la posee.
//

import Foundation

/// Un par clave/valor del frontmatter del sidecar.
struct MetadataField: Identifiable, Sendable {
    let key: String
    let value: String
    var id: String { key }
}

enum SidecarLoader {
    /// Busca el sidecar `<nombre-original-resuelto>.md` junto al documento y
    /// devuelve sus campos de frontmatter, en orden. Vacío si no hay sidecar.
    nonisolated static func load(for resolvedURL: URL) -> [MetadataField] {
        let sidecar = resolvedURL
            .deletingLastPathComponent()
            .appendingPathComponent(resolvedURL.lastPathComponent + ".md")

        guard let text = try? String(contentsOf: sidecar, encoding: .utf8) else { return [] }
        return parseFrontmatter(text)
    }

    /// Parser mínimo de frontmatter: bloque entre `---` con líneas `clave: valor`.
    private nonisolated static func parseFrontmatter(_ text: String) -> [MetadataField] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }

        var fields: [MetadataField] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }                 // fin del frontmatter
            if trimmed.isEmpty { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }

            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)

            // Quita comillas y corchetes de lista, deja una lista por comas.
            if value.hasPrefix("[") && value.hasSuffix("]") {
                value = String(value.dropFirst().dropLast())
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if key.isEmpty || value.isEmpty { continue }
            fields.append(MetadataField(key: key, value: value))
        }
        return fields
    }
}
