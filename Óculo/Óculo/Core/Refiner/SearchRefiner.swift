//
//  SearchRefiner.swift
//  Óculo
//
//  Borde Óculo↔afinada. El núcleo no se acopla a Ollama: dispara un proceso
//  externo OPCIONAL a través de este protocolo. La degradación es un VALOR
//  (`.unavailable`), no una excepción: la afinada nunca rompe la búsqueda rápida.
//
//  Frontera (handoff): entrada {query, metadata de bóveda, model, endpoint};
//  salida [{id, why, pages}] ordenada por relevancia.
//

import Foundation

/// Una propuesta del refinador, ya con su trazabilidad.
nonisolated struct RefinerResult: Sendable {
    let id: String        // id de nota de bóveda (se resuelve al documento)
    let why: String       // una frase: por qué encaja
    let pages: [Int]      // de topic_pages si aplica; vacío si no
}

/// Resultado de afinar: o propuestas, o no disponible (con motivo legible).
nonisolated enum RefinerOutcome: Sendable {
    case refined([RefinerResult])
    case unavailable(String)
}

/// Cualquier motor de afinada. La implementación por defecto es `OllamaRefiner`.
nonisolated protocol SearchRefiner: Sendable {
    func refine(
        query: String,
        notes: [VaultNote],
        model: String,
        endpoint: String
    ) async -> RefinerOutcome
}

extension SearchRefiner {
    /// Tope de propuestas que mostramos (ranking de relevancia).
    static var maxResults: Int { 5 }
}
