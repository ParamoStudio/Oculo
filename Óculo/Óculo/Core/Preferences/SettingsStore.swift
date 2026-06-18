//
//  SettingsStore.swift
//  Óculo
//
//  Ajustes durables (Application Support, exportables): carpeta de la bóveda
//  (security-scoped bookmark) y config de Ollama (modelo + servidor).
//  Nada de esto es verdad de documento; vaciarlo no pierde nada.
//

import Foundation
import Observation

/// Forma persistida de los ajustes.
struct VaultSettings: Codable, Sendable {
    var vaultBookmark: Data?
    var ollamaModel: String
    var ollamaEndpoint: String
    var searchKey: String
    var recentsKey: String

    init(
        vaultBookmark: Data? = nil,
        ollamaModel: String = "qwen2.5:7b",
        ollamaEndpoint: String = "http://127.0.0.1:11434",
        searchKey: String = "s",
        recentsKey: String = "r"
    ) {
        self.vaultBookmark = vaultBookmark
        self.ollamaModel = ollamaModel
        self.ollamaEndpoint = ollamaEndpoint
        self.searchKey = searchKey
        self.recentsKey = recentsKey
    }

    /// Decodificado tolerante: claves nuevas ausentes caen a su valor por defecto
    /// (no se pierde lo demás —p. ej. el bookmark de la bóveda— al ampliar el formato).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vaultBookmark = try c.decodeIfPresent(Data.self, forKey: .vaultBookmark)
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "qwen2.5:7b"
        ollamaEndpoint = try c.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? "http://127.0.0.1:11434"
        searchKey = try c.decodeIfPresent(String.self, forKey: .searchKey) ?? "s"
        recentsKey = try c.decodeIfPresent(String.self, forKey: .recentsKey) ?? "r"
    }
}

@MainActor
@Observable
final class SettingsStore {
    /// Carpeta de la bóveda resuelta desde el bookmark (nil si no hay).
    private(set) var vaultURL: URL?
    var ollamaModel: String { didSet { persist() } }
    var ollamaEndpoint: String { didSet { persist() } }
    var searchKey: String { didSet { persist() } }
    var recentsKey: String { didSet { persist() } }

    private let access: FileAccessProvider
    private let fileURL: URL
    private var vaultBookmark: Data?

    init(access: FileAccessProvider = MacFileAccessProvider()) {
        self.access = access

        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Óculo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")

        let loaded = Self.load(from: fileURL)
        vaultBookmark = loaded.vaultBookmark
        ollamaModel = loaded.ollamaModel
        ollamaEndpoint = loaded.ollamaEndpoint
        searchKey = loaded.searchKey
        recentsKey = loaded.recentsKey

        restoreVault()
    }

    var vaultName: String? { vaultURL?.lastPathComponent }

    /// Pide al usuario la carpeta de la bóveda y la recuerda.
    func chooseVault() async {
        guard let url = await access.pickFolder() else { return }
        guard let bookmark = try? access.makeBookmark(for: url) else { return }
        if let vaultURL { access.stopAccess(to: vaultURL) }
        vaultBookmark = bookmark
        access.startAccess(to: url)
        vaultURL = url
        persist()
    }

    /// Fija la bóveda desde una URL concreta (import de configuración).
    func setVault(_ url: URL) {
        guard let bookmark = try? access.makeBookmark(for: url) else { return }
        if let vaultURL { access.stopAccess(to: vaultURL) }
        vaultBookmark = bookmark
        access.startAccess(to: url)
        vaultURL = url
        persist()
    }

    func clearVault() {
        if let vaultURL { access.stopAccess(to: vaultURL) }
        vaultBookmark = nil
        vaultURL = nil
        persist()
    }

    private func restoreVault() {
        guard let vaultBookmark,
              let resolved = try? access.resolveBookmark(vaultBookmark) else { return }
        access.startAccess(to: resolved.url)
        vaultURL = resolved.url
    }

    private func persist() {
        let settings = VaultSettings(
            vaultBookmark: vaultBookmark,
            ollamaModel: ollamaModel,
            ollamaEndpoint: ollamaEndpoint,
            searchKey: searchKey,
            recentsKey: recentsKey
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> VaultSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(VaultSettings.self, from: data) else {
            return VaultSettings()
        }
        return settings
    }
}
