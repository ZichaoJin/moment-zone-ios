//
//  MemoriesAppApp.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

@main
struct MemoriesAppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Photo.self, Collection.self, Event.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
