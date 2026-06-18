//
//  GridSelection.swift
//  Óculo
//
//  Selección múltiple de la rejilla activa, compartida con la barra superior
//  (deseleccionar / seleccionar todo). Es estado de sesión, no se persiste.
//

import Foundation
import Observation

@MainActor
@Observable
final class GridSelection {
    /// Documentos seleccionados (por su URL de enlace).
    var selected: Set<URL> = []
    /// Todos los documentos de la rejilla visible (para "seleccionar todo").
    var available: [URL] = []

    var isEmpty: Bool { selected.isEmpty }
    var count: Int { selected.count }

    func clear() { selected.removeAll() }
    func selectAll() { selected = Set(available) }
}
