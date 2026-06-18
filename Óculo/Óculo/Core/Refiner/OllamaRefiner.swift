//
//  OllamaRefiner.swift
//  Óculo
//
//  Implementación por defecto de `SearchRefiner`: llama a un Ollama local vía
//  HTTP (/api/chat) con `format: json`, sin stream y `keep_alive` 5 min.
//  Toda incidencia (servidor caído, timeout, modelo ausente, JSON inválido)
//  se traduce a `.unavailable(motivo)` — nunca lanza ni rompe la rápida.
//

import Foundation

nonisolated struct OllamaRefiner: SearchRefiner {
    /// La afinada puede tardar decenas de segundos (es aceptable: la rápida siempre está).
    var timeout: TimeInterval = 120

    func refine(
        query: String,
        notes: [VaultNote],
        model: String,
        endpoint: String
    ) async -> RefinerOutcome {
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        guard !trimmedModel.isEmpty else { return .unavailable(TL("Model is missing in Settings.", "Falta el modelo en Ajustes.")) }
        guard let base = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else {
            return .unavailable(TL("Invalid Ollama endpoint.", "Endpoint de Ollama inválido."))
        }
        guard !notes.isEmpty else { return .unavailable(TL("No vault notes to refine.", "No hay notas de bóveda que afinar.")) }

        var request = URLRequest(url: base.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body = ChatRequest(
            model: trimmedModel,
            messages: [
                .init(role: "system", content: RefinerPrompt.system()),
                .init(role: "user", content: RefinerPrompt.user(query: query, notes: notes))
            ],
            stream: false,
            format: "json",
            keep_alive: "5m",
            options: .init(temperature: 0)
        )
        guard let payload = try? JSONEncoder().encode(body) else {
            return .unavailable(TL("Couldn't prepare the request.", "No se pudo preparar la petición."))
        }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable(TL("Unexpected response from Ollama.", "Respuesta inesperada de Ollama."))
            }
            guard (200..<300).contains(http.statusCode) else {
                // 404 típico: el modelo no está instalado.
                if http.statusCode == 404 {
                    return .unavailable(TL("Model “\(trimmedModel)” is not in Ollama.", "El modelo «\(trimmedModel)» no está en Ollama."))
                }
                return .unavailable(TL("Ollama responded \(http.statusCode).", "Ollama respondió \(http.statusCode)."))
            }
            guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
                return .unavailable(TL("Couldn't read Ollama's response.", "No se pudo leer la respuesta de Ollama."))
            }
            guard let results = Self.parseResults(chat.message.content) else {
                return .unavailable(TL("Refined search returned invalid JSON.", "La afinada no devolvió un JSON válido."))
            }
            return .refined(Array(results.prefix(RefinerPrompt.maxResults)))
        } catch let error as URLError where error.code == .timedOut {
            return .unavailable(TL("Refined search took too long.", "La afinada tardó demasiado."))
        } catch {
            return .unavailable(TL("Ollama unavailable: \(error.localizedDescription)", "Ollama no disponible: \(error.localizedDescription)"))
        }
    }

    /// Parsea el contenido JSON del modelo: `{"results":[{id,why,pages}]}`.
    private static func parseResults(_ content: String) -> [RefinerResult]? {
        guard let data = content.data(using: .utf8) else { return nil }
        guard let wrapper = try? JSONDecoder().decode(ResultsWrapper.self, from: data) else { return nil }
        return wrapper.results.compactMap { item in
            let id = item.id.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty else { return nil }
            return RefinerResult(
                id: id,
                why: item.why.trimmingCharacters(in: .whitespaces),
                pages: item.pages?.compactMap(\.intValue) ?? []
            )
        }
    }
}

// MARK: - Forma del cable (Ollama /api/chat)

private nonisolated struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct Options: Encodable { let temperature: Double }
    let model: String
    let messages: [Message]
    let stream: Bool
    let format: String
    let keep_alive: String
    let options: Options
}

private nonisolated struct ChatResponse: Decodable {
    struct Message: Decodable { let content: String }
    let message: Message
}

private nonisolated struct ResultsWrapper: Decodable {
    struct Item: Decodable {
        let id: String
        let why: String
        let pages: [IntOrString]?
    }
    let results: [Item]
}

/// Tolera que el modelo devuelva páginas como número o como cadena ("12").
private nonisolated enum IntOrString: Decodable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i) }
        else { self = .string((try? c.decode(String.self)) ?? "") }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        }
    }
}
