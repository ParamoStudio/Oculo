//
//  VaultNote.swift
//  Óculo
//
//  Modelo tolerante de una nota de la bóveda (subconjunto que Óculo lee del
//  contrato). Campos desconocidos se ignoran; ausentes quedan vacíos.
//

import Foundation

/// Tema → páginas donde se trata (para la afinada). Del contrato:
/// `topic_pages: - {topic: feldespato sódico, pages: [2, 4, 87]}`.
nonisolated struct TopicPages: Sendable, Hashable {
    let topic: String
    let pages: [Int]
}

nonisolated struct VaultNote: Identifiable, Sendable {
    let id: String                 // estable; "" si la nota no lo declara
    let contentHash: String        // "sha256:…"; "" si no lo declara
    let sourcePath: String?
    let title: String?
    let aliases: [String]
    let tags: [String]
    let topics: [String]
    let summary: String?
    let topicPages: [TopicPages]
    let related: [String]

    init(frontmatter d: [String: FrontmatterValue]) {
        id = d.scalar("id") ?? ""
        contentHash = d.scalar("content_hash") ?? ""
        sourcePath = d.scalar("source_path")
        title = d.scalar("title")
        aliases = d.list("aliases")
        tags = d.list("tags")
        topics = d.list("topics")
        summary = d.scalar("summary")
        topicPages = Self.parseTopicPages(d.list("topic_pages"))
        related = d.list("related")
    }

    /// Parsea las entradas en línea `{topic: …, pages: [1, 2]}` (tolerante:
    /// admite sin páginas, con/sin llaves, comillas opcionales).
    private static func parseTopicPages(_ raw: [String]) -> [TopicPages] {
        raw.compactMap { entry in
            var s = entry.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("{") && s.hasSuffix("}") { s = String(s.dropFirst().dropLast()) }

            let pages: [Int]
            let topicPart: String
            if let r = s.range(of: "pages:") {
                topicPart = String(s[..<r.lowerBound])
                pages = String(s[r.upperBound...])
                    .drop(while: { $0 != "[" }).dropFirst()
                    .prefix(while: { $0 != "]" })
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            } else {
                topicPart = s
                pages = []
            }

            var topic = topicPart.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            if let r = topic.range(of: "topic:") { topic = String(topic[r.upperBound...]) }
            topic = topic.trimmingCharacters(in: CharacterSet(charactersIn: " ,\"'"))
            return topic.isEmpty ? nil : TopicPages(topic: topic, pages: pages)
        }
    }
}
