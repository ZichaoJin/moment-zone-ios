//
//  StoryDetailView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData

/// Story 详情视图：进入 Story 后只看这个 Story 的数据，地图自动 fit bounds
struct StoryDetailView: View {
    @Bindable var collection: Collection
    var initialDayDate: Date?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showNoLocationSheet = false
    @State private var showStoryVideoGenerate = false
    @State private var showJourneyViewer = false
    @State private var viewerInitialDayDate: Date?
    @State private var viewerInitialEventId: UUID?
    @State private var selectedOverviewEventId: UUID?
    
    init(collection: Collection, initialDayDate: Date? = nil) {
        self.collection = collection
        self.initialDayDate = initialDayDate
    }
    
    /// Story 中的所有照片（排除已删除，与全部相册同步）
    private var storyPhotos: [Photo] {
        collection.photos.filter { $0.deletedAt == nil }.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// 无位置的照片
    private var photosWithoutLocation: [Photo] {
        storyPhotos.filter { $0.coordinate == nil }
    }

    private var overviewEvents: [StoryOverviewEvent] {
        if !collection.events.isEmpty {
            let sortedEvents = collection.events.sorted { $0.startTime < $1.startTime }
            return sortedEvents.compactMap { event in
                let photos = storyPhotos.filter { $0.eventId == event.id }.sorted { $0.timestamp < $1.timestamp }
                guard !photos.isEmpty else { return nil }
                let title = event.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? event.locationName!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : (photos.first?.displayLocationName.isEmpty == false ? photos.first!.displayLocationName : "这段回忆")
                return StoryOverviewEvent(
                    id: event.id,
                    title: title,
                    coordinate: photos.first?.coordinate,
                    day: Calendar.current.startOfDay(for: event.startTime),
                    photos: photos
                )
            }
        }

        let grouped = Dictionary(grouping: storyPhotos) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted().compactMap { day in
            let photos = (grouped[day] ?? []).sorted { $0.timestamp < $1.timestamp }
            guard !photos.isEmpty else { return nil }
            return StoryOverviewEvent(
                id: UUID(),
                title: photos.first?.displayLocationName.isEmpty == false ? photos.first!.displayLocationName : "这段回忆",
                coordinate: photos.first?.coordinate,
                day: day,
                photos: photos
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showJourneyViewer {
                    JourneyMemoryView(
                        collection: collection,
                        initialDayDate: viewerInitialDayDate ?? initialDayDate,
                        initialEventId: viewerInitialEventId
                    )
                } else {
                    StoryOverviewMapPage(
                        storyTitle: collection.title,
                        storyNote: collection.note,
                        storyCategory: collection.storyCategory,
                        storyId: collection.id,
                        events: overviewEvents,
                        selectedEventId: $selectedOverviewEventId,
                        onBackTap: { dismiss() },
                        onGenerateVideoTap: { showStoryVideoGenerate = true },
                        onEventOpen: { event in
                            viewerInitialEventId = event.id
                            viewerInitialDayDate = event.day
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showJourneyViewer = true
                            }
                        }
                    )
                }
            }
            .onAppear {
                guard selectedOverviewEventId == nil, let initialDayDate else { return }
                let targetDay = Calendar.current.startOfDay(for: initialDayDate)
                selectedOverviewEventId = overviewEvents.first(where: { Calendar.current.isDate($0.day, inSameDayAs: targetDay) })?.id
            }
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(true)
            .sheet(isPresented: $showNoLocationSheet) {
                NoLocationPhotosSheet(
                    collection: collection,
                    onDismiss: { showNoLocationSheet = false }
                )
            }
            .sheet(isPresented: $showStoryVideoGenerate) {
                StoryVideoGenerateView(collection: collection)
            }
        }
    }
}

private struct StoryOverviewEvent: Identifiable {
    let id: UUID
    let title: String
    let coordinate: CLLocationCoordinate2D?
    let day: Date
    let photos: [Photo]
}

/// 相机运行态：非响应式存储，避免每帧都触发 SwiftUI 重绘。
private final class StoryMapRuntimeStore: ObservableObject {
    var displayedRegion: MKCoordinateRegion?
}

private struct StoryOverviewMapPage: View {
    let storyTitle: String
    let storyNote: String?
    let storyCategory: StoryCategory
    let storyId: UUID
    let events: [StoryOverviewEvent]
    @Binding var selectedEventId: UUID?
    var onBackTap: () -> Void
    var onGenerateVideoTap: () -> Void
    var onEventOpen: (StoryOverviewEvent) -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastHapticEventId: UUID?
    @State private var previousSelectedCoord: CLLocationCoordinate2D?
    @State private var isCameraAnimating = false

    // MARK: - 沉浸式照片模式
    @State private var isImmersive = false
    @State private var immersivePhotoIndex: Int = 0
    @State private var immersiveEventIndex: Int = 0
    @State private var isProgressScrubbing = false
    @State private var scrubPreviewEventIndex: Int?
    @State private var scrubPreviewOffsetX: CGFloat = 0
    @State private var railFocusedEventId: UUID?
    @State private var syncingRailSelection = false
    @State private var suppressRailFeedbackUntil: Date = .distantPast

    // MARK: - 路线动画
    /// passed 路线在 curvedFullRoute 上截取到第几个点（动画驱动）
    @State private var passedCurveEnd: Int = 0
    @State private var cameraAnimTimer: Timer?
    @StateObject private var runtimeStore = StoryMapRuntimeStore()

    /// 当前沉浸模式下的照片列表（当前激活 event 的照片）
    private var immersivePhotos: [Photo] {
        guard immersiveEventIndex >= 0, immersiveEventIndex < events.count else { return [] }
        return events[immersiveEventIndex].photos
    }

    /// 所有 event 最终落脚放大级别（固定不变）
    private let finalSpanDelta: Double = 0.0120
    /// 近距离阈值：两点在此距离内直接平移，不需要缩小镜头
    private let nearThresholdMeters: Double = 1200
    /// 概览模式下把选中点轻微上提，让位置更接近屏幕中线
    private let overviewLiftFactor: Double = -0.01

