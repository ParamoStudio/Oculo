//
//  LibraryScanner.swift
//  Óculo
//
//  Recorrido de una carpeta: resuelve symlinks, filtra tipos de lectura,
//  oculta dotfiles y sidecars de metadata. Puro, sin estado propio.
//

import Foundation

/// Resumen de una carpeta para su tarjeta-bolsillo: cuántos documentos contiene
/// (recursivo) y cuándo se tocó el más reciente.
nonisolated struct FolderStats: Sendable {
    let documentCount: Int
    let latestModified: Date?
}

enum LibraryScanner {

    /// Lista las entradas de una carpeta (un nivel; el recorrido profundo es perezoso).
    nonisolated static func scan(directory: URL) -> [LibraryEntry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }

        let siblingNames = Set(contents.map { $0.lastPathComponent })
        var entries: [LibraryEntry] = []

        for url in contents {
            let name = url.lastPathComponent

            // Oculta dotfiles (p. ej. .biblioteca-generada, .DS_Store).
            if name.hasPrefix(".") { continue }

            // Sigue el symlink a su destino. Un enlace colgante se omite con gracia.
            let resolved = url.resolvingSymlinksInPath()
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir) else { continue }

            let modified = (try? resolved.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate

            // El tipo manda sobre "ser directorio": un .pages es un paquete (carpeta
            // en disco) pero es un documento, no una categoría en la que entrar.
            if let type = DocumentType(extension: url.pathExtension) {
                // Oculta sidecars <documento.ext>.md que ensombrecen a un hermano.
                if isMetadataSidecar(name: name, siblings: siblingNames) { continue }
                entries.append(LibraryEntry(
                    displayURL: url,
                    resolvedURL: resolved,
                    isDirectory: false,
                    docType: type,
                    modified: modified
                ))
            } else if isDir.boolValue {
                // Una carpeta sin ningún documento legible en su subárbol es ruido: se oculta.
                guard containsReadableDocument(in: resolved) else { continue }
                entries.append(LibraryEntry(
                    displayURL: url,
                    resolvedURL: resolved,
                    isDirectory: true,
                    docType: nil,
                    modified: modified
                ))
            }
            // else: archivo de tipo no-lectura → ignorado.
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory  // carpetas primero
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Cuenta recursiva de documentos legibles dentro de una carpeta y la fecha
    /// más reciente entre ellos. No desciende en paquetes (.pages, etc.).
    nonisolated static func stats(for directory: URL) -> FolderStats {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return FolderStats(documentCount: 0, latestModified: nil)
        }

        var count = 0
        var latest: Date?

        for case let url as URL in enumerator {
            if looksLikeSidecar(name: url.lastPathComponent) { continue }
            guard DocumentType(extension: url.pathExtension) != nil else { continue }
            count += 1
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate {
                if let current = latest { if date > current { latest = date } }
                else { latest = date }
            }
        }

        return FolderStats(documentCount: count, latestModified: latest)
    }

    /// Primeros documentos legibles del subárbol (para las portadas del bolsillo).
    /// No desciende en paquetes; salida temprana al alcanzar `limit`.
    nonisolated static func sampleDocuments(in directory: URL, limit: Int = 3) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            if looksLikeSidecar(name: url.lastPathComponent) { continue }
            if DocumentType(extension: url.pathExtension) != nil {
                found.append(url.resolvingSymlinksInPath())
                if found.count >= limit { break }
            }
        }
        return found
    }

    /// `true` en cuanto encuentra un documento legible en el subárbol (salida temprana).
    /// No desciende en paquetes (un .pages cuenta como documento por sí mismo).
    nonisolated static func containsReadableDocument(in directory: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }
        for case let url as URL in enumerator {
            if looksLikeSidecar(name: url.lastPathComponent) { continue }
            if DocumentType(extension: url.pathExtension) != nil { return true }
        }
        return false
    }

    /// `true` si `name` tiene forma de sidecar (`paper.pdf.md`): doble extensión
    /// `.md` sobre un tipo legible. No comprueba si el documento padre existe.
    private nonisolated static func looksLikeSidecar(name: String) -> Bool {
        let ns = name as NSString
        guard ns.pathExtension.lowercased() == "md" else { return false }
        let baseExt = (ns.deletingPathExtension as NSString).pathExtension
        return DocumentType(extension: baseExt) != nil
    }

    /// Sidecar real: tiene forma de sidecar **y** su documento padre existe al lado.
    private nonisolated static func isMetadataSidecar(name: String, siblings: Set<String>) -> Bool {
        guard looksLikeSidecar(name: name) else { return false }
        let base = (name as NSString).deletingPathExtension   // "paper.pdf"
        return siblings.contains(base)
    }
}
