//
//  MapSearchSheet.swift
//  MemoriesApp
//

import SwiftUI
import MapKit

/// 地图搜索：搜索地址 + 推荐去过的地方
struct MapSearchSheet: View {
    let allPhotos: [Photo]
    var currentCoordinate: CLLocationCoordinate2D?
    var onSelect: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false

    /// 用户去过的地方（从照片历史提取，按频次+时间综合排序）
    private var visitedPlaces: [VisitedPlace] {
        let withLoc = allPhotos.filter { $0.coordinate != nil && !$0.displayLocationName.isEmpty }
        var dict: [String: VisitedPlace] = [:]
        for photo in withLoc {
            let name = photo.displayLocationName
            if var existing = dict[name] {
                existing.count += 1
                if photo.timestamp > existing.latestVisit {
                    existing.latestVisit = photo.timestamp
                    existing.coordinate = photo.coordinate!
                }
                dict[name] = existing
            } else {
                dict[name] = VisitedPlace(
                    name: name,
                    coordinate: photo.coordinate!,
                    count: 1,
                    latestVisit: photo.timestamp
                )
            }
        }
        // 综合排序：历史频次 + 最近访问 + 与当前位置距离
        return dict.values.sorted { a, b in
            let aScore = placeScore(a)
            let bScore = placeScore(b)
            return aScore > bScore
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // 搜索栏
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索地址", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .onSubmit { performSearch() }
                        if !searchText.isEmpty {
                            Button { searchText = ""; searchResults = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 搜索结果
                if !searchResults.isEmpty {
                    Section("搜索结果") {
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                if let coord = item.placemark.location?.coordinate {
                                    onSelect(coord)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "未知地点")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if let addr = item.placemark.thoroughfare {
                                            Text(addr)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                // 去过的地方推荐
                if searchText.isEmpty && !visitedPlaces.isEmpty {
                    Section("去过的地方") {
                        ForEach(visitedPlaces.prefix(20), id: \.name) { place in
                            Button {
                                onSelect(place.coordinate)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 6) {
                                            Text("\(place.count) 张照片")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("· \(place.latestVisit.formatted(.dateTime.month().day()))")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                            if let distanceText = distanceText(from: place.coordinate) {
                                                Text("· \(distanceText)")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("搜索地点")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.count >= 2 {
                    performSearch()
                } else if newValue.isEmpty {
                    searchResults = []
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            isSearching = false
            searchResults = response?.mapItems ?? []
        }
    }

    private func placeScore(_ place: VisitedPlace) -> Double {
        let now = Date()
        let daysAgo = max(now.timeIntervalSince(place.latestVisit) / 86_400, 0)
        let recencyScore = max(0, 1 - min(daysAgo / 365, 1))
        let historyScore = min(Double(place.count) / 12, 1)

        let distanceScore: Double
        if let currentCoordinate {
            let current = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
            let target = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let km = current.distance(from: target) / 1000
            distanceScore = max(0, 1 - min(km / 20, 1))
        } else {
            distanceScore = 0.5
        }
        return historyScore * 0.45 + recencyScore * 0.35 + distanceScore * 0.20
    }

    private func distanceText(from coordinate: CLLocationCoordinate2D) -> String? {
        guard let currentCoordinate else { return nil }
        let current = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = current.distance(from: target)
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

private struct VisitedPlace {
    let name: String
    var coordinate: CLLocationCoordinate2D
    var count: Int
    var latestVisit: Date
}
