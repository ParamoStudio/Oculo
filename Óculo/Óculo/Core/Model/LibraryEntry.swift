//
//  LibraryEntry.swift
//  Óculo
//
//  Una entrada (carpeta o documento) dentro de una carpeta de la biblioteca.
//  Se deriva del filesystem en cada recorrido; Óculo no la posee.
//

import Foundation

nonisolated struct LibraryEntry: Identifiable, Sendable {
    /// URL tal cual aparece en la carpeta (puede ser un symlink). Se usa para mostrar el nombre.
    let displayURL: URL
    /// URL resuelta a su destino real. Se usa para recorrer/abrir.
    let resolvedURL: URL
    let isDirectory: Bool
    /// Tipo de documento si es un archivo legible; `nil` para carpetas.
    let docType: DocumentType?
    /// Fecha de última modificación del destino, si se pudo leer.
    let modified: Date?

    /// Identidad estable por el enlace mostrado.
    var id: URL { displayURL }

    /// Nombre del enlace (puede traer desambiguación entre corchetes), según doctrina.
    var name: String { displayURL.lastPathComponent }
}
