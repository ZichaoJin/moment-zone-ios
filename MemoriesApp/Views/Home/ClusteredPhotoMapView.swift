//
//  ClusteredPhotoMapView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

/// 支持层级聚合的照片地图视图；可选显示按时间顺序的路线
struct ClusteredPhotoMapView: View {
    let photos: [Photo]
    @Binding var cameraPosition: MapCameraPosition
    /// 为 true 时按照片时间顺序绘制地点连线（回忆/时间模式）
    var showRouteLine: Bool = false
    /// 高亮某张照片所属的聚合组
    var highlightedPhotoId: UUID? = nil
    /// 高亮的story IDs（用于双击照片后高亮story）
    var highlightedStoryIds: Set<UUID> = []
    var onClusterTapped: ((MapClusteringService.Cluster) -> Void)?
    /// 可选：直接在地图标注点弹出地点内 stories 列表并选择跳转
    var onClusterStorySelect: ((Collection, Date) -> Void)? = nil
    var onPhotoTapped: ((Photo) -> Void)?
    
    @State private var currentSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
    @State private var currentRegion: MKCoordinateRegion?
    @State private var popoverClusterId: String?
    
    /// 只展示有有效坐标的照片
    private var photosWithLocation: [Photo] {
        photos.filter { $0.coordinate != nil }
    }
    
    /// 按时间排序后的坐标序列（用于路线）
    private var routeCoordinates: [CLLocationCoordinate2D] {
        guard showRouteLine else { return [] }
        return photos
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.coordinate }
    }
    
    /// 根据当前地图 span 计算聚合点
    private var clusters: [MapClusteringService.Cluster] {
        return MapClusteringService.clusterPhotos(
            photosWithLocation,
            mapSpan: currentSpan,
            visibleRegion: currentRegion
        )
    }
    
    /// 非高亮聚合点
    private var nonHighlightedClusters: [MapClusteringService.Cluster] {
        guard let hId = highlightedPhotoId else { return clusters }
        return clusters.filter { !$0.photos.contains(where: { $0.id == hId }) }
    }
    
    /// 高亮聚合点（包含选中照片的）
    private var highlightedClusters: [MapClusteringService.Cluster] {
        guard let hId = highlightedPhotoId else { return [] }
        return clusters.filter { $0.photos.contains(where: { $0.id == hId }) }
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            if showRouteLine, routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(AppTheme.accent.opacity(0.8), lineWidth: 4)
            }
            ForEach(nonHighlightedClusters) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    ClusterAnnotationNode(
                        cluster: cluster,
                        isHighlighted: false,
                        highlightedPhotoId: highlightedPhotoId,
                        highlightedStoryIds: highlightedStoryIds,
                        canShowStoryPopover: onClusterStorySelect != nil,
                        popoverClusterId: $popoverClusterId,
                        onClusterTapped: onClusterTapped,
                        onStorySelected: onClusterStorySelect
                    )
                }
                .annotationTitles(.hidden)
            }
            ForEach(highlightedClusters) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    ClusterAnnotationNode(
                        cluster: cluster,
                        isHighlighted: true,
                        highlightedPhotoId: highlightedPhotoId,
                        highlightedStoryIds: highlightedStoryIds,
                        canShowStoryPopover: onClusterStorySelect != nil,
                        popoverClusterId: $popoverClusterId,
                        onClusterTapped: onClusterTapped,
                        onStorySelected: onClusterStorySelect
                    )
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            currentRegion = context.region
            currentSpan = context.region.span
        }
        .onAppear {
            updateRegionFromCameraPosition()
        }
        .animation(.none, value: highlightedPhotoId)
        .frame(minHeight: 200)
    }
    
    /// 从 cameraPosition 更新 region（仅在初始化时使用）
    private func updateRegionFromCameraPosition() {
        // 使用反射或其他方式获取 region
        // 如果 cameraPosition 是 .region，我们可以通过 Mirror 获取
        let mirror = Mirror(reflecting: cameraPosition)
        for child in mirror.children {
            if let region = child.value as? MKCoordinateRegion {
                currentRegion = region
                currentSpan = region.span
                return
            }
        }
    }
}

private struct ClusterAnnotationNode: View {
    let cluster: MapClusteringService.Cluster
    let isHighlighted: Bool
    let highlightedPhotoId: UUID?
    let highlightedStoryIds: Set<UUID>
    let canShowStoryPopover: Bool
    @Binding var popoverClusterId: String?
    var onClusterTapped: ((MapClusteringService.Cluster) -> Void)?
    var onStorySelected: ((Collection, Date) -> Void)?

    private var isPopoverShown: Binding<Bool> {
        Binding(
            get: { popoverClusterId == cluster.id },
            set: { show in
                if !show, popoverClusterId == cluster.id {
                    popoverClusterId = nil
                }
            }
        )
    }

