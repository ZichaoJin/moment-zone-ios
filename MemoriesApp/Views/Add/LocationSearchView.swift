//
//  LocationSearchView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import UIKit

struct LocationSearchView: View {
    @ObservedObject var searchService: LocationSearchService
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Binding var locationName: String
    @FocusState private var isSearchFocused: Bool
    
    @State private var searchText = ""
    
    var onLocationSelected: ((CLLocationCoordinate2D, String) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索地点（如：天安门、三里屯）", text: $searchText)
                    .focused($isSearchFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await searchService.search(query: searchText)
                        }
                    }
                    .onChange(of: searchText) { _, newValue in
                        if !newValue.isEmpty {
                            Task {
                                await searchService.search(query: newValue)
                            }
                        } else {
                            searchService.searchResults = []
                        }
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchService.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            if searchService.isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("搜索中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
            }
            
            if !searchService.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(searchService.searchResults.enumerated()), id: \.offset) { index, item in
                            LocationSearchResultRow(item: item) {
                                let result = searchService.selectResult(item)
                                selectedCoordinate = result.coordinate
                                locationName = result.name
                                searchText = result.name
                                searchService.searchResults = []
                                isSearchFocused = false
                                onLocationSelected?(result.coordinate, result.name)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        // 键盘「完成」由父视图（编辑地点/添加地点）统一提供，此处不再添加，避免出现两个或没有
    }
}

struct LocationSearchResultRow: View {
    let item: MKMapItem
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "未知地点")
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    if let address = item.placemark.title, address != item.name {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color(.systemBackground))
        
        Divider()
            .padding(.leading, 48)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var service = LocationSearchService()
        @State var coord: CLLocationCoordinate2D?
        @State var name = ""
        
        var body: some View {
            LocationSearchView(
                searchService: service,
                selectedCoordinate: $coord,
                locationName: $name
            )
            .padding()
        }
    }
    return PreviewWrapper()
}
