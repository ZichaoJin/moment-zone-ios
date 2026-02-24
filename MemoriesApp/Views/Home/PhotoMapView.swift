//
//  PhotoMapView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

struct PhotoMapView: View {
    let photos: [Photo]
    @Binding var cameraPosition: MapCameraPosition
    var onPhotoTapped: ((Photo) -> Void)?

    /// 只展示有有效坐标的 Photo
    private var photosWithLocation: [Photo] {
        photos.filter { $0.coordinate != nil }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(photosWithLocation, id: \.id) { photo in
                Annotation("", coordinate: photo.coordinate!) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                        Image(systemName: "heart.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .font(.caption)
                    }
                    .onTapGesture {
                        onPhotoTapped?(photo)
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
    PhotoMapView(photos: [], cameraPosition: .constant(.automatic))
}
