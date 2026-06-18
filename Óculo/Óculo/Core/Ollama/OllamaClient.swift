//
//  OllamaClient.swift
//  Óculo
//
//  Cliente HTTP mínimo para el Ollama local (dependencia externa OPCIONAL).
//  Aquí solo la prueba de conexión; la búsqueda afinada se añade en T3d.
//  Por defecto apunta a 127.0.0.1 (loopback, exento de ATS).
//

import Foundation

struct OllamaClient {
    enum ConnectionResult: Sendable {
        case ok(models: [String])
        case modelMissing(available: [String])
        case unreachable(String)
    }

    /// Comprueba que el servidor responde y si el modelo configurado está disponible.
    func testConnection(model: String, endpoint: String) async -> ConnectionResult {
        guard let base = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else {
            return .unreachable("Endpoint inválido")
        }
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unreachable("Respuesta inesperada del servidor")
            }
            let names = Self.parseModelNames(data)
            let wanted = model.trimmingCharacters(in: .whitespaces)
            let present = wanted.isEmpty || names.contains { $0 == wanted || $0.hasPrefix(wanted + ":") }
            return present ? .ok(models: names) : .modelMissing(available: names)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// Parsea la respuesta de `/api/tags`: `{ "models": [ { "name": "qwen2.5:7b" }, … ] }`.
    private static func parseModelNames(_ data: Data) -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        guard let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return [] }
        return tags.models.map(\.name)
    }
}
