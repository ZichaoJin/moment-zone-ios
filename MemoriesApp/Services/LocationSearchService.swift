//
//  LocationSearchService.swift
//  MemoriesApp
//

import Foundation
import MapKit

@MainActor
class LocationSearchService: ObservableObject {
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false
    
    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
        )
        
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems
        } catch {
            print("搜索失败: \(error.localizedDescription)")
            searchResults = []
        }
    }
    
    func selectResult(_ item: MKMapItem) -> (coordinate: CLLocationCoordinate2D, name: String) {
        let coordinate = item.placemark.coordinate
        let name = item.name ?? item.placemark.title ?? "未知地点"
        return (coordinate, name)
    }
}
