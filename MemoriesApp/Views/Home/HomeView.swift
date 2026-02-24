//
//  HomeView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import MapKit

private let timelineWindowDays: Double = 3

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.timestamp, order: .reverse) private var memories: [Memory]
    @State private var selectedDate: Date = Date()
    @State private var selectedMemory: Memory?
    @State private var editingMemory: Memory?
    @State private var showMergeMemories = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    private var rangeStart: Date {
        guard let first = memories.min(by: { $0.timestamp < $1.timestamp })?.timestamp else {
            return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        }
        return first
    }

    private var rangeEnd: Date {
        guard let last = memories.max(by: { $0.timestamp < $1.timestamp })?.timestamp else {
            return Date()
        }
        return last
    }

    private var filteredMemories: [Memory] {
        let window = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -Int(timelineWindowDays), to: selectedDate) ?? selectedDate,
            end: Calendar.current.date(byAdding: .day, value: Int(timelineWindowDays), to: selectedDate) ?? selectedDate
        )
        return memories.filter { window.contains($0.timestamp) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TimelineSliderView(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    selectedDate: $selectedDate,
                    windowDays: timelineWindowDays
                )
                Divider()
                MemoryMapView(memories: filteredMemories, cameraPosition: $mapCameraPosition) { memory in
                    selectedMemory = memory
                    centerMap(on: memory)
                }
                Divider()
                MemoryListView(
                    memories: filteredMemories,
                    scrollToId: selectedMemory?.id,
                    onMemoryTap: { memory in
                        selectedMemory = memory
                    },
                    onEdit: { memory in
                        editingMemory = memory
                    }
                )
            }
            .navigationTitle("回忆")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMergeMemories = true
                    } label: {
                        Image(systemName: "arrow.triangle.merge")
                    }
                }
            }
            .sheet(item: $selectedMemory, onDismiss: { selectedMemory = nil }) { memory in
                MemoryDetailView(memory: memory)
            }
            .sheet(item: $editingMemory, onDismiss: { editingMemory = nil }) { memory in
                AddMemoryView(editingMemory: memory)
            }
            .sheet(isPresented: $showMergeMemories) {
                MergeMemoriesView()
            }
            .onAppear {
                if selectedDate > rangeEnd { selectedDate = rangeEnd }
                if selectedDate < rangeStart { selectedDate = rangeStart }
            }
            .onChange(of: selectedMemory) { _, new in
                if let m = new, (m.latitude != 0 || m.longitude != 0) {
                    centerMap(on: m)
                }
            }
        }
    }

    private func centerMap(on memory: Memory) {
        mapCameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: memory.latitude, longitude: memory.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Memory.self], inMemory: true)
}
