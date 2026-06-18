//
//  SearchDatabase.swift
//  Óculo
//
//  Índice rápido SQLite FTS5 (GRDB), regenerable. Caché en Application Support.
//  Ranking BM25F ponderado por campo: título/aliases > tags/topics > resumen/cuerpo > nombre.
//

import Foundation
import GRDB

/// Dónde busca: todas las bibliotecas, una biblioteca, o un conjunto de rutas
/// (para tags y Favoritos, que son colecciones, no bibliotecas).
enum SearchScope: Sendable, Equatable {
    case all
    case library(String)
    case paths(Set<String>)
}

/// Fila a indexar: un documento + (si existe) la metadata de su nota de bóveda
/// + los tags propios de Óculo (`usertags`, curación manual del usuario).
struct SearchRow: Sendable {
    let path: String
    let library: String
    let name: String
    let title: String
    let aliases: String
    let tags: String
    let topics: String
    let summary: String
    let body: String
    var usertags: String

    init(path: String, library: String, name: String, note: VaultNote?, usertags: String = "") {
        self.path = path
        self.library = library
        self.name = name
        title = note?.title ?? ""
        aliases = note?.aliases.joined(separator: " ") ?? ""
        tags = note?.tags.joined(separator: " ") ?? ""
        topics = note?.topics.joined(separator: " ") ?? ""
        summary = note?.summary ?? ""
        body = ""
        self.usertags = usertags
    }
}

/// Resultado de la búsqueda rápida.
struct SearchHit: Identifiable, Sendable {
    let path: String
    let library: String
    let name: String
    let title: String
    let score: Double

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayTitle: String { title.isEmpty ? name : title }
}

final class SearchDatabase {
    private let dbQueue: DatabaseQueue

    init() throws {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("search-index.sqlite").path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(virtualTable: "documents", using: FTS5()) { t in
                t.tokenizer = .unicode61()      // quita diacríticos: "búsqueda" ≈ "busqueda"
                t.column("path").notIndexed()
                t.column("library").notIndexed()
                t.column("name")
                t.column("title")
                t.column("aliases")
                t.column("tags")
                t.column("topics")
                t.column("summary")
                t.column("body")
            }
        }
        // El índice es caché regenerable: recreo la tabla con la columna usertags;
        // el rebuild la repuebla en el próximo arranque.
        migrator.registerMigration("v2-usertags") { db in
            try db.drop(table: "documents")
            try db.create(virtualTable: "documents", using: FTS5()) { t in
                t.tokenizer = .unicode61()
                t.column("path").notIndexed()
                t.column("library").notIndexed()
                t.column("name")
                t.column("title")
                t.column("aliases")
                t.column("tags")
                t.column("topics")
                t.column("summary")
                t.column("body")
                t.column("usertags")   // tags propios de Óculo (curación manual)
            }
        }
        try migrator.migrate(dbQueue)
    }

    /// Reemplaza todo el índice (rebuild completo; el índice es regenerable).
    func replaceAll(_ rows: [SearchRow]) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM documents")
            let insert = """
            INSERT INTO documents (path, library, name, title, aliases, tags, topics, summary, body, usertags)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            for r in rows {
                try db.execute(sql: insert, arguments: [
                    r.path, r.library, r.name, r.title, r.aliases, r.tags, r.topics, r.summary, r.body, r.usertags
                ])
            }
        }
    }

    /// Actualiza solo la columna `usertags` (cambia al añadir/quitar tags) sin
    /// re-enumerar archivos: limpia y reescribe las rutas tagueadas.
    func refreshUserTags(_ byPath: [String: String]) async {
        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE documents SET usertags = ''")
            for (path, tags) in byPath {
                try db.execute(sql: "UPDATE documents SET usertags = ? WHERE path = ?", arguments: [tags, path])
            }
        }
    }

    /// Busca acotando por `scope`. Pesos BM25F: usertags (curación manual) por
    /// encima del título; luego aliases > tags/topics > resumen > nombre/cuerpo.
    func search(_ raw: String, scope: SearchScope = .all, limit: Int = 60) -> [SearchHit] {
        guard let match = Self.ftsQuery(from: raw) else { return [] }

        var clause = ""
        var args: [DatabaseValueConvertible] = [match]
        switch scope {
        case .all:
            break
        case .library(let name):
            clause = "AND library = ?"
            args.append(name)
        case .paths(let paths):
            if paths.isEmpty { return [] }   // colección vacía → nada que buscar
            let placeholders = paths.map { _ in "?" }.joined(separator: ", ")
            clause = "AND path IN (\(placeholders))"
            args.append(contentsOf: paths.map { $0 as DatabaseValueConvertible })
        }

        let sql = """
        SELECT path, library, name, title,
               bm25(documents, 0.0, 0.0, 1.0, 10.0, 8.0, 5.0, 5.0, 2.0, 1.0, 12.0) AS score
        FROM documents
        WHERE documents MATCH ? \(clause)
        ORDER BY score
        LIMIT \(limit)
        """
        return (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
                SearchHit(
                    path: row["path"],
                    library: row["library"],
                    name: row["name"],
                    title: row["title"] ?? "",
                    score: row["score"] ?? 0
                )
            }
        }) ?? []
    }

    /// Consulta FTS5 tolerante: cada término como prefijo, unidos por OR
    /// (más términos casados ⇒ mejor BM25 ⇒ sube en el ranking).
    private static func ftsQuery(from raw: String) -> String? {
        let terms = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " OR ")
    }
}
