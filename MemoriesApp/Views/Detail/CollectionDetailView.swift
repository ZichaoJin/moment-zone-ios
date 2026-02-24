//
//  CollectionDetailView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

struct CollectionDetailView: View {
    let collection: Collection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 照片横滑
                    if !collection.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(collection.photos, id: \.id) { photo in
                                    AssetImageView(localIdentifier: photo.assetLocalId, size: CGSize(width: 280, height: 280))
                                        .frame(width: 280, height: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 292)
                    }
                    
                    // 地图（如果有位置）
                    if let coordinate = collection.centerCoordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Annotation(collection.title, coordinate: coordinate) {
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
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Collection Note
                    if let note = collection.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                    }
                    
                    // 时间范围
                    if let startTime = collection.startTime, let endTime = collection.endTime {
                        Label("\(startTime.formatted(date: .long, time: .shortened)) - \(endTime.formatted(date: .long, time: .shortened))", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(collection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CollectionDetailView(collection: Collection(
        title: "示例集合",
        type: .auto,
        startTime: Date(),
        endTime: Date()
    ))
}
