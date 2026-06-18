//
//  SettingsView.swift
//  Óculo
//
//  Ajustes (⌘,): idioma, carpeta de la bóveda, atajos, Ollama y export/import.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var store
    @Environment(AppearanceStore.self) private var appearance
    @Environment(TagStore.self) private var tags
    @Environment(CoverStore.self) private var covers
    @Environment(RecentsStore.self) private var recents

    @State private var testing = false
    @State private var status: String?
    @State private var statusOK = false
    @State private var importMessage: String?

    var body: some View {
        @Bindable var settings = settings
        @Bindable var loc = Localization.shared

        Form {
            Section(T("Language", "Idioma")) {
                Picker(T("Language", "Idioma"), selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(T("Vault", "Bóveda")) {
                HStack(alignment: .firstTextBaseline) {
                    if let name = settings.vaultName {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).fontWeight(.medium)
                            Text(settings.vaultURL?.path(percentEncoded: false) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text(T("No folder selected", "Ninguna carpeta seleccionada"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(T("Choose folder…", "Elegir carpeta…")) { Task { await settings.chooseVault() } }
                    if settings.vaultName != nil {
                        Button(T("Remove", "Quitar"), role: .destructive) { settings.clearVault() }
                    }
                }
                Text(T("Folder of `.md` notes that Óculo reads (never writes) to match and search.",
                       "Carpeta de notas `.md` que Óculo lee (nunca escribe) para emparejar y buscar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(T("Shortcuts", "Atajos")) {
                HStack {
                    Text(T("Key to open search", "Tecla para abrir el buscador"))
                    Spacer()
                    TextField("", text: $settings.searchKey)
                        .frame(width: 38)
                        .multilineTextAlignment(.center)
                        .onChange(of: settings.searchKey) { _, value in
                            let clamped = String(value.prefix(1)).lowercased()
                            if clamped != settings.searchKey { settings.searchKey = clamped }
                        }
                }
                HStack {
                    Text(T("Key to open Recents", "Tecla para abrir Recientes"))
                    Spacer()
                    TextField("", text: $settings.recentsKey)
                        .frame(width: 38)
                        .multilineTextAlignment(.center)
                        .onChange(of: settings.recentsKey) { _, value in
                            let clamped = String(value.prefix(1)).lowercased()
                            if clamped != settings.recentsKey { settings.recentsKey = clamped }
                        }
                }
                Text(T("Search: this key or ⌘K. Recents: this key. Defaults: s and r.",
                       "Buscador: esta tecla o ⌘K. Recientes: esta tecla. Por defecto: s y r."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(T("Ollama · refined search (optional)", "Ollama · búsqueda afinada (opcional)")) {
                TextField(T("Model", "Modelo"), text: $settings.ollamaModel, prompt: Text("qwen2.5:7b"))
                TextField(T("Server", "Servidor"), text: $settings.ollamaEndpoint, prompt: Text("http://127.0.0.1:11434"))
                HStack(spacing: 10) {
                    Button(T("Test connection", "Probar conexión")) { Task { await test() } }
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let status {
                        Label(status, systemImage: statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(statusOK ? .green : .orange)
                            .font(.callout)
                            .lineLimit(2)
                    }
                }
                Text(T("If Ollama isn't available, fast search still works fully.",
                       "Si Ollama no está disponible, la búsqueda rápida sigue funcionando entera."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(T("Configuration", "Configuración")) {
                HStack(spacing: 10) {
                    Button(T("Export…", "Exportar…")) {
                        ConfigTransfer.export(settings: settings, store: store, appearance: appearance,
                                              tags: tags, covers: covers, recents: recents)
                    }
                    Button(T("Import…", "Importar…")) {
                        guard let summary = ConfigTransfer.runImport(settings: settings, store: store, appearance: appearance,
                                                                     tags: tags, covers: covers, recents: recents) else { return }
                        importMessage = message(for: summary)
                    }
                }
                Text(T("Export/import everything Óculo manages (settings, libraries, tags, covers) to move it to another computer. The index rebuilds itself. Import replaces the current configuration.",
                       "Exporta/importa todo lo que Óculo gestiona (ajustes, bibliotecas, tags, portadas) para trasladarlo a otro equipo. El índice se reconstruye solo. Importar reemplaza la configuración actual."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 460)
        .environment(\.locale, loc.locale)
        .alert(T("Import", "Importación"), isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// Mensaje del alert tras importar (solo avisa de lo no resuelto).
    private func message(for s: ImportSummary) -> String {
        if s.failedToRead { return T("Couldn't read the configuration file.", "No se pudo leer el archivo de configuración.") }
        var lines = [T("Configuration imported. \(s.importedLibraries) library(ies) restored.",
                       "Configuración importada. \(s.importedLibraries) biblioteca(s) restaurada(s).")]
        if let vault = s.missingVault {
            lines.append(T("The vault doesn't exist on this computer and was skipped:\n\(vault)",
                           "La bóveda no existe en este equipo y se omitió:\n\(vault)"))
        }
        if !s.missingLibraries.isEmpty {
            lines.append(T("Not found on this computer (reopen them manually):\n", "No encontradas en este equipo (reábrelas a mano):\n")
                         + s.missingLibraries.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }

    private func test() async {
        testing = true
        status = nil
        let result = await OllamaClient().testConnection(
            model: settings.ollamaModel,
            endpoint: settings.ollamaEndpoint
        )
        testing = false
        switch result {
        case .ok(let models):
            statusOK = true
            status = T("Connected · \(models.count) model(s) available", "Conectado · \(models.count) modelo(s) disponibles")
        case .modelMissing(let available):
            statusOK = false
            let list = available.prefix(3).joined(separator: ", ")
            status = available.isEmpty
                ? T("Connects, but no models installed", "Conecta, pero no hay modelos instalados")
                : T("Connects, but the model is missing. Available: \(list)…", "Conecta, pero falta el modelo. Hay: \(list)…")
        case .unreachable(let message):
            statusOK = false
            status = T("Unavailable: \(message)", "No disponible: \(message)")
        }
    }
}
