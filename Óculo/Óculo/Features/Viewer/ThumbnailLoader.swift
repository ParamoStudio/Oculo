//
//  ThumbnailLoader.swift
//  Óculo
//
//  Genera la miniatura de la primera página de un documento (QLThumbnailGenerator).
//  Solo lectura; el sistema cachea sus propias representaciones.
//

import AppKit
import PDFKit
import QuickLookThumbnailing

enum ThumbnailLoader {
    static func firstPage(of url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    /// Miniatura de una página concreta (0-based). Página 0 o no-PDF → miniatura
    /// del sistema (firstPage). No produce datos: solo renderiza esa página.
    static func page(_ index: Int, of url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        guard index > 0, url.pathExtension.lowercased() == "pdf" else {
            return await firstPage(of: url, size: size, scale: scale)
        }
        return await Task.detached(priority: .utility) {
            guard let doc = PDFDocument(url: url), index < doc.pageCount, let page = doc.page(at: index) else { return nil }
            let box = page.bounds(for: .cropBox)
            let target = CGSize(width: size.width * scale, height: size.height * scale)
            let factor = min(target.width / box.width, target.height / box.height)
            let pixels = CGSize(width: box.width * factor, height: box.height * factor)
            return page.thumbnail(of: pixels, for: .cropBox)
        }.value
    }
}
