//
//  MemoriesHomeView.swift
//  MemoriesApp

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import UIKit

private enum HomeDisplayMode: String, CaseIterable {
    case map
    case calendar
    case stories

    var icon: String {
        switch self {
        case .map: return "map"
        case .calendar: return "calendar"
        case .stories: return "list.bullet.rectangle"
        }
    }
}

/// 主界面：TabView + 自定义底部面板（照片网格）
struct MemoriesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Collection> { c in c.deletedAt == nil }, sort: \Collection.createdAt, order: .reverse) private var allCollections: [Collection]
    @Query(filter: #Predicate<Photo> { p in p.deletedAt == nil }, sort: \Photo.timestamp, order: .reverse) private var allPhotos: [Photo]
    
    @StateObject private var userLocationBootstrapper = UserLocationBootstrapper()
    @State private var editingPhoto: Photo?
    @State private var focusedPhoto: Photo?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var isPhotoSelectionMode = false
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var showAddSheet = false
    @State private var showTrashSheet = false
    @State private var homeMode: HomeDisplayMode = .stories
    @State private var storiesScreenSelectedCollection: Collection?
    @State private var storiesScreenSelectedDayDate: Date?
    @State private var currentPanelDetent: CGFloat = 300
    @State private var calendarHighlightDate: Date? = nil
    @State private var calendarHighlightStoryIds: Set<UUID> = []
    @State private var hasCenteredOnUserLocation = false
    @State private var mapViewportHeight: CGFloat = UIScreen.main.bounds.height
    @State private var showMapSearchSheet = false
    @State private var mapStoryPickerPhoto: Photo?
    @State private var selectedPhotoForDetail: Photo?
    @State private var showQuickActions = false
    @State private var editingStoryCollection: Collection?
    @Namespace private var modeSwitchNamespace
    
    private var storyCollections: [Collection] {
        allCollections.filter { $0.type == .story }
            .filter { !$0.photos.filter({ $0.deletedAt == nil }).isEmpty }
            .sorted { ($0.startTime ?? Date.distantPast) > ($1.startTime ?? Date.distantPast) }
    }
    
    private var displayedPhotos: [Photo] {
        allPhotos.sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        allPhotosTab
        .sheet(isPresented: $showAddSheet) {
            BatchAddView()
        }
        .sheet(isPresented: $showTrashSheet) {
            TrashView()
        }
        .fullScreenCover(item: $storiesScreenSelectedCollection, onDismiss: {
            storiesScreenSelectedCollection = nil
            storiesScreenSelectedDayDate = nil
        }) { collection in
            if collection.type == .story {
                StoryDetailView(collection: collection, initialDayDate: storiesScreenSelectedDayDate)
            } else {
                CollectionDetailView(collection: collection)
            }
        }
    }
    
    // MARK: - All Photos Tab
    
    private var allPhotosTab: some View {
        GeometryReader { geo in
            let maxH = geo.size.height
            let panelMaxH = geo.size.height + geo.safeAreaInsets.bottom
            let safeBottom = geo.safeAreaInsets.bottom
            
            ZStack(alignment: .bottom) {
                homeBackgroundLayer
                photoPanel(maxH: maxH, panelMaxH: panelMaxH, safeBottom: safeBottom)
            }
            .onAppear {
                mapViewportHeight = maxH
            }
            .onChange(of: geo.size.height) { _, newValue in
                mapViewportHeight = newValue
            }
        }
        .onAppear {
            userLocationBootstrapper.requestIfNeeded()
        }
        .onReceive(userLocationBootstrapper.$latestCoordinate) { newCoordinate in
            guard let coordinate = newCoordinate else { return }
            if pendingCenterOnLocation {
                pendingCenterOnLocation = false
                focusMap(to: coordinate, mapHeight: mapViewportHeight, animated: true)
            } else {
                centerMapOnUserIfNeeded(coordinate, mapHeight: mapViewportHeight)
            }
        }
        .sheet(item: $editingPhoto, onDismiss: { editingPhoto = nil }) { photo in
            PhotoEditView(photo: photo)
        }
        .sheet(item: $editingStoryCollection, onDismiss: { editingStoryCollection = nil }) { story in
            EditStoryView(collection: story)
        }
        .sheet(item: $selectedPhotoForDetail) { photo in
            PhotoDetailView(photos: displayedPhotos, initialPhoto: photo)
        }
        .sheet(item: $mapStoryPickerPhoto) { photo in
            MapPhotoStoryListSheet(photo: photo) { story in
                mapStoryPickerPhoto = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    storiesScreenSelectedDayDate = photo.timestamp
                    storiesScreenSelectedCollection = story
                }
            }
            .presentationDetents([.height(280), .medium])
        }
        .sheet(isPresented: $showMapSearchSheet) {
            MapSearchSheet(
                allPhotos: displayedPhotos,
                currentCoordinate: userLocationBootstrapper.latestCoordinate
            ) { coordinate in
                showMapSearchSheet = false
                focusMap(to: coordinate, mapHeight: mapViewportHeight, animated: true)
            }
            .presentationDetents([.height(360)])
        }
    }

    private var homeBackgroundLayer: AnyView {
        switch homeMode {
        case .calendar:
            return AnyView(calendarModeLayer)
        case .stories:
            return AnyView(storiesModeLayer)
        case .map:
            return AnyView(mapModeLayer)
        }
    }

    private var calendarModeLayer: some View {
        CalendarStoriesView(
            storyCollections: storyCollections,
            onStoryTap: { story, tappedDate in
                storiesScreenSelectedDayDate = tappedDate
                storiesScreenSelectedCollection = story
            },
            onStoryTagTap: {
                focusedPhoto = nil
                calendarHighlightDate = nil
                calendarHighlightStoryIds = []
            },
            onAdd: { showAddSheet = true },
            onTrash: { showTrashSheet = true },
            highlightedDate: calendarHighlightDate,
            highlightedStoryIds: calendarHighlightStoryIds
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: currentPanelDetent + 18)
        }
        .transition(.opacity)
    }

    private var storiesModeLayer: some View {
        StoriesTimelineListView(
            storyCollections: storyCollections,
            onStoryTap: { story in
                storiesScreenSelectedDayDate = nil
                storiesScreenSelectedCollection = story
            },
            highlightedStoryIds: calendarHighlightStoryIds,
            onEditStory: { story in
                editingStoryCollection = story
            },
            onDeleteStory: { story in
                deleteStoryAndOrphanPhotos(story)
            }
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: currentPanelDetent + 18)
        }
        .transition(.opacity)
    }

    private var mapModeLayer: some View {
        ZStack(alignment: .topTrailing) {
            ClusteredPhotoMapView(
                photos: displayedPhotos,
                cameraPosition: $mapCameraPosition,
                showRouteLine: false,
                highlightedPhotoId: focusedPhoto?.id,
                highlightedStoryIds: calendarHighlightStoryIds,
                onClusterTapped: nil,
                onClusterStorySelect: { story, day in
                    storiesScreenSelectedDayDate = day
                    storiesScreenSelectedCollection = story
                },
                onPhotoTapped: { _ in }
            )
            mapFloatingButtons
        }
        .transition(.opacity)
    }

    private func photoPanel(maxH: CGFloat, panelMaxH: CGFloat, safeBottom: CGFloat) -> some View {
        DraggablePhotoPanel(maxH: panelMaxH, onDetentChanged: { currentPanelDetent = $0 }) { bottomInset in
            photoGridToolbar
                .zIndex(120)
            PhotoGridByDateView(
                photos: displayedPhotos,
                isSelectionMode: isPhotoSelectionMode,
                selectedIds: $selectedPhotoIds,
                extraBottomPadding: bottomInset + safeBottom + 20,
                highlightedPhotoId: focusedPhoto?.id,
                onPhotoTap: handleGridPhotoTap,
                onPhotoDoubleTap: { handleGridPhotoDoubleTap($0, mapHeight: maxH) },
                onPhotoLongPress: handleGridPhotoLongPress,
                onEdit: { editingPhoto = $0 },
                onDelete: handleGridPhotoDelete
            )
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }

    private func handleGridPhotoTap(_ photo: Photo) {
        // 点击照片一律进入照片详情栏（与正常一致）
        selectedPhotoForDetail = photo
    }

    private func handleGridPhotoDoubleTap(_ photo: Photo, mapHeight: CGFloat) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let targetStoryIds = Set(
            photo.collections
                .filter { $0.type == .story && $0.deletedAt == nil }
                .map(\.id)
        )
        let samePhoto = focusedPhoto?.id == photo.id
        let sameDay = calendarHighlightDate.map { Calendar.current.isDate($0, inSameDayAs: photo.timestamp) } ?? false
        let sameStories = calendarHighlightStoryIds == targetStoryIds

        // 再次双击同一定位目标：全部取消
        if samePhoto && sameDay && sameStories {
            focusedPhoto = nil
            calendarHighlightDate = nil
            calendarHighlightStoryIds = []
            return
        }

        // 三端同步定位：地图 + 日历 + stories list 同时更新
        focusedPhoto = photo
        calendarHighlightDate = photo.timestamp
        calendarHighlightStoryIds = targetStoryIds
        if let coord = photo.coordinate {
            focusMap(to: coord, mapHeight: mapHeight, animated: true)
        }
    }

    private func handleGridPhotoLongPress(_ photo: Photo) {
        if !isPhotoSelectionMode {
            isPhotoSelectionMode = true
        }
    }

    private func handleGridPhotoDelete(_ photo: Photo) {
        if focusedPhoto?.id == photo.id {
            focusedPhoto = nil
        }
        photo.deletedAt = Date()
        try? modelContext.save()
    }
    
    /// 删除回忆时：标记 story 已删除，并软删除「仅属于该回忆」的照片（仍在其他回忆里的照片保留）
    private func deleteStoryAndOrphanPhotos(_ story: Collection) {
        let photosInStory = story.photos.filter { $0.deletedAt == nil }
        for photo in photosInStory {
            let otherStories = photo.collections.filter {
                $0.type == .story && $0.deletedAt == nil && $0.id != story.id
            }
            if otherStories.isEmpty {
                photo.deletedAt = Date()
            }
        }
        story.deletedAt = Date()
        try? modelContext.save()
    }
    
    /// 照片工具栏
    private var photoGridToolbar: some View {
        HStack {
            if isPhotoSelectionMode {
                toolbarIconButton(icon: "xmark") {
                    isPhotoSelectionMode = false
                    selectedPhotoIds.removeAll()
                }
                
                Spacer()
                
                if !selectedPhotoIds.isEmpty {
                    toolbarIconButton(icon: "trash", tint: Color(red: 0.90, green: 0.40, blue: 0.35)) {
                        movePhotosToTrash(ids: selectedPhotoIds)
                        selectedPhotoIds.removeAll()
                        isPhotoSelectionMode = false
                    }
                }
                
                toolbarIconButton(icon: "checkmark.circle") {
                    selectedPhotoIds = Set(displayedPhotos.map { $0.id })
                }
            } else {
                Text("\(displayedPhotos.count) 张照片")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                modeSwitcher
                toolbarMoreMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var modeSwitcher: some View {
        let orderedModes: [HomeDisplayMode] = [.stories, .calendar, .map]
        return HStack(spacing: 6) {
            ForEach(orderedModes, id: \.rawValue) { mode in
                let selected = homeMode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        homeMode = mode
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        if selected {
                            Circle()
                                .fill(AppTheme.pillBackground)
                                .matchedGeometryEffect(id: "mode_selection", in: modeSwitchNamespace)
                        }
                        Image(systemName: mode.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selected ? AppTheme.pillForeground : AppTheme.pillForeground.opacity(0.5))
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var toolbarMoreMenu: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showQuickActions.toggle()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.pillForeground)
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(AppTheme.pillBackground)
                    }
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .overlay(alignment: .top) {
            quickActionsPopup
        }
        .zIndex(200)
    }

    private var quickActionsPopup: some View {
        VStack(spacing: 8) {
            quickActionCircle(icon: "plus") {
                showAddSheet = true
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    showQuickActions = false
                }
            }
            quickActionCircle(icon: "checkmark.circle.fill") {
                isPhotoSelectionMode = true
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    showQuickActions = false
                }
            }
            quickActionCircle(icon: "trash", destructive: true) {
                showTrashSheet = true
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    showQuickActions = false
                }
            }
        }
        .frame(width: 36)
        .offset(y: 42)
        .scaleEffect(showQuickActions ? 1 : 0.18, anchor: .top)
        .opacity(showQuickActions ? 1 : 0)
        .allowsHitTesting(showQuickActions)
        .zIndex(220)
    }

    private func quickActionCircle(icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(destructive ? Color(red: 0.88, green: 0.40, blue: 0.35) : AppTheme.pillForeground)
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(AppTheme.pillBackground)
                    }
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }

    private func toolbarIconButton(icon: String, tint: Color = AppTheme.pillForeground, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(AppTheme.pillBackground)
                    }
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }
    
    // MARK: - Map Floating Buttons

    private var mapFloatingButtons: some View {
        HStack(spacing: 10) {
            mapFab(icon: "magnifyingglass") { showMapSearchSheet = true }
            mapFab(icon: "location.fill") { returnToCurrentLocation() }
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    private func mapFab(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.pillForeground)
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(AppTheme.pillBackground)
                    }
                )
                .shadow(color: Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.14), radius: 4, y: 2)
        }
    }

    @State private var pendingCenterOnLocation = false

    private func returnToCurrentLocation() {
        if let coord = userLocationBootstrapper.latestCoordinate {
            focusMap(to: coord, mapHeight: mapViewportHeight, animated: true)
        }
        pendingCenterOnLocation = true
        userLocationBootstrapper.forceRequestLocation()
    }

    private func movePhotosToTrash(ids: Set<UUID>) {
        let now = Date()
        let toTrash = displayedPhotos.filter { ids.contains($0.id) }
        for photo in toTrash {
            photo.deletedAt = now
        }
        try? modelContext.save()
    }

    private func centerMapOnUserIfNeeded(_ coordinate: CLLocationCoordinate2D, mapHeight: CGFloat) {
        guard !hasCenteredOnUserLocation, focusedPhoto == nil else { return }
        hasCenteredOnUserLocation = true
        focusMap(to: coordinate, mapHeight: mapHeight, animated: true)
    }

    private func focusMap(to coordinate: CLLocationCoordinate2D, mapHeight: CGFloat, animated: Bool) {
        let visibleMapFraction = max(0.1, 1.0 - (currentPanelDetent / max(mapHeight, 1)))
        let spanDelta = 0.05
        let latOffset = spanDelta * visibleMapFraction * 0.5
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - latOffset,
            longitude: coordinate.longitude
        )
        let action = {
            mapCameraPosition = .region(
                MKCoordinateRegion(
                    center: adjustedCenter,
                    span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
                )
            )
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) { action() }
        } else {
            action()
        }
    }
}

