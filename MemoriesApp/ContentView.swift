//
//  ContentView.swift
//  MemoriesApp
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MemoriesHomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Photo.self, Collection.self, Event.self], inMemory: true)
}