    private var selectedEvent: StoryOverviewEvent? {
        if let selectedEventId, let found = events.first(where: { $0.id == selectedEventId }) {
            return found
        }
        return events.first
    }

    private var normalizedNote: String {
        (storyNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldScrollNote: Bool {
        normalizedNote.count > 54
    }

    private var routePoints: [(id: UUID, coordinate: CLLocationCoordinate2D)] {
        events.compactMap { event in
            guard let coordinate = event.coordinate else { return nil }
            return (id: event.id, coordinate: coordinate)
        }
    }

    private var activeImmersiveEventIndex: Int {
        if isProgressScrubbing, let idx = scrubPreviewEventIndex {
            return min(max(idx, 0), max(events.count - 1, 0))
        }
        return min(max(immersiveEventIndex, 0), max(events.count - 1, 0))
    }

    private var isRailFeedbackSuppressed: Bool {
        Date() < suppressRailFeedbackUntil
    }

    private var selectedRouteIndex: Int? {
        guard let selectedId = selectedEvent?.id else { return nil }
        return routePoints.firstIndex(where: { $0.id == selectedId })
    }

    private var fullRouteCoordinates: [CLLocationCoordinate2D] {
        routePoints.map(\.coordinate)
    }

    private var curvedFullRouteCoordinates: [CLLocationCoordinate2D] {
        curvedCoordinates(from: fullRouteCoordinates)
    }

    /// passed 路线：直接从完整曲线截取前 passedCurveEnd 个点
    private var curvedPassedRouteCoordinates: [CLLocationCoordinate2D] {
        let all = curvedFullRouteCoordinates
        guard passedCurveEnd > 0, !all.isEmpty else { return [] }
        let end = min(passedCurveEnd + 1, all.count)
        return Array(all.prefix(end))
    }

    /// 路线头部高亮片段（用于表示“正在前进”）
    private var curvedRouteHeadCoordinates: [CLLocationCoordinate2D] {
        let passed = curvedPassedRouteCoordinates
        guard passed.count > 1 else { return [] }
        return Array(passed.suffix(min(7, passed.count)))
    }

    /// 非选中点展示坐标预计算：避免每个 annotation 都重复遍历 events。
    private var nonHighlightedDisplayCoordinates: [UUID: CLLocationCoordinate2D] {
        let tolerance = 0.00012
        let bucketStep = tolerance
        let items: [(id: UUID, coordinate: CLLocationCoordinate2D)] = events.compactMap { event in
            guard let coordinate = event.coordinate else { return nil }
            return (event.id, coordinate)
        }
        guard !items.isEmpty else { return [:] }

        var buckets: [String: [(id: UUID, coordinate: CLLocationCoordinate2D)]] = [:]
        for item in items {
            let latKey = Int((item.coordinate.latitude / bucketStep).rounded())
            let lonKey = Int((item.coordinate.longitude / bucketStep).rounded())
            let key = "\(latKey)_\(lonKey)"
            buckets[key, default: []].append(item)
        }

        var output: [UUID: CLLocationCoordinate2D] = [:]
        for (_, group) in buckets {
            if group.count == 1, let only = group.first {
                output[only.id] = only.coordinate
                continue
            }

            let count = group.count
            for (index, entry) in group.enumerated() {
                let base = entry.coordinate
                let angle = (2.0 * Double.pi / Double(count)) * Double(index)
                let radius = 0.00018 + Double(min(count, 6)) * 0.00002
                let latOffset = sin(angle) * radius
                let lonScale = max(cos(base.latitude * Double.pi / 180.0), 0.35)
                let lonOffset = (cos(angle) * radius) / lonScale
                output[entry.id] = CLLocationCoordinate2D(
                    latitude: base.latitude + latOffset,
                    longitude: base.longitude + lonOffset
                )
            }
        }
        return output
    }

    /// routePoint index → 对应的曲线采样点 index（每段 12 点）
    private func curveIndex(forRoutePoint index: Int) -> Int {
        min(index * 12, max(curvedFullRouteCoordinates.count - 1, 0))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                if curvedFullRouteCoordinates.count > 1 {
                    MapPolyline(coordinates: curvedFullRouteCoordinates)
                        .stroke(
                            Color(red: 0.71, green: 0.62, blue: 0.53).opacity(0.24),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [3, 7])
                        )
                }

                if curvedPassedRouteCoordinates.count > 1 {
                    MapPolyline(coordinates: curvedPassedRouteCoordinates)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.86, green: 0.78, blue: 0.68).opacity(0.95),
                                    Color(red: 0.76, green: 0.64, blue: 0.52).opacity(0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                        )
                }

                if curvedRouteHeadCoordinates.count > 1 {
                    MapPolyline(coordinates: curvedRouteHeadCoordinates)
                        .stroke(
                            Color(red: 0.97, green: 0.90, blue: 0.78).opacity(0.96),
                            style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
                        )
                }

                let selectedId = selectedEvent?.id
                let selectedCoord = selectedEvent?.coordinate

                // 转场中直接跳过非选中 annotation，避免无效布局计算导致卡顿
                if !isCameraAnimating {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                        if event.id != selectedId,
                           let coordinate = displayCoordinate(for: event, highlighted: false),
                           !isOverlappingSelected(event, selectedCoord: selectedCoord) {
                            Annotation("", coordinate: coordinate) {
                                Button {
                                    selectedEventId = event.id
                                } label: {
                                    OverviewEventPinDot(isNeighborOfSelected: isNeighborOfSelected(event))
                                }
                                .buttonStyle(.plain)
                                .zIndex(0)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }

                // 选中的 annotation：沉浸时只显示小圆点，否则可点击进入沉浸模式
                if let selected = selectedEvent,
                   let coordinate = displayCoordinate(for: selected, highlighted: true),
                   (!isCameraAnimating || isImmersive) {
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        if isImmersive {
                            if isCameraAnimating {
                                OverviewEventMovingPin()
                            } else {
                                ImmersiveEventMapAnchor(title: selected.title)
                            }
                        } else {
                            Button {
                                enterImmersiveMode()
                            } label: {
                                OverviewEventPinCallout(event: selected, highlighted: true)
                            }
                            .buttonStyle(.plain)
                            .zIndex(999)
                        }
                    }
                    .annotationTitles(.hidden)
                }

            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .allowsHitTesting(!isImmersive)
            .onAppear { setupInitialCamera() }
            .onDisappear {
                cameraAnimTimer?.invalidate()
                cameraAnimTimer = nil
            }
            .onChange(of: selectedEventId) { oldValue, newValue in
                guard let firstId = events.first?.id else { return }
                if newValue == nil || !events.contains(where: { $0.id == newValue }) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedEventId = firstId
                    }
                    return
                }
                if let newValue, newValue != lastHapticEventId {
                    UISelectionFeedbackGenerator().selectionChanged()
                    lastHapticEventId = newValue
                }
                if !isImmersive {
                    if let oldId = oldValue,
                       let oldEvent = events.first(where: { $0.id == oldId }),
                       let oldCoord = oldEvent.coordinate {
                        previousSelectedCoord = oldCoord
                    }
                    // 立即对焦，让动画更流畅（滑动和点击一致）
                    focusOnSelectedEvent(animated: true)
                }
            }