// MARK: - Draggable Photo Panel

/// 仿苹果地图/股票的可拖拽底部面板。
/// 核心原理：面板始终占满 maxDetent 高度，通过 offset 上下移动，
/// 内部 ScrollView 布局永远不变 → 零抖动、零重排。
private struct DraggablePhotoPanel<Content: View>: View {
    let maxH: CGFloat
    var onDetentChanged: ((CGFloat) -> Void)?
    /// content 接收一个参数：面板底部被屏幕遮挡的高度，外部应加到 ScrollView 的 bottom padding
    @ViewBuilder let content: (_ bottomInset: CGFloat) -> Content

    // 当前吸附的"露出高度"
    @State private var snappedDetent: CGFloat = 0
    // 拖拽中的实时偏移量
    @State private var dragDelta: CGFloat = 0
    @State private var hasInitialized = false

    private var minDetent: CGFloat { 100 }
    private var midDetent: CGFloat { maxH * 0.4 }
    private var maxDetent: CGFloat { maxH * 0.88 }
    private var detents: [CGFloat] { [minDetent, midDetent, maxDetent] }

    /// 面板顶部距屏幕底部的偏移（正值 = 向下，即隐藏更多）
    private var panelOffset: CGFloat {
        guard hasInitialized else { return maxDetent } // 未初始化时完全藏在屏幕外
        // dragDelta 直接就是 translation.height（向下为正）
        // 露出高度 = snappedDetent - dragDelta（往下拉 → 露出变少）
        let targetExposed = rubberBandExposed(snappedDetent - dragDelta)
        return maxDetent - targetExposed
    }

