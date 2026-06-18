//
//  SearchIndexer.swift
//  Óculo
//
//  Enumera recursivamente los documentos legibles de una biblioteca (resolviendo
//  symlinks, saltando dotfiles, paquetes y sidecars `<doc.ext>.md`).
//

import Foundation

enum SearchIndexer {
    nonisolated static func documents(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if looksLikeSidecar(name) { continue }
            guard DocumentType(extension: url.pathExtension) != nil else { continue }
            result.append(url.resolvingSymlinksInPath())
        }
        return result
    }

    /// `nombre.ext.md` sobre un tipo legible → sidecar de metadata, no documento.
    private nonisolated static func looksLikeSidecar(_ name: String) -> Bool {
        let ns = name as NSString
        guard ns.pathExtension.lowercased() == "md" else { return false }
        let baseExt = (ns.deletingPathExtension as NSString).pathExtension
        return DocumentType(extension: baseExt) != nil
    }
}
