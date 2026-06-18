//
//  ConfigTransfer.swift
//  Óculo
//
//  Exporta/importa toda la configuración que Óculo gestiona (ajustes, preferencias,
//  bibliotecas y bóveda como RUTAS, tags, portadas, recientes) en un único archivo,
//  para trasladarla a otro equipo. No exporta caché regenerable (índice, hashes) ni
//  bookmarks (son específicos de cada máquina; se regeneran desde la ruta al importar).
//

import AppKit
import UniformTypeIdentifiers

/// Forma serializada de toda la configuración.
struct ConfigBundle: Codable {
    struct LibraryRef: Codable { var name: String; var path: String }

    var version: Int = 1
    var ollamaModel: String
    var ollamaEndpoint: String
    var searchKey: String
    var recentsKey: String
    var vaultPath: String?
    var libraries: [LibraryRef]
    var mode: String
    var toneIndex: Int
    var viewMode: String
    var cardSize: Double
    var tags: [Tag]
    var covers: [String: Int]
    var recents: [RecentEntry]
}

/// Resumen de un import, para informar al usuario (lo no resuelto, sin romper nada).
struct ImportSummary {
    var failedToRead = false
    var missingVault: String?
    var missingLibraries: [String] = []
    var importedLibraries = 0
}

@MainActor
enum ConfigTransfer {

    // MARK: Export

    static func export(settings: SettingsStore, store: LibraryStore, appearance: AppearanceStore,
                       tags: TagStore, covers: CoverStore, recents: RecentsStore) {
        let bundle = ConfigBundle(
            ollamaModel: settings.ollamaModel,
            ollamaEndpoint: settings.ollamaEndpoint,
            searchKey: settings.searchKey,
            recentsKey: settings.recentsKey,
            vaultPath: settings.vaultURL?.path(percentEncoded: false),
            libraries: store.libraries.map { .init(name: $0.name, path: $0.url.path(percentEncoded: false)) },
            mode: appearance.mode.rawValue,
            toneIndex: appearance.toneIndex,
            viewMode: appearance.viewMode.rawValue,
            cardSize: appearance.cardSize,
            tags: tags.tags,
            covers: covers.pages,
            recents: recents.entries
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Oculo-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bundle) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Import (reemplaza la config actual)

    static func runImport(settings: SettingsStore, store: LibraryStore, appearance: AppearanceStore,
                          tags: TagStore, covers: CoverStore, recents: RecentsStore) -> ImportSummary? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let bundle = try? decoder.decode(ConfigBundle.self, from: data) else {
            return ImportSummary(failedToRead: true)
        }

        var summary = ImportSummary()

        // Ajustes y preferencias.
        settings.ollamaModel = bundle.ollamaModel
        settings.ollamaEndpoint = bundle.ollamaEndpoint
        settings.searchKey = bundle.searchKey
        settings.recentsKey = bundle.recentsKey
        appearance.apply(
            mode: AppearanceMode(rawValue: bundle.mode) ?? .mist,
            toneIndex: bundle.toneIndex,
            viewMode: GridViewMode(rawValue: bundle.viewMode) ?? .grid,
            cardSize: bundle.cardSize
        )

        // Bóveda: si la ruta existe → fijarla; si no → omitir y avisar.
        if let vaultPath = bundle.vaultPath {
            if FileManager.default.fileExists(atPath: vaultPath) {
                settings.setVault(URL(fileURLWithPath: vaultPath))
            } else {
                summary.missingVault = vaultPath
            }
        }

        // Bibliotecas (por ruta; las que no existan se omiten y se listan).
        let missing = store.replaceLibraries(bundle.libraries.map { (name: $0.name, path: $0.path) })
        summary.missingLibraries = missing
        summary.importedLibraries = bundle.libraries.count - missing.count

        // Colecciones propias (clavadas a id se reconectan al reindexar; las de ruta
        // que no existan simplemente no se mostrarán).
        tags.replaceAll(bundle.tags)
        covers.replaceAll(bundle.covers)
        recents.replaceAll(bundle.recents)

        return summary
    }
}