            // 前景层：沉浸时显示照片浮层，否则显示概览（滚轮 + 标题）
            if isImmersive {
                immersiveOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack {
                Spacer()
                GeometryReader { geo in
                    let itemWidth: CGFloat = 140
                    let horizontalInset = max(0, (geo.size.width - itemWidth) * 0.5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(events) { event in
                                OverviewEventRailCard(
                                    event: event,
                                    highlighted: event.id == selectedEvent?.id
                                )
                                .frame(width: itemWidth)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.82)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.96)
                                }
                                .id(event.id)
                                .onTapGesture {
                                    // 下方点击只定位到地图里对应的 story，不进入回忆/immersive
                                    if selectedEventId != event.id {
                                        // 使用与滑动一致的动画，避免卡顿
                                        selectedEventId = event.id
                                    }
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .safeAreaPadding(.horizontal, horizontalInset)
                    .scrollPosition(id: $railFocusedEventId, anchor: .center)
                    .onChange(of: railFocusedEventId) { _, newValue in
                        if syncingRailSelection || isRailFeedbackSuppressed { return }
                        guard let newValue else { return }
                        guard events.contains(where: { $0.id == newValue }) else { return }
                        if selectedEventId != newValue {
                            selectedEventId = newValue
                        }
                    }
                    .onChange(of: selectedEventId) { _, newValue in
                        if railFocusedEventId != newValue {
                            syncingRailSelection = true
                            railFocusedEventId = newValue
                            DispatchQueue.main.async {
                                syncingRailSelection = false
                            }
                        }
                        // 从后往前滑动过头时，强制吸附到第一个
                        if newValue == nil || !events.contains(where: { $0.id == newValue }) {
                            if let firstId = events.first?.id {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedEventId = firstId
                                }
                            }
                        }
                    }
                }
                .frame(height: 146)
                .padding(.bottom, 18)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    StoryListTypeDot(
                        symbolName: storyCategory.symbolName,
                        color: AppTheme.storyColor(category: storyCategory, storyId: storyId),
                        size: 28,
                        iconSize: 13
                    )
                    Text(storyTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if !normalizedNote.isEmpty {
                    if shouldScrollNote {
                        ScrollView(showsIndicators: true) {
                            Text(normalizedNote)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.95))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        )
                    } else {
                        Text(normalizedNote)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                    }
                }
                Spacer()
            }
            .padding(.leading, 14)
            .padding(.trailing, 110)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.30), Color.black.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)

            if !isImmersive {
                HStack {
                    Spacer()
                    floatingControlButton(icon: "movieclapper", action: onGenerateVideoTap)
                    .padding(.trailing, 8)
                    floatingControlButton(icon: "xmark", action: onBackTap)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - 沉浸模式 UI（全屏浮动：照片居中，底部控制条）

    @ViewBuilder
    private var immersiveOverlay: some View {
        GeometryReader { geo in
            let bottomBarH: CGFloat = 44 + max(geo.safeAreaInsets.bottom, 16)
            let carouselH: CGFloat = geo.size.height * 0.56

            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        exitImmersiveMode()
                    }

                ImmersivePhotoCarousel(
                    photos: immersivePhotos,
                    currentIndex: $immersivePhotoIndex,
                    onTargetIndex: handleImmersiveTargetIndex
                )
                .frame(height: carouselH)
                .frame(maxWidth: .infinity)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
                .onTapGesture { }

                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        if isProgressScrubbing, events.indices.contains(activeImmersiveEventIndex) {
                            Text(events[activeImmersiveEventIndex].day.formatted(.dateTime.month().day()))
                                .font(.system(size: isProgressScrubbing ? 14 : 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.86))
                                .scaleEffect(isProgressScrubbing ? 1.14 : 1)
                                .offset(x: scrubPreviewOffsetX)
                                .animation(.easeOut(duration: 0.16), value: isProgressScrubbing)
                                .animation(.easeOut(duration: 0.08), value: scrubPreviewOffsetX)
                        }

                        HStack(alignment: .center, spacing: 10) {
                            Text("\(immersivePhotoIndex + 1)/\(max(immersivePhotos.count, 1))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.38))
                                .frame(width: 32, alignment: .leading)

                            immersiveProgressBar
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 16))
                }
                .background(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.52)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
                .frame(height: bottomBarH + 36)
                .onTapGesture { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let isVertical = abs(value.translation.height) > abs(value.translation.width) * 1.2
                    if isVertical && value.translation.height > 60 {
                        exitImmersiveMode()
                    }
                }
        )
    }

    @ViewBuilder
    private var immersiveProgressBar: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, _ in
                    let passed = idx <= activeImmersiveEventIndex
                    let isCurrent = idx == activeImmersiveEventIndex
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            passed
                                ? AppTheme.accent.opacity(isCurrent ? 0.98 : 0.70)
                                : Color.white.opacity(0.30)
                        )
                        .frame(height: isCurrent ? 4 : 3)
                        .animation(.easeOut(duration: 0.16), value: activeImmersiveEventIndex)
                        .onTapGesture {
                            jumpToImmersiveEvent(idx: idx)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.vertical, 4)
            .background(Color.clear)
            .contentShape(Rectangle())
            .gesture(progressScrubGesture(totalWidth: geo.size.width))
        }
        .frame(height: 30)
    }

    private func handleImmersiveTargetIndex(_ rawTarget: Int) {
        if rawTarget < 0 {
            if immersiveEventIndex > 0 {
                let newEventIdx = immersiveEventIndex - 1
                let newPhotoCount = events[newEventIdx].photos.count
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                jumpToImmersiveEvent(idx: newEventIdx, photoIndex: max(newPhotoCount - 1, 0))
            }
        } else if rawTarget >= immersivePhotos.count, immersiveEventIndex < events.count - 1 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            jumpToImmersiveEvent(idx: immersiveEventIndex + 1, photoIndex: 0)
        }
    }

    private func jumpToImmersiveEvent(idx: Int, photoIndex: Int = 0) {
        guard idx >= 0, idx < events.count else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            immersiveEventIndex = idx
            immersivePhotoIndex = photoIndex
            selectedEventId = events[idx].id
        }
        focusOnImmersiveEvent(idx: idx)
    }

    private func progressScrubGesture(totalWidth: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.20)
            .onEnded { _ in
                isProgressScrubbing = true
                scrubPreviewEventIndex = immersiveEventIndex
                scrubPreviewOffsetX = 0
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .simultaneously(with:
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isProgressScrubbing, !events.isEmpty else { return }
                        let x = min(max(value.location.x, 0), totalWidth)
                        let ratio = x / max(totalWidth, 1)
                        let idx = min(events.count - 1, max(0, Int(round(ratio * CGFloat(max(events.count - 1, 1))))))
                        if scrubPreviewEventIndex != idx {
                            scrubPreviewEventIndex = idx
                            UISelectionFeedbackGenerator().selectionChanged()
                            if immersiveEventIndex != idx {
                                immersiveEventIndex = idx
                                immersivePhotoIndex = 0
                            }
                            selectedEventId = events[idx].id
                            focusOnImmersiveEvent(
                                idx: idx,
                                duration: 0.22,
                                useSmoothTransition: false
                            )
                        }
                        let centered = x - totalWidth * 0.5
                        scrubPreviewOffsetX = max(-120, min(120, centered))
                    }
                    .onEnded { _ in
                        guard isProgressScrubbing else { return }
                        let target = scrubPreviewEventIndex ?? immersiveEventIndex
                        isProgressScrubbing = false
                        scrubPreviewOffsetX = 0
                        jumpToImmersiveEvent(idx: target)
                    }
            )
    }

    private func focusOnImmersiveEvent(
        idx: Int,
        duration: Double = 0.45,
        useSmoothTransition: Bool = true
    ) {
        guard idx >= 0, idx < events.count,
              let coord = events[idx].coordinate else { return }
        let span = finalSpanDelta * 1.50
        let liftFactor = 0.45
        let targetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: coord.latitude + span * liftFactor,
                longitude: coord.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        let routeTarget = curveTargetIndex(for: events[idx].id)

        guard useSmoothTransition else {
            withAnimation(.easeInOut(duration: duration)) {
                setCameraRegion(targetRegion)
                if let routeTarget {
                    passedCurveEnd = routeTarget
                }
            }
            return
        }

        let fromRegion = runtimeStore.displayedRegion ?? targetRegion
        let dist = distanceMeters(from: fromRegion.center, to: coord)
        previousSelectedCoord = coord
        startCameraTransition(
            from: fromRegion,
            to: targetRegion,
            distance: dist,
            routeTargetCurveEnd: routeTarget
        )
    }

    private func enterImmersiveMode() {
        if let selId = selectedEvent?.id,
           let idx = events.firstIndex(where: { $0.id == selId }) {
            immersiveEventIndex = idx
        } else {
            immersiveEventIndex = 0
        }
        immersivePhotoIndex = 0

        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            isImmersive = true
        }
        focusOnImmersiveEvent(idx: immersiveEventIndex)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func exitImmersiveMode() {
        let targetId = events.indices.contains(immersiveEventIndex)
            ? events[immersiveEventIndex].id
            : selectedEventId
        isProgressScrubbing = false
        scrubPreviewEventIndex = nil
        scrubPreviewOffsetX = 0
        suppressRailFeedbackUntil = Date().addingTimeInterval(0.60)
        if let targetId {
            selectedEventId = targetId
        }
        // ★ 关键：先把 railFocusedEventId 清 nil，这样 ScrollView 重建后
        //   再赋值才能被 SwiftUI 识别为"变化"，触发真正的滚动居中。
        //   如果不清 nil，相同 UUID 赋值是 no-op，ScrollView 不会滚动。
        railFocusedEventId = nil
        syncingRailSelection = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isImmersive = false
        }
        // ScrollView 出现后立即设置正确位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            railFocusedEventId = targetId
        }
        // 转场动画结束后再做一次带动画的校正确保居中
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.85)) {
                railFocusedEventId = targetId
            }
            syncingRailSelection = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusOnSelectedEvent(animated: true)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private func floatingControlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    private func setupInitialCamera() {
        if selectedEventId == nil {
            selectedEventId = events.first?.id
        }
        railFocusedEventId = selectedEventId
        lastHapticEventId = selectedEventId
        previousSelectedCoord = selectedEvent?.coordinate
        // 初始化 passed 路线位置（无动画）
        if let idx = selectedRouteIndex {
            passedCurveEnd = curveIndex(forRoutePoint: idx)
        }
        focusOnSelectedEvent(animated: false)
    }

    // MARK: - 路线动画

    private func curveTargetIndex(for eventId: UUID?) -> Int? {
        guard let eventId,
              let idx = routePoints.firstIndex(where: { $0.id == eventId }) else { return nil }
        return curveIndex(forRoutePoint: idx)
    }

    /// 根据动态抬升系数把选中点推到"上方观察区"
    private func finalRegion(for coord: CLLocationCoordinate2D, liftFactor: Double) -> MKCoordinateRegion {
        let verticalOffset = finalSpanDelta * liftFactor
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coord.latitude + verticalOffset, longitude: coord.longitude),
            span: MKCoordinateSpan(latitudeDelta: finalSpanDelta, longitudeDelta: finalSpanDelta)
        )
    }

    private func focusOnSelectedEvent(animated: Bool) {
        if let selectedEvent,
           let coord = selectedEvent.coordinate {
            let routeTarget = curveTargetIndex(for: selectedEvent.id)

            // ——— 无动画（首次加载）：直接跳到最终放大 ———
            guard animated else {
                stopCameraAnimation()
                setCameraRegion(finalRegion(for: coord, liftFactor: overviewLiftFactor))
                if let routeTarget {
                    passedCurveEnd = routeTarget
                }
                previousSelectedCoord = coord
                return
            }

            // ——— 有动画：统一走单时间轴过渡（远距离自动中段拉远）———
            let targetRegion = finalRegion(for: coord, liftFactor: overviewLiftFactor)
            let fromRegion = runtimeStore.displayedRegion ?? finalRegion(for: previousSelectedCoord ?? coord, liftFactor: overviewLiftFactor)
            let dist = distanceMeters(from: fromRegion.center, to: coord)
            previousSelectedCoord = coord
            startCameraTransition(
                from: fromRegion,
                to: targetRegion,
                distance: dist,
                routeTargetCurveEnd: routeTarget
            )
            return
        }

        // fallback：无选中 event → fit all
        let coords = events.compactMap(\.coordinate)
        guard !coords.isEmpty else { return }
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLng = coords.map(\.longitude).min() ?? 0
        let maxLng = coords.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.7, 0.05),
                longitudeDelta: max((maxLng - minLng) * 1.7, 0.05)
            )
        )
        setCameraRegion(region)
    }

    private func setCameraRegion(_ region: MKCoordinateRegion) {
        if let previous = runtimeStore.displayedRegion {
            let centerThreshold = 0.00000045
            let spanThreshold = 0.00000085
            let centerDiffLat = abs(previous.center.latitude - region.center.latitude)
            let centerDiffLng = abs(previous.center.longitude - region.center.longitude)
            let spanDiffLat = abs(previous.span.latitudeDelta - region.span.latitudeDelta)
            let spanDiffLng = abs(previous.span.longitudeDelta - region.span.longitudeDelta)
            if centerDiffLat < centerThreshold,
               centerDiffLng < centerThreshold,
               spanDiffLat < spanThreshold,
               spanDiffLng < spanThreshold {
                return
            }
        }
        runtimeStore.displayedRegion = region
        cameraPosition = .region(region)
    }

    private func stopCameraAnimation() {
        cameraAnimTimer?.invalidate()
        cameraAnimTimer = nil
        isCameraAnimating = false
    }

    /// 单时间轴过渡：center 连续平移，span 中段平滑抬高后回落。
    /// 路线 passed 进度与相机共用同一时钟，彻底避免双定时器竞争。
    private func startCameraTransition(
        from: MKCoordinateRegion,
        to: MKCoordinateRegion,
        distance: CLLocationDistance,
        routeTargetCurveEnd: Int?
    ) {
        stopCameraAnimation()

        let farTransition = distance > nearThresholdMeters
        isCameraAnimating = true

        let duration = transitionDuration(for: distance, farTransition: farTransition)
        let fps: Double = farTransition ? 30 : 32
        let startTime = CACurrentMediaTime()
        let fromCenter = from.center
        let toCenter = to.center
        let fromSpan = max(from.span.latitudeDelta, finalSpanDelta)
        let toSpan = max(to.span.latitudeDelta, finalSpanDelta)
        let peakSpan = cameraPeakSpan(fromSpan: fromSpan, toSpan: toSpan, distance: distance, farTransition: farTransition)
        let routeFrom = Double(passedCurveEnd)
        let routeTo = Double(routeTargetCurveEnd ?? passedCurveEnd)
        let shouldAnimateRoute = routeTargetCurveEnd != nil

        let timer = Timer(timeInterval: 1.0 / fps, repeats: true) { timer in
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(max(elapsed / duration, 0), 1)
            let eased = t * t * t * (t * (t * 6 - 15) + 10) // smootherstep

            let lat = fromCenter.latitude + (toCenter.latitude - fromCenter.latitude) * eased
            let lng = fromCenter.longitude + (toCenter.longitude - fromCenter.longitude) * eased

            // 中段抬高：0->1->0，远距离时幅度更大，近距离几乎无感
            let arch = sin(Double.pi * t)
            let bump = pow(max(arch, 0), farTransition ? 1.0 : 1.8)
            let span = toSpan + (peakSpan - toSpan) * bump

            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            setCameraRegion(region)
            if shouldAnimateRoute {
                let routeIndex = Int(round(routeFrom + (routeTo - routeFrom) * eased))
                if routeIndex != passedCurveEnd {
                    passedCurveEnd = routeIndex
                }
            }

            if t >= 1.0 {
                setCameraRegion(to)
                if let routeTargetCurveEnd {
                    passedCurveEnd = routeTargetCurveEnd
                }
                timer.invalidate()
                cameraAnimTimer = nil
                isCameraAnimating = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cameraAnimTimer = timer
    }

    private func transitionDuration(for distance: CLLocationDistance, farTransition: Bool) -> Double {
        if !farTransition {
            return min(max(0.54 + distance / 12_000.0, 0.54), 0.74)
        }
        return min(max(0.82 + distance / 22_000.0, 0.82), 1.35)
    }

    private func cameraPeakSpan(fromSpan: Double, toSpan: Double, distance: CLLocationDistance, farTransition: Bool) -> Double {
        if !farTransition {
            return max(fromSpan, toSpan) * 1.03
        }
        let distBased = zoomOutSpanForDistance(distance)
        // 保底有抬升，但避免突然拉太远
        return min(max(distBased, max(fromSpan, toSpan) * 1.20), 0.22)
    }

    /// 根据两点距离计算 zoom-out 需要的 spanDelta
    private func zoomOutSpanForDistance(_ meters: CLLocationDistance) -> Double {
        let degreeSpan = meters / 111_000.0
        // 远距离需要看到路径，但避免过度拉远导致选中卡片看起来变小
        return max(degreeSpan * 1.08, finalSpanDelta * 1.15)
    }

    private func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }

    /// 生成平滑弧线：每段使用二次贝塞尔曲线插值多个点
    private func curvedCoordinates(from points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard points.count > 1 else { return points }
        var output: [CLLocationCoordinate2D] = []

        for index in 0..<(points.count - 1) {
            let p0 = points[index]
            let p2 = points[index + 1]

            let dx = p2.longitude - p0.longitude
            let dy = p2.latitude - p0.latitude
            let segmentLength = sqrt(dx * dx + dy * dy)

            guard segmentLength > 1e-8 else {
                if index == 0 { output.append(p0) }
                output.append(p2)
                continue
            }

            // 法线方向
            let nx = -dy / segmentLength
            let ny = dx / segmentLength
            // 交替弯曲方向（左右交替更好看）
            let direction: Double = (index % 2 == 0) ? 1 : -1
            // 弧度因子：距离越远弧度越大，但有上限
            let curveFactor = min(max(segmentLength * 0.20, 0.0006), 0.008)

            // 贝塞尔控制点（偏移中点的法线方向）
            let controlLat = (p0.latitude + p2.latitude) * 0.5 + ny * curveFactor * direction
            let controlLng = (p0.longitude + p2.longitude) * 0.5 + nx * curveFactor * direction

            // 用 12 个插值点绘制平滑曲线
            let steps = 12
            for step in (index == 0 ? 0 : 1)...steps {
                let t = Double(step) / Double(steps)
                let mt = 1 - t
                let lat = mt * mt * p0.latitude + 2 * mt * t * controlLat + t * t * p2.latitude
                let lng = mt * mt * p0.longitude + 2 * mt * t * controlLng + t * t * p2.longitude
                output.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }
        return output
    }

    /// 判断 event 坐标是否和选中点过近（会在视觉上重叠）
    private func isOverlappingSelected(_ event: StoryOverviewEvent, selectedCoord: CLLocationCoordinate2D?) -> Bool {
        guard let selectedCoord, let eventCoord = event.coordinate else { return false }
        // 保护选中卡片上方区域：非选中点不能压在选中卡片/标题上方
        let latDiff = eventCoord.latitude - selectedCoord.latitude
        let lngDiff = abs(eventCoord.longitude - selectedCoord.longitude)
        let sideThreshold = max(finalSpanDelta * 0.42, 0.0022)
        let aboveMin = -finalSpanDelta * 0.03
        let aboveMax = finalSpanDelta * 0.76
        let inCardColumn = lngDiff < sideThreshold && latDiff > aboveMin && latDiff < aboveMax
        let inCenterCore = abs(latDiff) < max(finalSpanDelta * 0.28, 0.0019) && lngDiff < max(finalSpanDelta * 0.28, 0.0019)
        return inCardColumn || inCenterCore
    }

    /// 判断 event 是否紧邻当前选中
    private func isNeighborOfSelected(_ event: StoryOverviewEvent) -> Bool {
        guard let selectedEvent,
              let selIdx = events.firstIndex(where: { $0.id == selectedEvent.id }),
              let evtIdx = events.firstIndex(where: { $0.id == event.id }) else { return false }
        return abs(selIdx - evtIdx) <= 1
    }

    private func displayCoordinate(for event: StoryOverviewEvent, highlighted: Bool) -> CLLocationCoordinate2D? {
        guard let base = event.coordinate else { return nil }
        if highlighted { return base }
        return nonHighlightedDisplayCoordinates[event.id] ?? base
    }
}

// MARK: - 沉浸式照片滚轴

private struct ImmersivePhotoCarousel: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    var onTargetIndex: (Int) -> Void

    @State private var snappedIndex: Int? = nil

    private var photosSignature: String {
        photos.map(\.assetLocalId).joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geo in
            let itemWidth: CGFloat = max(geo.size.width * 0.80, 1)
            let itemHeight: CGFloat = geo.size.height * 0.985
            let horizontalInset = max(0, (geo.size.width - itemWidth) * 0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                if photos.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("暂无照片")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                } else {
                    LazyHStack(spacing: 12) {
                        ForEach(photos.indices, id: \.self) { idx in
                            ImmersivePhotoTile(
                                localIdentifier: photos[idx].assetLocalId,
                                width: itemWidth,
                                height: itemHeight,
                                dimAmount: 0
                            )
                            .frame(width: itemWidth, height: itemHeight)
                            .id(idx)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.93)
                                    .opacity(phase.isIdentity ? 1 : 0.34)
                            }
                            .onTapGesture { }
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, horizontalInset)
            .scrollPosition(id: $snappedIndex, anchor: .center)
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        guard !photos.isEmpty else { return }
                        if currentIndex == 0, dx > 54 {
                            onTargetIndex(-1)
                        } else if currentIndex == photos.count - 1, dx < -54 {
                            onTargetIndex(photos.count)
                        }
                    }
            )
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            let clamped = photos.isEmpty ? 0 : min(max(currentIndex, 0), photos.count - 1)
            snappedIndex = photos.isEmpty ? nil : clamped
            if currentIndex != clamped { currentIndex = clamped }
        }
        .onChange(of: snappedIndex) { _, newValue in
            guard let newValue else { return }
            let clamped = photos.isEmpty ? 0 : min(max(newValue, 0), photos.count - 1)
            if currentIndex != clamped {
                currentIndex = clamped
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            guard !photos.isEmpty else {
                snappedIndex = nil
                return
            }
            let clamped = min(max(newValue, 0), photos.count - 1)
            if snappedIndex != clamped {
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                    snappedIndex = clamped
                }
            }
        }
        .onChange(of: photosSignature) { _, _ in
            if !photos.isEmpty {
                let clamped = min(max(currentIndex, 0), photos.count - 1)
                if clamped != currentIndex { currentIndex = clamped }
                snappedIndex = clamped
            } else if currentIndex != 0 {
                currentIndex = 0
                snappedIndex = nil
            }
        }
    }
}

