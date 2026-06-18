//
//  LibraryBackground.swift
//  Óculo
//
//  Fondo de la biblioteca: frost translúcido (deja ver el escritorio detrás)
//  con un tinte de color sutil del tono encima.
//

import SwiftUI

struct LibraryBackground: View {
    let mode: AppearanceMode
    let tone: Tone

    var body: some View {
        VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
            .overlay {
                LinearGradient(
                    colors: tone.wash(for: mode),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .opacity(0.9)   // algo más translúcido: deja ver un poco más el fondo
            .ignoresSafeArea()
    }
}