    var body: some View {
        let roundedShape = UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)

        // 面板底部被屏幕遮挡的高度 = maxDetent - 当前露出高度
        let bottomInset = max(0, maxDetent - snappedDetent)

        VStack(spacing: 0) {
            dragHandle
            content(bottomInset)
        }
        // 面板始终是 maxDetent 高度 —— 内部布局完全稳定，ScrollView 无需重新布局
        .frame(maxWidth: .infinity)
        .frame(height: maxDetent, alignment: .top)
        .background(roundedShape.fill(.regularMaterial))
        .clipShape(roundedShape)
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
        // 只用 offset 控制显示位置，不改变任何布局
        .offset(y: panelOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 280, damping: 36)) {
                initializeIfNeeded()
            }
        }
        .onChange(of: maxH) { _, _ in
            guard hasInitialized else { initializeIfNeeded(); return }
            let clamped = clampedDetent(snappedDetent)
            snappedDetent = clamped
            dragDelta = 0
            onDetentChanged?(clamped)
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color(red: 0.65, green: 0.55, blue: 0.44).opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
            .gesture(panelDragGesture)
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                // translation.height: 正 = 向下拖，负 = 向上拖
                // 直接存原始值，panelOffset 里用 snappedDetent - dragDelta 算露出高度
                dragDelta = value.translation.height
            }
            .onEnded { value in
                let translation = value.translation.height
                // 当前实时露出高度
                let currentExposed = clampedDetent(snappedDetent - translation)
                // 用惯性预测最终位置
                let velocityDelta = value.predictedEndTranslation.height - translation
                let projected = clampedDetent(currentExposed - velocityDelta * 0.12)
                let target = nearestDetent(to: projected)

                // 锁定当前位置，然后动画到目标
                snappedDetent = currentExposed
                dragDelta = 0

                withAnimation(.interpolatingSpring(stiffness: 320, damping: 38)) {
                    snappedDetent = target
                }
                onDetentChanged?(target)
            }
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true
        snappedDetent = midDetent
        dragDelta = 0
        onDetentChanged?(midDetent)
    }

    private func clampedDetent(_ h: CGFloat) -> CGFloat {
        min(max(h, minDetent), maxDetent)
    }

    private func rubberBandExposed(_ exposed: CGFloat) -> CGFloat {
        if exposed < minDetent {
            return minDetent - (minDetent - exposed) * 0.25
        }
        if exposed > maxDetent {
            return maxDetent + (exposed - maxDetent) * 0.22
        }
        return exposed
    }

    private func nearestDetent(to h: CGFloat) -> CGFloat {
        detents.min(by: { abs($0 - h) < abs($1 - h) }) ?? midDetent
    }
}