private struct ImmersivePhotoTile: View {
    let localIdentifier: String
    let width: CGFloat
    let height: CGFloat
    let dimAmount: CGFloat

    var body: some View {
        ZStack {
            AssetImageView(
                localIdentifier: localIdentifier,
                size: CGSize(width: width, height: height)
            )
            .id(localIdentifier)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if dimAmount > 0.001 {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(max(0, min(0.45, dimAmount))))
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct StoryListTypeDot: View {
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

private struct OverviewEventRailCard: View {
    let event: StoryOverviewEvent
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 封面图区域
            ZStack(alignment: .bottomTrailing) {
                if let coverId = event.photos.first?.assetLocalId {
                    AssetImageView(localIdentifier: coverId, size: CGSize(width: 200, height: 200))
                        .frame(width: highlighted ? 68 : 54, height: highlighted ? 68 : 54)
                        .clipShape(RoundedRectangle(cornerRadius: highlighted ? 14 : 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: highlighted ? 14 : 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.82, green: 0.72, blue: 0.60).opacity(0.6), Color(red: 0.72, green: 0.60, blue: 0.48).opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: highlighted ? 68 : 54, height: highlighted ? 68 : 54)
                }
                // 照片数量角标
                if event.photos.count > 1 {
                    Text("\(event.photos.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(4)
                }
            }

            // 标题
            Text(event.title)
                .font(.system(size: highlighted ? 11 : 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(width: 92)
                .padding(.top, 6)

            // 日期（选中态才显示）
            if highlighted {
                Text(event.day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(red: 0.50, green: 0.42, blue: 0.33))
                    .padding(.top, 1)
            }
        }
        .foregroundStyle(highlighted ? Color(red: 0.22, green: 0.17, blue: 0.12) : .primary.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, highlighted ? 11 : 9)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlighted ? .ultraThinMaterial : .regularMaterial)
                .shadow(
                    color: highlighted
                        ? Color(red: 0.55, green: 0.44, blue: 0.33).opacity(0.10)
                        : Color.black.opacity(0.03),
                    radius: highlighted ? 3 : 1,
                    y: highlighted ? 1 : 0
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(highlighted ? 0.16 : 0.07), lineWidth: 0.35)
        )
        .scaleEffect(highlighted ? 1.03 : 0.90)
        .opacity(highlighted ? 1 : 0.65)
        .zIndex(highlighted ? 3 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: highlighted)
    }
}

/// 非选中 annotation：仅小圆点，极小化避免遮挡
private struct OverviewEventPinDot: View {
    let isNeighborOfSelected: Bool

    var body: some View {
        Circle()
            .fill(Color(red: 0.70, green: 0.60, blue: 0.48).opacity(isNeighborOfSelected ? 0.85 : 0.75))
            .frame(width: isNeighborOfSelected ? 11 : 10, height: isNeighborOfSelected ? 11 : 10)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
            .allowsHitTesting(true)
    }
}

/// 转场中的选中点：纯轻量渲染，避免拖着大卡片移动导致掉帧
private struct OverviewEventMovingPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 13, height: 13)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 13, height: 13)
        }
        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
    }
}

