//
//  MacFileAccessProvider.swift
//  Óculo
//
//  Implementación de FileAccessProvider para macOS.
//

import AppKit

/// Acceso a archivos en macOS para la build personal **sin sandbox**.
///
/// Usa bookmarks normales: sin sandbox no hace falta *security scope* y el
/// acceso a la carpeta elegida persiste entre arranques. Bajo App Store (con
/// sandbox) estos bookmarks pasarían a `.withSecurityScope` apuntando a un
/// ancestro común; el resto de la app no cambia.
@MainActor
final class MacFileAccessProvider: FileAccessProvider {

    nonisolated init() {}

    func pickFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Abrir"
        panel.message = "Elige una carpeta para mostrarla como biblioteca."

        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    @discardableResult
    func startAccess(to url: URL) -> Bool {
        // Sin sandbox devuelve `false` (no hay scope que abrir) y es inofensivo.
        url.startAccessingSecurityScopedResource()
    }

    func stopAccess(to url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
