//
//  DocumentType.swift
//  Óculo
//
//  Tipos de documento de lectura que Óculo muestra. Todo lo demás se ignora.
//

import Foundation

/// Los únicos tipos que Óculo presenta como documentos legibles.
nonisolated enum DocumentType: String, CaseIterable {
    case pdf
    case epub
    case txt
    case docx
    case odt
    case pages
    case md

    /// Crea un tipo a partir de una extensión de archivo (sin distinguir mayúsculas).
    init?(extension ext: String) {
        self.init(rawValue: ext.lowercased())
    }

    /// Etiqueta corta para mostrar (p. ej. "PDF").
    var label: String { rawValue.uppercased() }
}
