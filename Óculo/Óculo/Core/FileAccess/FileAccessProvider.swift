//
//  FileAccessProvider.swift
//  Óculo
//
//  Frontera portable de acceso a archivos.
//

import Foundation

/// Resultado de resolver un bookmark persistido a una URL utilizable.
struct ResolvedBookmark {
    let url: URL
    /// El bookmark sigue resolviendo pero conviene regenerarlo (la carpeta se movió, etc.).
    let isStale: Bool
}

/// Contrato de acceso a archivos independiente de plataforma.
///
/// La UI y el recorrido de la biblioteca nunca conocen `NSOpenPanel` ni
/// `UIDocumentPicker`: solo hablan con este protocolo. Añadir iPadOS más
/// adelante es **aditivo** —una nueva implementación—, no un reescrito.
///
/// El bookmark es **permiso, no datos**: se persiste en Application Support y
/// vaciarlo no pierde ningún documento (el árbol se reconstruye del filesystem).
@MainActor
protocol FileAccessProvider {
    /// Presenta el selector nativo de carpetas. `nil` si el usuario cancela.
    func pickFolder() async -> URL?

    /// Crea el permiso persistible (bookmark) para una carpeta elegida.
    func makeBookmark(for url: URL) throws -> Data

    /// Resuelve un bookmark a una URL utilizable.
    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark

    /// Comienza el acceso a un recurso. Bajo sandbox abre el *security scope*.
    /// Devuelve `true` si hay que cerrar con `stopAccess` más tarde.
    @discardableResult
    func startAccess(to url: URL) -> Bool

    /// Cesa el acceso iniciado con `startAccess`.
    func stopAccess(to url: URL)
}
