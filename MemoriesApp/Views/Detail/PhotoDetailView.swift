//
//  PhotoDetailView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import CoreLocation

/// 照片详情：支持左右滑动浏览同组照片，底部显示定位信息
struct PhotoDetailView: View {
    /// 当前照片列表（同一组/cluster 的所有照片）
    let photos: [Photo]
    /// 初始选中的照片
    let initialPhoto: Photo
    /// 可选：编辑地点应用后的回调（用于重新聚合 events）
    var onLocationChanged: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var editingLocationPhoto: Photo?
    private let detailImageSize = CGSize(width: 1200, height: 1200)

    init(photos: [Photo], initialPhoto: Photo, onLocationChanged: (() -> Void)? = nil) {
        self.photos = photos
        self.initialPhoto = initialPhoto
        self.onLocationChanged = onLocationChanged
    }

    /// 便捷初始化：只传单张照片
    init(photo: Photo, onLocationChanged: (() -> Void)? = nil) {
        self.photos = [photo]
        self.initialPhoto = photo
        self.onLocationChanged = onLocationChanged
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // 主体：可左右滑动的照片
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            AssetImageView(
                                localIdentifier: photo.assetLocalId,
                                size: detailImageSize,
                                adaptive: true
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 8)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))

                    // 底部信息
                    photoInfoBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if photos.count > 1 {
                        Text("\(currentIndex + 1) / \(photos.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if let idx = photos.firstIndex(where: { $0.id == initialPhoto.id }) {
                    currentIndex = idx
                }
                prefetchNearbyImages(around: currentIndex)
            }
            .onChange(of: currentIndex) { _, newValue in
                prefetchNearbyImages(around: newValue)
            }
        }
    }

    private var currentPhoto: Photo {
        guard photos.indices.contains(currentIndex) else { return initialPhoto }
        return photos[currentIndex]
    }
    
    /// 针对当前照片的推荐地点（从同一story中按时间接近排序）
    private var currentPhotoRecommendations: [(name: String, coordinate: CLLocationCoordinate2D)] {
        let photo = currentPhoto
        // 从photo的collections中获取同一story的照片
        let storyPhotos = photo.collections.flatMap { $0.photos.filter { $0.deletedAt == nil && $0.coordinate != nil && !$0.displayLocationName.isEmpty } }
        guard !storyPhotos.isEmpty else { return [] }
        
        var seen = Set<String>()
        return storyPhotos
            .sorted { abs($0.timestamp.timeIntervalSince(photo.timestamp)) < abs($1.timestamp.timeIntervalSince(photo.timestamp)) }
            .compactMap { p -> (name: String, coordinate: CLLocationCoordinate2D)? in
                let name = p.displayLocationName
                guard !seen.contains(name), let coord = p.coordinate else { return nil }
                seen.insert(name)
                return (name: name, coordinate: coord)
            }
    }

    private var photoInfoBar: some View {
        VStack(spacing: 6) {
            // 时间
            Text(currentPhoto.timestamp.formatted(date: .long, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.primary)

            // 定位（可点击编辑）
            Button {
                editingLocationPhoto = currentPhoto
            } label: {
                if !currentPhoto.displayLocationName.isEmpty {
                    HStack(spacing: 4) {
                        Label(currentPhoto.displayLocationName, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Label("添加位置", systemImage: "location.badge.plus")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .sheet(item: $editingLocationPhoto) { photo in
            PhotoEditView(
                photo: photo,
                recommendedLocations: currentPhotoRecommendations,
                onLocationChanged: onLocationChanged
            )
        }
    }

    private func prefetchNearbyImages(around index: Int) {
        guard !photos.isEmpty, photos.indices.contains(index) else { return }
        PhotoService.prefetch(localIdentifier: photos[index].assetLocalId, targetSize: detailImageSize)
        if photos.indices.contains(index - 1) {
            PhotoService.prefetch(localIdentifier: photos[index - 1].assetLocalId, targetSize: detailImageSize)
        }
        if photos.indices.contains(index + 1) {
            PhotoService.prefetch(localIdentifier: photos[index + 1].assetLocalId, targetSize: detailImageSize)
        }
    }
}

struct CollectionCard: View {
    let collection: Collection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: collection.type == .story ? "book.fill" : "map.fill")
                    .foregroundStyle(AppTheme.accent)
                Text(collection.title)
                    .font(.headline)
            }

            if let note = collection.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

#Preview {
    PhotoDetailView(photo: Photo(assetLocalId: ""))
}