/// 沉浸模式下的地图锚点：标题在点上方，点在下方
private struct ImmersiveEventMapAnchor: View {
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.17, blue: 0.12))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )

            ZStack {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 12, height: 12)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 12, height: 12)
            }
            .shadow(color: .black.opacity(0.26), radius: 3, y: 1)
        }
    }
}

/// 选中的 annotation：高品质卡片（带图片 + 标题 + 箭头 + 定位点）
private struct OverviewEventPinCallout: View {
    let event: StoryOverviewEvent
    let highlighted: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.5)) { timeline in
            let photos = event.photos
            let count = photos.count
            let index = count > 1
                ? Int(timeline.date.timeIntervalSinceReferenceDate / 1.5).quotientAndRemainder(dividingBy: count).remainder
                : 0
            let coverId = (count > 0 && index >= 0 && index < count) ? photos[index].assetLocalId : photos.first?.assetLocalId

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if let coverId {
                        AssetImageView(localIdentifier: coverId, size: CGSize(width: 460, height: 300))
                            .frame(width: 154, height: 102)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 12,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 12
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.82, green: 0.72, blue: 0.60), Color(red: 0.72, green: 0.60, blue: 0.48)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 154, height: 102)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 12,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 12
                                )
                            )
                    }

                    HStack(spacing: 4) {
                        Text(event.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.22, green: 0.17, blue: 0.12))
                            .lineLimit(1)

                        if event.photos.count > 1 {
                            Text("·\(event.photos.count)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.50, green: 0.42, blue: 0.33))
                        }
                    }
                            .frame(width: 146)
                    .padding(.vertical, 7)
                }
                .frame(width: 154)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color(red: 0.55, green: 0.44, blue: 0.33).opacity(0.35), radius: 12, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.6), Color(red: 0.82, green: 0.72, blue: 0.60).opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.85, green: 0.77, blue: 0.67).opacity(0.9))
                    .offset(y: -2)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)

                ZStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 10, height: 10)
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 10, height: 10)
                }
                .offset(y: -3)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .transition(.scale(scale: 0.7).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: highlighted)
        }
    }
}

