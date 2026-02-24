//
//  MemoryDetailView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

struct MemoryDetailView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !memory.assetLocalIds.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(memory.assetLocalIds, id: \.self) { localId in
                                    AssetImageView(localIdentifier: localId, size: CGSize(width: 280, height: 280))
                                        .frame(width: 280, height: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 292)
                    }
                    if memory.latitude != 0 || memory.longitude != 0 {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: memory.latitude, longitude: memory.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
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
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !memory.note.isEmpty {
                        Text(memory.note)
                            .font(.body)
                    }
                    if !memory.locationName.isEmpty {
                        Label(memory.locationName, systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label(memory.timestamp.formatted(date: .long, time: .shortened), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("回忆详情")
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
    MemoryDetailView(memory: Memory(
        timestamp: Date(),
        latitude: 39.9,
        longitude: 116.4,
        locationName: "示例地点",
        note: "这是一条示例回忆"
    ))
}
