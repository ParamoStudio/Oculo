//
//  AppearanceStore.swift
//  Óculo
//
//  Estado de presentación vivo (modo + tono), respaldado por PreferencesStore.
//  Capa de UI: aquí sí se conocen Color/ColorScheme.
//

import SwiftUI
import Observation

/// Un tono: pocas opciones (doctrina). No es un fondo saturado, sino un **tinte
/// sutil del glass** (de un matiz a otro cercano, a baja opacidad) más un
/// **accent** vivo para lo interactivo (selección, anillos, botones).
struct Tone: Identifiable, Sendable {
    let id: Int
    let name: String
    /// Color vivo para selección/elementos interactivos.
    let accent: Color
    /// Matiz vecino para que el tinte tenga una transición de color suave.
    let accentSoft: Color

    /// Muestra del picker.
    var swatch: Color { accent }

    /// Tinte del glass: dos matices cercanos, opacidad baja (más en oscuro).
    func wash(for mode: AppearanceMode) -> [Color] {
        switch mode {
        case .mist:
            [accent.opacity(0.20), accentSoft.opacity(0.11), accent.opacity(0.06)]
        case .dusk:
            [accent.opacity(0.32), accentSoft.opacity(0.19), accent.opacity(0.12)]
        }
    }

    static let all: [Tone] = [
        Tone(id: 0, name: "Iris",
             accent:     rgb(0.435, 0.525, 0.839),
             accentSoft: rgb(0.561, 0.498, 0.839)),
        Tone(id: 1, name: "Peach",
             accent:     rgb(0.878, 0.569, 0.420),
             accentSoft: rgb(0.878, 0.690, 0.420)),
        Tone(id: 2, name: "Sea",
             accent:     rgb(0.310, 0.722, 0.604),
             accentSoft: rgb(0.310, 0.722, 0.753)),
        Tone(id: 3, name: "Rose",
             accent:     rgb(0.788, 0.467, 0.690),
             accentSoft: rgb(0.659, 0.467, 0.788)),
        Tone(id: 4, name: "Slate",
             accent:     rgb(0.490, 0.576, 0.690),
             accentSoft: rgb(0.553, 0.561, 0.690)),
    ]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

@MainActor
@Observable
final class AppearanceStore {
    var mode: AppearanceMode
    var toneIndex: Int
    var viewMode: GridViewMode { didSet { persist() } }
    var cardSize: Double { didSet { persist() } }

    private let store: PreferencesStore

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let prefs = store.load()
        mode = prefs.mode
        toneIndex = prefs.toneIndex
        viewMode = prefs.viewMode
        cardSize = prefs.cardSize
    }

    var colorScheme: ColorScheme {
        mode == .mist ? .light : .dark
    }

    var tone: Tone {
        Tone.all[min(max(toneIndex, 0), Tone.all.count - 1)]
    }

    func toggleMode() {
        mode = (mode == .mist) ? .dusk : .mist
        persist()
    }

    func setTone(_ id: Int) {
        toneIndex = id
        persist()
    }

    /// Aplica de golpe un conjunto de preferencias (import de configuración).
    func apply(mode: AppearanceMode, toneIndex: Int, viewMode: GridViewMode, cardSize: Double) {
        self.mode = mode
        self.toneIndex = toneIndex
        self.viewMode = viewMode
        self.cardSize = cardSize
        persist()
    }

    private func persist() {
        store.save(Preferences(mode: mode, toneIndex: toneIndex, viewMode: viewMode, cardSize: cardSize))
    }
}
