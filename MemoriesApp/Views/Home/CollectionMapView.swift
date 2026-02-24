//
//  CollectionMapView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

struct CollectionMapView: View {
    let collections: [Collection]
    @Binding var cameraPosition: MapCameraPosition
    var onCollectionTapped: ((Collection) -> Void)?

    /// 只展示有有效坐标的 Collection
    private var collectionsWithLocation: [Collection] {
        collections.filter { $0.centerCoordinate != nil }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(collectionsWithLocation, id: \.id) { collection in
                Annotation(collection.title, coordinate: collection.centerCoordinate!) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 36, height: 36)
                            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                        Image(systemName: collection.type == .story ? "book.fill" : "map.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .font(.title3)
                    }
                    .onTapGesture {
                        onCollectionTapped?(collection)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(minHeight: 200)
    }
}

#Preview {
    CollectionMapView(collections: [], cameraPosition: .constant(.automatic))
}
