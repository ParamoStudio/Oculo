//
//  DocumentTypeStyle.swift
//  Óculo
//
//  Estilo de presentación por tipo de documento (capa de UI; no toca el modelo).
//

import SwiftUI

extension DocumentType {
    /// Acento de color por tipo, alineado con el prototipo.
    var accentColor: Color {
        switch self {
        case .pdf:   Color(red: 0.91, green: 0.38, blue: 0.30)
        case .epub:  Color(red: 0.61, green: 0.43, blue: 0.94)
        case .docx:  Color(red: 0.30, green: 0.55, blue: 0.91)
        case .pages: Color(red: 0.94, green: 0.59, blue: 0.23)
        case .txt:   Color(red: 0.27, green: 0.73, blue: 0.48)
        case .odt:   Color(red: 0.23, green: 0.70, blue: 0.70)
        case .md:    Color(red: 0.55, green: 0.57, blue: 0.62)
        }
    }
}
