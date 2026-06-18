//
//  OculoApp.swift
//  Óculo
//

import SwiftUI

@main
struct OculoApp: App {
    @State private var store = LibraryStore()
    @State private var appearance = AppearanceStore()
    @State private var settings = SettingsStore()
    @State private var vault = VaultStore()
    @State private var search = SearchService()
    @State private var recents = RecentsStore()
    @State private var tags = TagStore()
    @State private var covers = CoverStore()
    @State private var gridSelection = GridSelection()

    var body: some Scene {
        WindowGroup {
            LibraryBrowserView()
                .environment(store)
                .environment(appearance)
                .environment(settings)
                .environment(vault)
                .environment(search)
                .environment(recents)
                .environment(tags)
                .environment(covers)
                .environment(gridSelection)
                .preferredColorScheme(appearance.colorScheme)
                .task(id: settings.vaultURL) { vault.load(from: settings.vaultURL) }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(store)
                .environment(appearance)
                .environment(tags)
                .environment(covers)
                .environment(recents)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
