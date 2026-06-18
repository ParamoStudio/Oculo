//
//  Localization.swift
//  Óculo
//
//  Localización ligera y reactiva ES/EN. La UI llama a `T("English", "Castellano")`
//  (primer argumento: inglés, por defecto). Como `T` lee la propiedad observable
//  `Localization.shared.language` dentro del body de las vistas, SwiftUI re-renderiza
//  al cambiar el idioma. Las fechas/números usan `Localization.shared.locale`.
//

import Foundation
import Observation

enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case en
    case es

    var id: String { rawValue }
    var label: String { self == .en ? "English" : "Castellano" }
    var locale: Locale { Locale(identifier: self == .en ? "en_US" : "es_ES") }
}

/// Copia no aislada del idioma para código fuera del MainActor (p. ej. el refinador).
nonisolated(unsafe) private var cachedLanguage: AppLanguage = .en

@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    var language: AppLanguage { didSet { cachedLanguage = language; persist() } }

    var locale: Locale { language.locale }

    private let fileURL: URL

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("language.json")

        if let data = try? Data(contentsOf: fileURL),
           let lang = try? JSONDecoder().decode(AppLanguage.self, from: data) {
            language = lang
        } else {
            language = .en   // inglés por defecto
        }
        cachedLanguage = language
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(language) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Devuelve la cadena según el idioma actual. Primer argumento: inglés (por defecto).
/// Reactivo en vistas (lee la propiedad observable).
@MainActor
func T(_ en: String, _ es: String) -> String {
    Localization.shared.language == .es ? es : en
}

/// Versión no aislada (para código fuera del MainActor, p. ej. el refinador).
nonisolated func TL(_ en: String, _ es: String) -> String {
    cachedLanguage == .es ? es : en
}
