//
//  CollectionHomeView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import MapKit

/// 主界面：支持多视图（Auto/Story/All Photos）
struct CollectionHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt, order: .reverse) private var allCollections: [Collection]
    @Query(sort: \Photo.timestamp, order: .reverse) private var allPhotos: [Photo]
    
    @State private var selectedView: HomeViewType = .auto
    @State private var selectedDate: Date = Date()
    @State private var selectedCollection: Collection?
    @State private var selectedPhoto: Photo?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    
    private let timelineWindowDays: Double = 3
    
    enum HomeViewType: String, CaseIterable {
        case auto = "Auto"
        case story = "Story"
        case allPhotos = "全部照片"
    }
    
    private var autoCollections: [Collection] {
        allCollections.filter { $0.type == .auto }
    }
    
    private var storyCollections: [Collection] {
        allCollections.filter { $0.type == .story }
    }
    
    private var filteredCollections: [Collection] {
        let window = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -Int(timelineWindowDays), to: selectedDate) ?? selectedDate,
            end: Calendar.current.date(byAdding: .day, value: Int(timelineWindowDays), to: selectedDate) ?? selectedDate
        )
        
        switch selectedView {
        case .auto:
            return autoCollections.filter { collection in
                guard let start = collection.startTime, let end = collection.endTime else { return false }
                let collectionInterval = DateInterval(start: start, end: end)
                return window.intersects(collectionInterval)
            }
        case .story:
            return storyCollections.filter { collection in
                guard let start = collection.startTime, let end = collection.endTime else { return true }
                let collectionInterval = DateInterval(start: start, end: end)
                return window.intersects(collectionInterval)
            }
        case .allPhotos:
            return []
        }
    }
    
    private var filteredPhotos: [Photo] {
        let window = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -Int(timelineWindowDays), to: selectedDate) ?? selectedDate,
            end: Calendar.current.date(byAdding: .day, value: Int(timelineWindowDays), to: selectedDate) ?? selectedDate
        )
        return allPhotos.filter { window.contains($0.timestamp) }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    private var rangeStart: Date {
        switch selectedView {
        case .auto, .story:
            let dates = filteredCollections.compactMap { $0.startTime }
            guard let first = dates.min() else {
                return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            }
            return first
        case .allPhotos:
            guard let first = allPhotos.min(by: { $0.timestamp < $1.timestamp })?.timestamp else {
                return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            }
            return first
        }
    }
    
    private var rangeEnd: Date {
        switch selectedView {
        case .auto, .story:
            let dates = filteredCollections.compactMap { $0.endTime }
            return dates.max() ?? Date()
        case .allPhotos:
            return allPhotos.max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date()
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 视图切换器
                Picker("视图", selection: $selectedView) {
                    ForEach(HomeViewType.allCases, id: \.self) { viewType in
                        Text(viewType.rawValue).tag(viewType)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                TimelineSliderView(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    selectedDate: $selectedDate,
                    windowDays: timelineWindowDays
                )
                Divider()
                
                // 地图
                if selectedView == .allPhotos {
                    PhotoMapView(photos: filteredPhotos, cameraPosition: $mapCameraPosition) { photo in
                        selectedPhoto = photo
                        centerMap(on: photo)
                    }
                } else {
                    CollectionMapView(collections: filteredCollections, cameraPosition: $mapCameraPosition) { collection in
                        selectedCollection = collection
                        centerMap(on: collection)
                    }
                }
                Divider()
                
                // 列表
                if selectedView == .allPhotos {
                    PhotoListView(
                        photos: filteredPhotos,
                        scrollToId: selectedPhoto?.id,
                        onPhotoTap: { selectedPhoto = $0 }
                    )
                } else {
                    CollectionListView(collections: filteredCollections, scrollToId: selectedCollection?.id) { collection in
                        selectedCollection = collection
                    }
                }
            }
            .navigationTitle("回忆")
            .sheet(item: $selectedCollection, onDismiss: { selectedCollection = nil }) { collection in
                CollectionDetailView(collection: collection)
            }
            .sheet(item: $selectedPhoto, onDismiss: { selectedPhoto = nil }) { photo in
                PhotoDetailView(photo: photo)
            }
            .onAppear {
                if selectedDate > rangeEnd { selectedDate = rangeEnd }
                if selectedDate < rangeStart { selectedDate = rangeStart }
            }
            .onChange(of: selectedCollection) { _, new in
                if let c = new, c.centerCoordinate != nil {
                    centerMap(on: c)
                }
            }
            .onChange(of: selectedPhoto) { _, new in
                if let p = new, p.coordinate != nil {
                    centerMap(on: p)
                }
            }
        }
    }
    
    private func centerMap(on collection: Collection) {
        guard let coord = collection.centerCoordinate else { return }
        mapCameraPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }
    
    private func centerMap(on photo: Photo) {
        guard let coord = photo.coordinate else { return }
        mapCameraPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }
}

#Preview {
    CollectionHomeView()
        .modelContainer(for: [Photo.self, Collection.self, Event.self], inMemory: true)
}
