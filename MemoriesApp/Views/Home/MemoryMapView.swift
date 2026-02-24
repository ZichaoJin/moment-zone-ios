//
//  MemoryMapView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

struct MemoryMapView: View {
    let memories: [Memory]
    @Binding var cameraPosition: MapCameraPosition
    var onPinTapped: ((Memory) -> Void)?

    /// 只展示有有效坐标的回忆（lat/lng 不全为 0）
    private var memoriesWithLocation: [Memory] {
        memories.filter { $0.latitude != 0 || $0.longitude != 0 }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(memoriesWithLocation, id: \.id) { memory in
                Annotation(memory.locationName.isEmpty ? "回忆" : memory.locationName, coordinate: CLLocationCoordinate2D(latitude: memory.latitude, longitude: memory.longitude)) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 36, height: 36)
                            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                        Image(systemName: "heart.fill")
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
                        onPinTapped?(memory)
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
    MemoryMapView(memories: [], cameraPosition: .constant(.automatic))
}
