//
//  Library.swift
//  Óculo
//
//  Una raíz de biblioteca: una carpeta cualquiera elegida por el usuario.
//

import Foundation

struct Library: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Carpeta raíz resuelta desde el bookmark.
    let url: URL
    /// El bookmark resolvió pero conviene regenerarlo.
    let isStale: Bool
}