private struct StoriesTimelineListView: View {
    let storyCollections: [Collection]
    var onStoryTap: (Collection) -> Void
    var highlightedStoryIds: Set<UUID> = []
    var onEditStory: (Collection) -> Void = { _ in }
    var onDeleteStory: (Collection) -> Void = { _ in }

    @State private var showStorySearch = false
    @State private var scrollTarget: UUID?

    struct Item: Identifiable {
        let id: UUID
        let collection: Collection
        let start: Date
        let end: Date
        let photos: [Photo]
    }

    private var items: [Item] {
        storyCollections.compactMap { c in
            let photos = c.photos.filter { $0.deletedAt == nil }.sorted { $0.timestamp < $1.timestamp }
            let start = c.startTime ?? photos.first?.timestamp
            let end = c.endTime ?? photos.last?.timestamp
            guard let start else { return nil }
            return Item(id: c.id, collection: c, start: start, end: end ?? start, photos: photos)
        }
        .sorted { $0.start < $1.start } // 最新在底部
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                List {
                    Color.clear
                        .frame(height: 54)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    ForEach(items) { item in
                        storyListRow(item)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    guard let latest = items.last?.id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        proxy.scrollTo(latest, anchor: .bottom)
                    }
                }
                .onChange(of: highlightedStoryIds) { _, ids in
                    guard let target = items.first(where: { ids.contains($0.id) })?.id else { return }
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollTarget = nil
                }
            }