    var body: some View {
        ClusterAnnotationView(
            cluster: cluster,
            isHighlighted: isHighlighted,
            highlightedPhotoId: highlightedPhotoId
        ) {
            if canShowStoryPopover {
                popoverClusterId = cluster.id
            } else {
                onClusterTapped?(cluster)
            }
        }
        .popover(isPresented: isPopoverShown, arrowEdge: .top) {
            ClusterStoryPopoverView(cluster: cluster, highlightedStoryIds: highlightedStoryIds) { story, day in
                popoverClusterId = nil
                onStorySelected?(story, day)
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ClusterStoryPopoverView: View {
    struct Entry: Identifiable {
        let id: UUID
        let collection: Collection
        let day: Date
        let color: Color
    }

    let cluster: MapClusteringService.Cluster
    let highlightedStoryIds: Set<UUID>
    var onSelect: (Collection, Date) -> Void

    private var locationTitle: String {
        var counts: [String: Int] = [:]
        for photo in cluster.photos {
            let name = photo.displayLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "这个地点"
    }

    private var entries: [Entry] {
        var map: [UUID: (collection: Collection, day: Date)] = [:]
        for photo in cluster.photos {
            let day = Calendar.current.startOfDay(for: photo.timestamp)
            for collection in photo.collections where collection.type == .story && collection.deletedAt == nil {
                if let existing = map[collection.id] {
                    if day < existing.day {
                        map[collection.id] = (collection, day)
                    }
                } else {
                    map[collection.id] = (collection, day)
                }
            }
        }
        return map.values
            .map {
                Entry(
                    id: $0.collection.id,
                    collection: $0.collection,
                    day: $0.day,
                    color: AppTheme.storyColor(category: $0.collection.storyCategory, storyId: $0.collection.id)
                )
            }
            .sorted { $0.day > $1.day }
    }

    private func coverAssetId(for entry: Entry) -> String? {
        cluster.photos
            .filter { $0.collections.contains(where: { $0.id == entry.collection.id }) }
            .sorted { $0.timestamp > $1.timestamp }
            .first?
            .assetLocalId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.pillForeground)
                    .frame(width: 24, height: 24)
                    .background(
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(AppTheme.pillBackground)
                        }
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(locationTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entries.count == 1 ? "1 个回忆" : "\(entries.count) 个回忆")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)

            if entries.isEmpty {
                Text("这个地点没有关联回忆")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        let lightBrown = Color(red: 0.86, green: 0.62, blue: 0.33)
                        let isOwned = highlightedStoryIds.contains(entry.collection.id)

                        Button {
                            onSelect(entry.collection, entry.day)
                        } label: {
                            HStack(spacing: 10) {
                                if let coverId = coverAssetId(for: entry) {
                                    PhotoThumbnailView(
                                        localIdentifier: coverId,
                                        size: nil,
                                        cornerRadius: 6,
                                        requestSize: CGSize(width: 72, height: 72)
                                    )
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    StoryTypeBadgeDot(symbolName: entry.collection.storyCategory.symbolName, color: lightBrown, size: 20, iconSize: 11)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.collection.title)
                                        .font(.subheadline.weight(isOwned ? .bold : .regular))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(dateRangeText(for: entry.collection))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 6)
                                if isOwned {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(lightBrown)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                (isOwned ? lightBrown.opacity(0.14) : Color(.secondarySystemBackground).opacity(0.85)),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isOwned ? lightBrown.opacity(0.9) : Color.black.opacity(0.08), lineWidth: isOwned ? 1.2 : 0.8)
                            )
                        }
                        .padding(.horizontal, 1)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 230, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private func dateRangeText(for story: Collection) -> String {
        let activePhotos = story.photos.filter { $0.deletedAt == nil }
        let start = story.startTime ?? activePhotos.map(\.timestamp).min()
        let end = story.endTime ?? activePhotos.map(\.timestamp).max()
        guard let start else { return "未设置日期" }
        guard let end else { return start.formatted(.dateTime.month().day()) }
        let from = start.formatted(.dateTime.month().day())
        let to = end.formatted(.dateTime.month().day())
        return from == to ? from : "\(from)-\(to)"
    }
}

private struct StoryTypeBadgeDot: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 20
    var iconSize: CGFloat = 11

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18))
            Circle().stroke(color.opacity(0.9), lineWidth: 1.1)
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// 聚合点标注视图：显示该区域最新照片的缩略图 + 右下角数量气泡
struct ClusterAnnotationView: View {
    let cluster: MapClusteringService.Cluster
    var isHighlighted: Bool = false
    /// 当高亮时，用这张照片做封面
    var highlightedPhotoId: UUID? = nil
    var onTap: () -> Void
    
    private var displayAssetId: String {
        if let hId = highlightedPhotoId,
           let photo = cluster.photos.first(where: { $0.id == hId }) {
            return photo.assetLocalId
        }
        return cluster.photos.sorted { $0.timestamp < $1.timestamp }.last?.assetLocalId ?? ""
    }
    
    private var pinSize: CGFloat { isHighlighted ? 56 : 48 }
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                PhotoThumbnailView(localIdentifier: displayAssetId)
                    .frame(width: pinSize, height: pinSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHighlighted ? Color.accentColor : .white, lineWidth: isHighlighted ? 3 : 2.5)
                    )
                    .shadow(color: isHighlighted ? AppTheme.accent.opacity(0.6) : Color(red: 0.3, green: 0.25, blue: 0.18).opacity(0.35), radius: isHighlighted ? 8 : 4, x: 0, y: 2)

                if cluster.photoCount > 1 {
                    Text("\(cluster.photoCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isHighlighted ? AppTheme.clusterBadgeHighlight : AppTheme.clusterBadge))
                        .offset(x: 6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ClusteredPhotoMapView(
        photos: [],
        cameraPosition: .constant(.automatic),
        onClusterTapped: nil,
        onPhotoTapped: nil
    )
}
