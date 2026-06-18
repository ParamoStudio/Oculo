//
//  DocRef.swift
//  Óculo
//
//  Referencia portable a un documento en el almacén propio de Óculo (recientes,
//  tags). Clavada al `id` de su nota de bóveda cuando existe (sobrevive a mover
//  y renombrar); cae a la ruta si no hay nota. Es caché/preferencia exportable,
//  nunca verdad de documento.
//

import Foundation

nonisolated struct DocRef: Codable, Sendable, Hashable, Identifiable {
    let noteID: String?       // id de la nota de bóveda, si se conocía al guardar
    let path: String          // ruta estándar (reserva / visualización)
    let library: String?      // etiqueta de la biblioteca de origen, si se conocía
    let name: String          // nombre de archivo para mostrar

    /// Identidad estable: por id de nota si existe, si no por ruta.
    var id: String { noteID ?? path }

    /// URL de reserva por ruta (la resolución viva por id la hace quien consume).
    var url: URL { URL(fileURLWithPath: path) }

    init(noteID: String?, path: String, library: String?, name: String) {
        self.noteID = noteID
        self.path = path
        self.library = library
        self.name = name
    }

    init(url: URL, library: String?, noteID: String?) {
        self.noteID = noteID
        self.path = url.standardizedFileURL.path
        self.library = library
        self.name = url.lastPathComponent
    }
}