            HStack(spacing: 10) {
                fab(icon: "magnifyingglass") { showStorySearch = true }
                fab(icon: "arrow.down") { scrollTarget = items.last?.id }
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showStorySearch) {
            StorySearchSheet(items: items) { targetId in
                scrollTarget = targetId
                showStorySearch = false
            }
            .presentationDetents([.height(360)])
        }
    }

    private func storyListRow(_ item: Item) -> some View {
        let tagColor = AppTheme.storyColor(category: item.collection.storyCategory, storyId: item.collection.id)
        let isHighlighted = highlightedStoryIds.contains(item.id)

        return Button {
            onStoryTap(item.collection)
        } label: {
            StoryTimelineRowView(item: item, tagColor: tagColor, isHighlighted: isHighlighted)
                .padding(.horizontal, isHighlighted ? 2 : 0)
                .padding(.vertical, isHighlighted ? 1 : 0)
        }
        .buttonStyle(.plain)
        .id(item.id)
        .listRowInsets(.init(top: isHighlighted ? 5 : 4, leading: 12, bottom: isHighlighted ? 5 : 4, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDeleteStory(item.collection)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.red))
            }
            .tint(Color.red.opacity(0.9))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEditStory(item.collection)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppTheme.accent))
            }
            .tint(AppTheme.accent.opacity(0.85))
        }
    }

    private func fab(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.pillForeground)
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(AppTheme.pillBackground)
                    }
                )
                .shadow(color: Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.14), radius: 4, y: 2)
        }
    }
}

