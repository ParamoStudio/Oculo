//
//  Frontmatter.swift
//  Óculo
//
//  Lector tolerante de frontmatter YAML (subconjunto del contrato de la bóveda):
//  escalares, listas en línea `[a, b]`, listas en bloque `- item`, y escalares
//  plegados `>` / literales `|`. Lee lo conocido e ignora lo demás.
//

import Foundation

nonisolated enum FrontmatterValue: Sendable {
    case scalar(String)
    case list([String])
}

nonisolated enum Frontmatter {
    /// Extrae y parsea el bloque `--- … ---` al inicio del texto.
    static func parse(_ text: String) -> [String: FrontmatterValue] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }

        // Cuerpo del frontmatter (hasta el siguiente "---").
        var body: [String] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            body.append(line)
        }

        var result: [String: FrontmatterValue] = [:]
        var i = 0
        while i < body.count {
            let raw = body[i]
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }

            let indent = raw.prefix { $0 == " " }.count
            guard indent == 0, let colon = raw.firstIndex(of: ":") else { i += 1; continue }

            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            let after = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if after == ">" || after == "|" {
                // Escalar en bloque (plegado o literal).
                var buffer: [String] = []
                i += 1
                while i < body.count {
                    let l = body[i]
                    if l.trimmingCharacters(in: .whitespaces).isEmpty { buffer.append(""); i += 1; continue }
                    if l.prefix(while: { $0 == " " }).count == 0 { break }
                    buffer.append(l.trimmingCharacters(in: .whitespaces)); i += 1
                }
                result[key] = .scalar(buffer.joined(separator: " ").trimmingCharacters(in: .whitespaces))
            } else if after.isEmpty {
                // Posible lista en bloque (`- item`).
                var items: [String] = []
                i += 1
                while i < body.count {
                    let l = body[i]
                    if l.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
                    if l.prefix(while: { $0 == " " }).count == 0 { break }
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") { items.append(unquote(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))) }
                    i += 1
                }
                result[key] = .list(items)
            } else if after.hasPrefix("[") && after.hasSuffix("]") {
                // Lista en línea.
                let inner = String(after.dropFirst().dropLast())
                let items = inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                result[key] = .list(items)
                i += 1
            } else {
                result[key] = .scalar(unquote(after))
                i += 1
            }
        }
        return result
    }

    private static func unquote(_ s: String) -> String {
        var t = s
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")), t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}

nonisolated extension Dictionary where Key == String, Value == FrontmatterValue {
    func scalar(_ key: String) -> String? {
        if case .scalar(let s) = self[key], !s.isEmpty { return s }
        return nil
    }

    func list(_ key: String) -> [String] {
        switch self[key] {
        case .list(let items): return items
        case .scalar(let s) where !s.isEmpty: return [s]
        default: return []
        }
    }
}
