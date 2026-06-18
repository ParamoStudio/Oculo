//
//  PreferencesStore.swift
//  Óculo
//
//  Preferencias de presentación (modo claro/oscuro y tono). Estado propio,
//  exportable y prescindible: vivir en Application Support, jamás en la
//  biblioteca. No es verdad de documento.
//

import Foundation

/// Identidad visual: claro (Mist) u oscuro (Dusk).
enum AppearanceMode: String, Codable, Sendable {
    case mist
    case dusk
}

/// Cómo se presentan los documentos: rejilla de tarjetas o lista.
enum GridViewMode: String, Codable, Sendable {
    case grid
    case list
}

/// Preferencias persistidas.
struct Preferences: Codable, Sendable {
    var mode: AppearanceMode
    var toneIndex: Int
    var viewMode: GridViewMode
    var cardSize: Double

    init(mode: AppearanceMode = .mist, toneIndex: Int = 0, viewMode: GridViewMode = .grid, cardSize: Double = 150) {
        self.mode = mode
        self.toneIndex = toneIndex
        self.viewMode = viewMode
        self.cardSize = cardSize
    }

    /// Decodificado tolerante: claves nuevas ausentes caen a su valor por defecto.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(AppearanceMode.self, forKey: .mode) ?? .mist
        toneIndex = try c.decodeIfPresent(Int.self, forKey: .toneIndex) ?? 0
        viewMode = try c.decodeIfPresent(GridViewMode.self, forKey: .viewMode) ?? .grid
        cardSize = try c.decodeIfPresent(Double.self, forKey: .cardSize) ?? 150
    }
}

@MainActor
final class PreferencesStore {
    private let fileURL: URL

    nonisolated init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory

        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("preferences.json")
    }

    func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs
    }

    func save(_ prefs: Preferences) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(prefs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