/// 事件卡片：时间、地点胶囊、1–3 张缩略图、一句话备注
struct EventCardView: View {
    let date: Date
    let title: String
    let photos: [Photo]
    let note: String?
    var onPhotoTap: ((Photo) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.prefix(5), id: \.id) { photo in
                            Button {
                                onPhotoTap?(photo)
                            } label: {
                                PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                                    .frame(width: 72, height: 72)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let note = note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 聚合点详情视图
struct ClusterDetailView: View {
    let cluster: MapClusteringService.Cluster
    var highlightedPhotoId: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<UUID> = []
    @State private var highlightedId: UUID?
    @State private var selectedPhoto: Photo?
    
    private var sortedPhotos: [Photo] {
        cluster.photos.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                if let hId = highlightedPhotoId,
                   let photo = sortedPhotos.first(where: { $0.id == hId }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("已定位到选中照片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                }

                Text("\(cluster.photoCount) 张照片")
                    .font(.headline)
                    .padding(.horizontal, 8)

                PhotoGridByDateView(
                    photos: sortedPhotos,
                    isSelectionMode: false,
                    selectedIds: $selectedIds,
                    highlightedPhotoId: highlightedId,
                    onPhotoTap: { photo in
                        selectedPhoto = photo
                    }
                )
            }
            .onAppear {
                highlightedId = highlightedPhotoId
            }
            .navigationTitle(cluster.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photos: sortedPhotos, initialPhoto: photo)
            }
        }
    }
}

/// 无位置照片补充 Sheet：可点击照片编辑地址，地图对准 Story 范围，推荐按拍照时间接近的地点
struct NoLocationPhotosSheet: View {
    @Bindable var collection: Collection
    var onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var editingPhoto: Photo?
    
    private var storyPhotos: [Photo] {
        collection.photos.filter { $0.deletedAt == nil }.sorted { $0.timestamp < $1.timestamp }
    }
    
    private var photosWithoutLocation: [Photo] {
        storyPhotos.filter { $0.coordinate == nil }
    }
    
    /// 本 Story 内所有出现过的地点名（含反地理编码缓存，用于推荐）
    private var storyLocationNames: [String] {
        let names = storyPhotos
            .filter { $0.coordinate != nil || ($0.manualLocationName ?? "").isEmpty == false }
            .map { $0.displayLocationName }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }
    
    /// Story 有位置照片的边界区域（用于地图初始视野）
    private var storyBoundsRegion: MKCoordinateRegion? {
        let withLoc = storyPhotos.compactMap { $0.coordinate }
        guard !withLoc.isEmpty else { return nil }
        let lats = withLoc.map(\.latitude)
        let lngs = withLoc.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let pad = 0.01
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat + pad, 0.02),
            longitudeDelta: max(maxLng - minLng + pad, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
    
    /// 同 Story 内有地址的照片，按与当前照片拍照时间接近排序，用于推荐地点
    private func recommendedLocationNames(for photo: Photo) -> [String] {
        let withLocation = storyPhotos.filter { !$0.displayLocationName.isEmpty }
        if withLocation.isEmpty { return [] }
        return withLocation
            .sorted { abs($0.timestamp.timeIntervalSince(photo.timestamp)) < abs($1.timestamp.timeIntervalSince(photo.timestamp)) }
            .map(\.displayLocationName)
            .uniqued()
    }
    
    /// 推荐地点（带坐标），按时间接近排序
    private func recommendedLocationsForPhoto(_ photo: Photo) -> [(name: String, coordinate: CLLocationCoordinate2D)] {
        let withLocation = storyPhotos.filter { $0.coordinate != nil && !$0.displayLocationName.isEmpty }
        guard !withLocation.isEmpty else { return [] }
        var seen = Set<String>()
        return withLocation
            .sorted { abs($0.timestamp.timeIntervalSince(photo.timestamp)) < abs($1.timestamp.timeIntervalSince(photo.timestamp)) }
            .compactMap { p -> (name: String, coordinate: CLLocationCoordinate2D)? in
                let name = p.displayLocationName
                guard !seen.contains(name), let coord = p.coordinate else { return nil }
                seen.insert(name)
                return (name: name, coordinate: coord)
            }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("以下照片没有位置信息，无法在地图上显示。点击某张照片可进入编辑添加地址，或使用快捷选择本 Story 内已有地点。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("无位置照片（\(photosWithoutLocation.count) 张）") {
                    ForEach(photosWithoutLocation, id: \.id) { photo in
                        Button {
                            editingPhoto = photo
                        } label: {
                            HStack(spacing: 12) {
                                PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                    
                                    if storyLocationNames.isEmpty {
                                        Text("点击添加地址")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Menu {
                                            Text("推荐（按拍照时间接近）")
                                                .font(.caption2)
                                            ForEach(recommendedLocationNames(for: photo), id: \.self) { name in
                                                Button(name) {
                                                    applyStoryLocation(to: photo, name: name)
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(photo.displayLocationName.isEmpty ? "选推荐地点" : photo.displayLocationName)
                                                    .font(.caption)
                                                    .foregroundStyle(photo.coordinate != nil ? .primary : .secondary)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                    }
                }
            }
            .navigationTitle("补充地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        try? modelContext.save()
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .sheet(item: $editingPhoto) { photo in
                PhotoEditView(
                    photo: photo,
                    initialMapRegion: storyBoundsRegion,
                    recommendedLocations: recommendedLocationsForPhoto(photo)
                )
            }
        }
    }
    
    private func applyStoryLocation(to photo: Photo, name: String) {
        let refPhoto = storyPhotos.first(where: { $0.displayLocationName == name && $0.coordinate != nil })
            ?? storyPhotos.first(where: { $0.displayLocationName == name })
        if let ref = refPhoto, let coord = ref.coordinate {
            photo.latitude = coord.latitude
            photo.longitude = coord.longitude
        }
        photo.manualLocationName = name
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#Preview {
    StoryDetailView(collection: Collection(
        title: "示例 Story",
        type: .story,
        startTime: Date(),
        endTime: Date()
    ))
}