private struct StoryTimelineRowView: View {
    let item: StoriesTimelineListView.Item
    let tagColor: Color
    let isHighlighted: Bool

    private var covers: [Photo] {
        Array(item.photos.sorted { $0.timestamp > $1.timestamp }.prefix(3))
    }

    private var dateRangeText: String {
        let startText = item.start.formatted(.dateTime.year().month().day())
        let endText = item.end.formatted(.dateTime.year().month().day())
        return "\(startText) - \(endText)"
    }

    private var chevronColor: Color {
        if isHighlighted { return Color.accentColor.opacity(0.95) }
        return Color(.quaternaryLabel)
    }

    private var cardBackgroundColor: Color {
        if isHighlighted { return Color.accentColor.opacity(0.14) }
        return AppTheme.cardBackground
    }

    private var cardStrokeColor: Color {
        if isHighlighted { return Color.accentColor.opacity(0.95) }
        return Color.black.opacity(0.07)
    }

    private var cardStrokeWidth: CGFloat {
        isHighlighted ? 3.0 : 0.8
    }

    private var cardShadowColor: Color {
        if isHighlighted { return Color.accentColor.opacity(0.2) }
        return .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(Array(covers.indices.reversed()), id: \.self) { i in
                    let p = covers[i]
                    PhotoThumbnailView(
                        localIdentifier: p.assetLocalId,
                        size: nil,
                        cornerRadius: 5,
                        requestSize: CGSize(width: 80, height: 80)
                    )
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(.systemBackground), lineWidth: 1.5))
                    .offset(x: CGFloat(i) * 3, y: CGFloat(i) * -2)
                }
            }
            .frame(width: 46, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.collection.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    MapStoryTypeDot(
                        symbolName: item.collection.storyCategory.symbolName,
                        color: tagColor,
                        size: 11,
                        iconSize: 7
                    )
                    Text("\(item.photos.count) 张")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(dateRangeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(chevronColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
        )
        .shadow(color: cardShadowColor, radius: 6, y: 2)
    }
}

