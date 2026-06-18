//
//  DocumentActions.swift
//  Óculo
//
//  Acciones de sistema sobre un documento. Solo lectura: abrir en su app por
//  defecto (para editar/anotar) o mostrarlo en Finder. Nunca modifica el archivo.
//

import AppKit

enum DocumentActions {
    /// Abre el documento en su aplicación por defecto del sistema.
    @MainActor static func openInNativeApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Revela el documento en el Finder.
    @MainActor static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
