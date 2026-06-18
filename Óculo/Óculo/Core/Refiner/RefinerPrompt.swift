//
//  RefinerPrompt.swift
//  Óculo
//
//  El *prompt* de la afinada como ARTEFACTO AISLADO (se refinará con el set de
//  instrucciones de digestión). Aquí solo se construye el mensaje a Qwen:
//  motor de búsqueda, no chatbot. Entrada = consulta + metadata de bóveda
//  (NUNCA el texto interior de los documentos). Salida esperada = JSON.
//

import Foundation

nonisolated enum RefinerPrompt {
    /// Tope de propuestas que pedimos al modelo (ranking de relevancia).
    static let maxResults = 5

    /// Instrucción de sistema: define el rol y el formato de salida.
    static func system() -> String {
        """
        Eres un motor de búsqueda exhaustiva, NO un asistente conversacional.
        Dada una consulta en lenguaje natural y un listado de documentos (id + metadata),
        devuelve SOLO un objeto JSON con esta forma exacta:

        {"results": [{"id": "<id>", "why": "<una frase>", "pages": [<enteros>]}]}

        Reglas:
        - Incluye SOLO documentos realmente relevantes para la consulta. Si uno no encaja,
          OMÍTELO (no lo listes con un motivo negativo). Mejor pocas propuestas buenas que rellenar.
        - Como máximo \(maxResults) documentos, ORDENADOS de más a menos relevante.
        - `why`: una sola frase breve y AFIRMATIVA de por qué ese documento encaja con la consulta.
        - `pages`: solo páginas que aparezcan en el `topic_pages` del documento elegido; si no hay, lista vacía.
        - NO inventes documentos ni ids ni páginas. Usa solo los del listado.
        - NO respondas la pregunta: conéctala con los documentos.
        - La afinada busca conexiones que la búsqueda rápida podría pasar por alto.
        - Cada documento puede traer `related`: ids de otros documentos conectados. Úsalo para
          traer documentos relacionados con la intención de la consulta aunque no coincidan
          léxicamente (sigue el grafo). Solo ids presentes en el listado.
        - Si ningún documento encaja, devuelve {"results": []}.
        - Responde únicamente con el JSON, sin texto adicional.
        - El campo `why` de cada resultado debe estar en \(TL("English", "castellano")).
        """
    }

    /// Mensaje de usuario: la consulta + la metadata compacta de cada nota.
    static func user(query: String, notes: [VaultNote]) -> String {
        var lines: [String] = []
        lines.append("CONSULTA: \(query)")
        lines.append("")
        lines.append("DOCUMENTOS:")
        for note in notes {
            lines.append(documentBlock(note))
        }
        return lines.joined(separator: "\n")
    }

    /// Metadata de una nota en forma compacta y legible para el modelo.
    private static func documentBlock(_ n: VaultNote) -> String {
        var parts: [String] = ["- id: \(n.id)"]
        if let t = n.title, !t.isEmpty { parts.append("  title: \(t)") }
        if !n.aliases.isEmpty { parts.append("  aliases: \(n.aliases.joined(separator: ", "))") }
        if !n.tags.isEmpty { parts.append("  tags: \(n.tags.joined(separator: ", "))") }
        if !n.topics.isEmpty { parts.append("  topics: \(n.topics.joined(separator: ", "))") }
        if let s = n.summary, !s.isEmpty { parts.append("  summary: \(s)") }
        if !n.topicPages.isEmpty {
            let tp = n.topicPages
                .map { "\($0.topic) → págs \($0.pages.map(String.init).joined(separator: ","))" }
                .joined(separator: "; ")
            parts.append("  topic_pages: \(tp)")
        }
        if !n.related.isEmpty { parts.append("  related: \(n.related.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }
}