private struct StorySearchSheet: View {
    struct Row: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
    }

    let items: [StoriesTimelineListView.Item]
    var onSelect: (UUID) -> Void
    @State private var query = ""

    private var rows: [Row] {
        items.map {
            Row(
                id: $0.id,
                title: $0.collection.title,
                subtitle: "\($0.start.formatted(.dateTime.year().month().day())) - \($0.end.formatted(.dateTime.year().month().day()))"
            )
        }
    }

    private var filtered: [Row] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return Array(rows.suffix(12).reversed()) } // 推荐：最近
        return rows.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索回忆名称", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section(query.isEmpty ? "推荐" : "搜索结果") {
                    ForEach(filtered) { row in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(row.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(row.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("查找回忆")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private final class UserLocationBootstrapper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latestCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var requested = false
    private var requestedLocationAfterAuthorized = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestIfNeeded() {
        guard !requested else { return }
        requested = true
        handleAuthorization(manager.authorizationStatus)
    }

    func forceRequestLocation() {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedLocationAfterAuthorized else { return }
            requestedLocationAfterAuthorized = true
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 用户拒绝或短时定位失败时，不打断主流程
    }
}

/// 地图中“已定位照片”二次点击后展示的 story 列表
private struct MapPhotoStoryListSheet: View {
    let photo: Photo
    var onSelect: (Collection) -> Void

    private var stories: [Collection] {
        photo.collections
            .filter { $0.type == .story && $0.deletedAt == nil }
            .sorted { ($0.startTime ?? Date.distantPast) > ($1.startTime ?? Date.distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if stories.isEmpty {
                    ContentUnavailableView(
                        "这张照片还不在回忆里",
                        systemImage: "tray",
                        description: Text("你可以先把它加入一个 Story")
                    )
                } else {
                    List {
                        ForEach(stories, id: \.id) { story in
                            Button {
                                onSelect(story)
                            } label: {
                                HStack(spacing: 10) {
                                    MapStoryTypeDot(
                                        symbolName: story.storyCategory.symbolName,
                                        color: AppTheme.storyColor(category: story.storyCategory, storyId: story.id),
                                        size: 20,
                                        iconSize: 11
                                    )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(story.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text((story.startTime ?? photo.timestamp).formatted(.dateTime.month().day()))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("所属回忆")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MapStoryTypeDot: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 20
    var iconSize: CGFloat = 11

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
            Circle()
                .stroke(color.opacity(0.9), lineWidth: 1.1)
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    MemoriesHomeView()
        .modelContainer(for: [Photo.self, Collection.self, Event.self], inMemory: true)
}
