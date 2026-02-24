//
//  JourneyMemoryView.swift
//  MemoriesApp
//
//  Unified Memory Mode: full-screen map background + foreground photo journey.
//

import SwiftUI
import MapKit
import UIKit

struct JourneyMemoryView: View {
    let collection: Collection
    var initialDayDate: Date? = nil
    var initialEventId: UUID? = nil

    @State private var currentDayIndex = 0
    @State private var currentEventIndex = 0
    @State private var currentPhotoIndex = 0
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var pulseToken = 0
    @State private var didSetInitialPosition = false
    @State private var suppressNextPhotoFocus = false
    @State private var lastFocusedCoordinate: CLLocationCoordinate2D?
    @State private var infoBarTransitionToken = 0
    /// A→B 短暂连线闪一下（0.3–0.5s 后淡出）
    @State private var transitionLine: (from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)?
    /// 镜头转场中：不画路径线，只用镜头表达移动，避免「点/标志沿路径动」的观感
    @State private var isMapTransitioning = false

    private var journeyStructure: [DayData] {
        let photos = collection.photos
            .filter { $0.deletedAt == nil }
            .sorted { $0.timestamp < $1.timestamp }
        guard !photos.isEmpty else { return [] }

        let calendar = Calendar.current
        var grouped: [Date: [EventData]] = [:]

        if !collection.events.isEmpty {
            let sortedEvents = collection.events.sorted { $0.startTime < $1.startTime }
            for event in sortedEvents {
                let eventPhotos = photos
                    .filter { $0.eventId == event.id }
                    .sorted { $0.timestamp < $1.timestamp }
                guard !eventPhotos.isEmpty else { continue }

                let day = calendar.startOfDay(for: event.startTime)
                let cleanTitle = event.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (cleanTitle?.isEmpty == false)
                    ? cleanTitle!
                    : (eventPhotos.first?.displayLocationName.isEmpty == false
                       ? (eventPhotos.first?.displayLocationName ?? "")
                       : "这段回忆")

                grouped[day, default: []].append(
                    EventData(
                        id: event.id,
                        title: title,
                        note: event.note,
                        coordinate: eventPhotos.first?.coordinate,
                        startTime: event.startTime,
                        photos: eventPhotos
                    )
                )
            }
        }

        if grouped.isEmpty {
            var fallback: [Date: [Photo]] = [:]
            for photo in photos {
                let day = calendar.startOfDay(for: photo.timestamp)
                fallback[day, default: []].append(photo)
            }

            for (day, dayPhotos) in fallback {
                let sorted = dayPhotos.sorted { $0.timestamp < $1.timestamp }
                let title = sorted.first?.displayLocationName.isEmpty == false
                    ? (sorted.first?.displayLocationName ?? "")
                    : "这段回忆"

                grouped[day, default: []].append(
                    EventData(
                        id: UUID(),
                        title: title,
                        note: sorted.first?.note,
                        coordinate: sorted.first?.coordinate,
                        startTime: sorted.first?.timestamp ?? day,
                        photos: sorted
                    )
                )
            }
        }

        return grouped.keys.sorted().enumerated().map { idx, day in
            let events = (grouped[day] ?? []).sorted { $0.startTime < $1.startTime }
            return DayData(index: idx, date: day, events: events)
        }
    }

    private var currentDayEvents: [EventData] {
        guard currentDayIndex >= 0, currentDayIndex < journeyStructure.count else { return [] }
        return journeyStructure[currentDayIndex].events
    }

    private var currentEvent: EventData? {
        guard currentEventIndex >= 0, currentEventIndex < currentDayEvents.count else { return nil }
        return currentDayEvents[currentEventIndex]
    }

    private var currentPhoto: Photo? {
        guard let event = currentEvent, !event.photos.isEmpty else { return nil }
        let safe = min(max(currentPhotoIndex, 0), event.photos.count - 1)
        return event.photos[safe]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                JourneyMapBackground(
                    events: currentDayEvents,
                    currentEventIndex: currentEventIndex,
                    pulseToken: pulseToken,
                    cameraPosition: $mapCameraPosition,
                    transitionLine: transitionLine,
                    isMapTransitioning: isMapTransitioning
                )
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    StoryTitleBar(
                        title: collection.title,
                        subtitle: currentDayLabel
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    JourneyInfoBar(
                        event: currentEvent,
                        photoIndex: currentPhotoIndex,
                        transitionToken: infoBarTransitionToken
                    )
                    .padding(.horizontal, 14)

                    Spacer()
                }

                VStack(spacing: 10) {
                    Spacer(minLength: max(geo.size.height * 0.015, 8))

                    MemoryPhotoCard(
                        event: currentEvent,
                        currentPhotoIndex: $currentPhotoIndex,
                        onTargetIndex: handlePhotoTargetIndex
                    )
                    .frame(maxWidth: geo.size.width * 0.9)
                    .frame(height: min(geo.size.height * 0.52, 460))

                    Spacer(minLength: max(geo.size.height * 0.31, 220))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                VStack(spacing: 0) {
                    Spacer()
                    DayProgressStrip(
                        dayCount: journeyStructure.count,
                        currentDayIndex: currentDayIndex,
                        onSelect: { idx in
                            select(dayIndex: idx, eventIndex: 0, photoIndex: 0, animated: true)
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > 52, abs(horizontal) > abs(vertical) * 1.3 else { return }
                        let edgeStartThreshold: CGFloat = 24
                        let startedRightEdge = value.startLocation.x >= geo.size.width - edgeStartThreshold
                        let startedLeftEdge = value.startLocation.x <= edgeStartThreshold

                        if startedRightEdge && horizontal < 0 && currentDayIndex < journeyStructure.count - 1 {
                            select(dayIndex: currentDayIndex + 1, eventIndex: 0, photoIndex: 0, animated: true)
                        } else if startedLeftEdge && horizontal > 0 && currentDayIndex > 0 {
                            select(dayIndex: currentDayIndex - 1, eventIndex: 0, photoIndex: 0, animated: true)
                        }
                    }
            )
        }
        .onAppear {
            setInitialPositionIfNeeded()
        }
        .onChange(of: journeyStructure.count) { _, _ in
            setInitialPositionIfNeeded()
        }
        .onChange(of: currentPhotoIndex) { _, _ in
            if suppressNextPhotoFocus {
                suppressNextPhotoFocus = false
                return
            }
            focusMapToCurrentPhoto(animated: false)
        }
    }

    private var currentDayLabel: String {
        guard currentDayIndex >= 0, currentDayIndex < journeyStructure.count else { return "" }
        return journeyStructure[currentDayIndex].date.formatted(date: .abbreviated, time: .omitted)
    }

    private func setInitialPositionIfNeeded() {
        guard !didSetInitialPosition, !journeyStructure.isEmpty else { return }
        let target = initialTargetPosition()
        didSetInitialPosition = true
        select(dayIndex: target.day, eventIndex: target.event, photoIndex: 0, animated: false)
    }

    private func initialDayIndex(from date: Date?) -> Int? {
        guard let date else { return nil }
        let target = Calendar.current.startOfDay(for: date)
        return journeyStructure.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: target) }
    }

    private func initialTargetPosition() -> (day: Int, event: Int) {
        if let initialEventId {
            for (dayIndex, day) in journeyStructure.enumerated() {
                if let eventIndex = day.events.firstIndex(where: { $0.id == initialEventId }) {
                    return (dayIndex, eventIndex)
                }
            }
        }
        return (initialDayIndex(from: initialDayDate) ?? 0, 0)
    }

    private func handlePhotoTargetIndex(_ rawTargetIndex: Int) {
        guard !journeyStructure.isEmpty else { return }

        var day = currentDayIndex
        var event = currentEventIndex
        var photo = rawTargetIndex
        var loopGuard = 0

        while loopGuard < 128 {
            loopGuard += 1
            guard day >= 0, day < journeyStructure.count else { break }
            let events = journeyStructure[day].events
            guard !events.isEmpty, event >= 0, event < events.count else { break }

            let photoCount = max(events[event].photos.count, 1)

            if photo < 0 {
                if event > 0 {
                    event -= 1
                    photo += max(events[event].photos.count, 1)
                    continue
                }
                if day > 0 {
                    day -= 1
                    let previousEvents = journeyStructure[day].events
                    event = max(previousEvents.count - 1, 0)
                    photo += max(previousEvents[event].photos.count, 1)
                    continue
                }
                photo = 0
                break
            }

            if photo >= photoCount {
                let overflow = photo - photoCount
                if event < events.count - 1 {
                    event += 1
                    photo = overflow
                    continue
                }
                if day < journeyStructure.count - 1 {
                    day += 1
                    event = 0
                    photo = overflow
                    continue
                }
                photo = photoCount - 1
                break
            }

            break
        }

        select(dayIndex: day, eventIndex: event, photoIndex: photo, animated: true)
    }

    private func select(dayIndex: Int, eventIndex: Int, photoIndex: Int, animated: Bool) {
        guard dayIndex >= 0, dayIndex < journeyStructure.count else { return }
        let events = journeyStructure[dayIndex].events
        guard !events.isEmpty else { return }

        let safeEvent = min(max(eventIndex, 0), events.count - 1)
        let photos = events[safeEvent].photos
        guard !photos.isEmpty else { return }

        let safePhoto = min(max(photoIndex, 0), photos.count - 1)
        let eventChanged = (currentDayIndex != dayIndex) || (currentEventIndex != safeEvent)
        let fromCoord: CLLocationCoordinate2D? = eventChanged ? currentDayEvents[currentEventIndex].coordinate : nil
        let toCoord: CLLocationCoordinate2D? = events[safeEvent].coordinate

        suppressNextPhotoFocus = true
        currentDayIndex = dayIndex
        currentEventIndex = safeEvent
        currentPhotoIndex = safePhoto

        if eventChanged {
            pulseToken += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            infoBarTransitionToken += 1
        }

        // ③ A→B 短暂连线闪一下（0.3–0.5s 后淡出）
        if eventChanged, let from = fromCoord, let to = toCoord {
            transitionLine = (from: from, to: to)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                transitionLine = nil
            }
        }

        let spanLatDeltaNormal: Double = 0.018

        if let center = toCoord {
            if eventChanged, let from = fromCoord, animated {
                let distanceDeg = hypot(center.latitude - from.latitude, center.longitude - from.longitude)
                let isNear = distanceDeg < 0.015

                isMapTransitioning = true

                if isNear {
                    // ① 近距离：仅镜头到 B，不画路径、不沿路径动
                    withAnimation(.easeOut(duration: 0.38)) {
                        mapCameraPosition = .region(
                            MKCoordinateRegion(
                                center: mapCenterForFloatingCard(center, spanLatDelta: spanLatDeltaNormal),
                                span: MKCoordinateSpan(latitudeDelta: spanLatDeltaNormal, longitudeDelta: spanLatDeltaNormal)
                            )
                        )
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                        isMapTransitioning = false
                    }
                } else {
                    // ② 远距离：只做「zoom out → 一次平滑到 B」，镜头表达移动，不拆成多段减少卡顿
                    let minLat = min(from.latitude, center.latitude)
                    let maxLat = max(from.latitude, center.latitude)
                    let minLng = min(from.longitude, center.longitude)
                    let maxLng = max(from.longitude, center.longitude)
                    let pad = 0.01
                    let spanLat = max((maxLat - minLat) + pad * 2, 0.04)
                    let spanLng = max((maxLng - minLng) + pad * 2, 0.04)
                    let zoomOutCenter = CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLng + maxLng) / 2
                    )
                    let zoomOutRegion = MKCoordinateRegion(
                        center: zoomOutCenter,
                        span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLng)
                    )
                    let finalRegion = MKCoordinateRegion(
                        center: mapCenterForFloatingCard(center, spanLatDelta: spanLatDeltaNormal),
                        span: MKCoordinateSpan(latitudeDelta: spanLatDeltaNormal, longitudeDelta: spanLatDeltaNormal)
                    )

                    withAnimation(.easeOut(duration: 0.12)) {
                        mapCameraPosition = .region(zoomOutRegion)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        withAnimation(.easeInOut(duration: 0.52)) {
                            mapCameraPosition = .region(finalRegion)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
                            isMapTransitioning = false
                        }
                    }
                }
            } else if animated {
                withAnimation(.easeInOut(duration: 0.45)) {
                    mapCameraPosition = .region(
                        MKCoordinateRegion(
                            center: mapCenterForFloatingCard(center, spanLatDelta: spanLatDeltaNormal),
                            span: MKCoordinateSpan(latitudeDelta: spanLatDeltaNormal, longitudeDelta: spanLatDeltaNormal)
                        )
                    )
                }
            } else {
                mapCameraPosition = .region(
                    MKCoordinateRegion(
                        center: mapCenterForFloatingCard(center, spanLatDelta: spanLatDeltaNormal),
                        span: MKCoordinateSpan(latitudeDelta: spanLatDeltaNormal, longitudeDelta: spanLatDeltaNormal)
                    )
                )
            }
        } else {
            let coordinates = events.compactMap(\.coordinate)
            guard !coordinates.isEmpty else { return }
            let minLat = coordinates.map(\.latitude).min() ?? 0
            let maxLat = coordinates.map(\.latitude).max() ?? 0
            let minLng = coordinates.map(\.longitude).min() ?? 0
            let maxLng = coordinates.map(\.longitude).max() ?? 0
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            )
            let spanLatDelta = max((maxLat - minLat) * 1.35, 0.02)
            if animated {
                withAnimation(.easeInOut(duration: 0.45)) {
                    mapCameraPosition = .region(
                        MKCoordinateRegion(
                            center: mapCenterForFloatingCard(center, spanLatDelta: spanLatDelta),
                            span: MKCoordinateSpan(
                                latitudeDelta: spanLatDelta,
                                longitudeDelta: max((maxLng - minLng) * 1.35, 0.02)
                            )
                        )
                    )
                }
            } else {
                mapCameraPosition = .region(
                    MKCoordinateRegion(
                        center: mapCenterForFloatingCard(center, spanLatDelta: spanLatDelta),
                        span: MKCoordinateSpan(
                            latitudeDelta: spanLatDelta,
                            longitudeDelta: max((maxLng - minLng) * 1.35, 0.02)
                        )
                    )
                )
            }
        }
    }

    private func focusMapToCurrentPhoto(animated: Bool) {
        guard let coord = currentPhoto?.coordinate else { return }
        if let last = lastFocusedCoordinate,
           abs(last.latitude - coord.latitude) < 0.000_005,
           abs(last.longitude - coord.longitude) < 0.000_005 {
            return
        }
        let spanLatDelta = 0.014
        let update = {
            mapCameraPosition = .region(
                MKCoordinateRegion(
                    center: mapCenterForFloatingCard(coord, spanLatDelta: spanLatDelta),
                    span: MKCoordinateSpan(latitudeDelta: spanLatDelta, longitudeDelta: 0.014)
                )
            )
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                update()
            }
        } else {
            update()
        }
        lastFocusedCoordinate = coord
    }

    private func mapCenterForFloatingCard(_ coordinate: CLLocationCoordinate2D, spanLatDelta: Double) -> CLLocationCoordinate2D {
        // 把当前位置压到屏幕下半部分，给上方照片展示留空间
        CLLocationCoordinate2D(
            latitude: coordinate.latitude + spanLatDelta * 0.28,
            longitude: coordinate.longitude
        )
    }

}

private struct StoryTitleBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DayProgressStrip: View {
    let dayCount: Int
    let currentDayIndex: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(dayCount, 0), id: \.self) { idx in
                Button {
                    onSelect(idx)
                } label: {
                    Capsule()
                        .fill(idx <= currentDayIndex ? Color.white : Color.white.opacity(0.3))
                        .frame(height: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 8)
    }
}

struct DayData: Identifiable {
    let id = UUID()
    let index: Int
    let date: Date
    let events: [EventData]
}

struct EventData: Identifiable {
    let id: UUID
    let title: String
    let note: String?
    let coordinate: CLLocationCoordinate2D?
    let startTime: Date
    let photos: [Photo]
}

private struct DayPillStrip: View {
    let days: [DayData]
    let currentDayIndex: Int
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button {
                        onSelect(index)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Day \(index + 1)")
                                .font(.caption.weight(.semibold))
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                        }
                        .foregroundStyle(index == currentDayIndex ? .white : .white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            index == currentDayIndex
                            ? Color.accentColor.opacity(0.95)
                            : Color.black.opacity(0.32),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct JourneyMapBackground: View {
    let events: [EventData]
    let currentEventIndex: Int
    let pulseToken: Int
    @Binding var cameraPosition: MapCameraPosition
    var transitionLine: (from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)?
    var isMapTransitioning: Bool = false

    var body: some View {
        Map(position: $cameraPosition) {
            let coordinates = events.compactMap(\.coordinate)

            // ③ A→B 短暂连线闪一下（淡线 0.3–0.5s）
            if let line = transitionLine {
                MapPolyline(coordinates: [line.from, line.to])
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, dash: [4, 4]))
            }

            // 转场中不画路径线，只用镜头表达移动，避免位置点/events 标志「沿路径动」的观感
            if !isMapTransitioning, coordinates.count > 1 {
                let passed = Array(coordinates.prefix(min(currentEventIndex + 1, coordinates.count)))
                if passed.count > 1 {
                    MapPolyline(coordinates: passed)
                        .stroke(AppTheme.accent.opacity(0.78), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                }

                if currentEventIndex < coordinates.count - 1 {
                    let upcoming = Array(coordinates.suffix(coordinates.count - currentEventIndex))
                    if upcoming.count > 1 {
                        MapPolyline(coordinates: upcoming)
                            .stroke(AppTheme.accent.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    }
                }
            }

            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if let coord = event.coordinate {
                    Annotation("", coordinate: coord) {
                        JourneyEventMarker(
                            isCurrent: index == currentEventIndex,
                            isPast: index < currentEventIndex,
                            pulseToken: pulseToken
                        )
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .allowsHitTesting(false)
        .saturation(0.78)
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct JourneyEventMarker: View {
    let isCurrent: Bool
    let isPast: Bool
    let pulseToken: Int

    @State private var pulseScale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(isCurrent ? Color.accentColor : (isPast ? AppTheme.accent.opacity(0.6) : Color.gray.opacity(0.4)))
                .frame(width: isCurrent ? 18 : 11, height: isCurrent ? 18 : 11)
                .scaleEffect(pulseScale)
                .shadow(color: .black.opacity(0.25), radius: 4)

            if isCurrent {
                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 2.5)
                    .frame(width: 24, height: 24)
            }
        }
        .onAppear { triggerPulse() }
        .onChange(of: pulseToken) { _, _ in triggerPulse() }
    }

    private func triggerPulse() {
        guard isCurrent else { return }
        pulseScale = 0.92
        withAnimation(.easeOut(duration: 0.2)) {
            pulseScale = 1.2
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.76).delay(0.16)) {
            pulseScale = 1.0
        }
    }
}

private struct MemoryPhotoCard: View {
    let event: EventData?
    @Binding var currentPhotoIndex: Int
    var onTargetIndex: (Int) -> Void

    var body: some View {
        ZStack {
            JourneyPhotoCarousel(
                photos: event?.photos ?? [],
                currentIndex: $currentPhotoIndex,
                onTargetIndex: onTargetIndex
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
    }
}

private struct JourneyPhotoCarousel: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    var onTargetIndex: (Int) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var externalJumpCooldownUntil: Date = .distantPast

    private var photosSignature: String {
        photos.map(\.assetLocalId).joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geo in
            let centerWidth: CGFloat = max(geo.size.width * 0.74, 1)
            let sideOffset: CGFloat = centerWidth * 0.57
            let stepWidth: CGFloat = max(centerWidth * 0.38, 64)
            let safeIndex = min(max(currentIndex, 0), max(photos.count - 1, 0))
            let signedProgress: CGFloat = max(-1, min(1, dragOffset / stepWidth))
            let progress: CGFloat = abs(signedProgress)
            let movingToPrevious: CGFloat = max(.zero, signedProgress)
            let movingToNext: CGFloat = max(.zero, -signedProgress)
            let tileHeight: CGFloat = geo.size.height * 0.97
            let leftDim: CGFloat = 0.34 - movingToPrevious * 0.24 + movingToNext * 0.06
            let rightDim: CGFloat = 0.34 - movingToNext * 0.24 + movingToPrevious * 0.06
            let leftScale: CGFloat = 0.90 + movingToPrevious * 0.10 - movingToNext * 0.015
            let rightScale: CGFloat = 0.90 + movingToNext * 0.10 - movingToPrevious * 0.015
            let leftOpacity: Double = Double(0.24 + movingToPrevious * 0.68)
            let rightOpacity: Double = Double(0.24 + movingToNext * 0.68)
            let leftOffsetX: CGFloat = -sideOffset + movingToPrevious * sideOffset - movingToNext * sideOffset * 0.15
            let rightOffsetX: CGFloat = sideOffset - movingToNext * sideOffset + movingToPrevious * sideOffset * 0.15
            let centerScale: CGFloat = 1 - progress * 0.09
            let centerOpacity: Double = Double(1 - progress * 0.38)
            let centerDim: CGFloat = progress * 0.24
            let centerZ: Double = progress > 0.02 ? 1 : 2
            let leftZ: Double = movingToPrevious > 0.02 ? 3 : 1
            let rightZ: Double = movingToNext > 0.02 ? 3 : 1

            ZStack(alignment: .center) {
                if photos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.35))
                        Text("暂无照片")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    if safeIndex > 0 {
                        JourneyPhotoTile(
                            localIdentifier: photos[safeIndex - 1].assetLocalId,
                            width: centerWidth,
                            height: tileHeight,
                            dimAmount: max(0, min(0.45, leftDim))
                        )
                        .scaleEffect(leftScale)
                        .opacity(leftOpacity)
                        .offset(x: leftOffsetX)
                        .zIndex(leftZ)
                    } else {
                        Color.clear
                            .frame(width: centerWidth, height: tileHeight)
                            .offset(x: leftOffsetX)
                    }

                    if safeIndex < photos.count - 1 {
                        JourneyPhotoTile(
                            localIdentifier: photos[safeIndex + 1].assetLocalId,
                            width: centerWidth,
                            height: tileHeight,
                            dimAmount: max(0, min(0.45, rightDim))
                        )
                        .scaleEffect(rightScale)
                        .opacity(rightOpacity)
                        .offset(x: rightOffsetX)
                        .zIndex(rightZ)
                    } else {
                        Color.clear
                            .frame(width: centerWidth, height: tileHeight)
                            .offset(x: rightOffsetX)
                    }

                    JourneyPhotoTile(
                        localIdentifier: photos[safeIndex].assetLocalId,
                        width: centerWidth,
                        height: tileHeight,
                        dimAmount: centerDim
                    )
                    .offset(x: dragOffset)
                    .scaleEffect(centerScale)
                    .opacity(centerOpacity)
                    .zIndex(centerZ)
                }
            }
            .contentShape(Rectangle())
            .gesture(makeDragGesture(pageWidth: stepWidth, safeIndex: safeIndex))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onChange(of: photosSignature) { _, _ in
            withAnimation(.none) {
                dragOffset = 0
            }
            if !photos.isEmpty {
                let clamped = min(max(currentIndex, 0), photos.count - 1)
                if clamped != currentIndex {
                    currentIndex = clamped
                }
            } else if currentIndex != 0 {
                currentIndex = 0
            }
        }
        .onChange(of: currentIndex) { _, _ in
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.9)) {
                dragOffset = 0
            }
        }
    }

    private func makeDragGesture(pageWidth: CGFloat, safeIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                var adjusted = value.translation.width
                let hitLeft = safeIndex == 0 && adjusted > .zero
                let hitRight = safeIndex == photos.count - 1 && adjusted < .zero
                if hitLeft || hitRight {
                    adjusted *= 0.4
                }
                dragOffset = max(-pageWidth * 1.05, min(pageWidth * 1.05, adjusted))
            }
            .onEnded { value in
                let predictedExtra = value.predictedEndTranslation.width - value.translation.width
                let projected = dragOffset + predictedExtra * 0.18
                var deltaIndex = Int(round(-projected / pageWidth))

                if deltaIndex == 0 {
                    if projected <= -pageWidth * 0.36 {
                        deltaIndex = 1
                    } else if projected >= pageWidth * 0.36 {
                        deltaIndex = -1
                    }
                }
                deltaIndex = max(-8, min(8, deltaIndex))

                if deltaIndex != 0 {
                    commit(target: currentIndex + deltaIndex)
                }

                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.9, blendDuration: 0.1)) {
                    dragOffset = 0
                }
            }
    }

    private func commit(target: Int) {
        guard !photos.isEmpty else { return }

        if target >= 0 && target < photos.count {
            currentIndex = target
            return
        }

        // 越界时尽量进入前后 event；加冷却避免重复触发
        let now = Date()
        guard now >= externalJumpCooldownUntil else {
            return
        }
        externalJumpCooldownUntil = now.addingTimeInterval(0.14)
        onTargetIndex(target)
    }
}

private struct JourneyPhotoTile: View {
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
            .clipShape(RoundedRectangle(cornerRadius: 20))

            if dimAmount > 0.001 {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(max(0, min(0.45, dimAmount))))
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct JourneyInfoBar: View {
    let event: EventData?
    let photoIndex: Int
    let transitionToken: Int

    @State private var glowOpacity: CGFloat = 0
    @State private var boxScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 8) {
            if let event {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(photoIndex + 1)/\(max(event.photos.count, 1))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(glowOpacity), lineWidth: 1.2)
        }
        .scaleEffect(boxScale)
        .onChange(of: transitionToken) { _, _ in
            boxScale = 0.97
            glowOpacity = 0.9
            withAnimation(.easeOut(duration: 0.12)) {
                boxScale = 1.01
            }
            withAnimation(.easeOut(duration: 0.28)) {
                glowOpacity = 0
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78).delay(0.12)) {
                boxScale = 1
            }
        }
    }
}

private struct JourneyTimeRail: View {
    let dayTitle: String
    let events: [EventData]
    let currentEventIndex: Int
    @Binding var position: CGFloat
    var onEventSelected: (Int) -> Void

    private var eventPositions: [CGFloat] {
        guard !events.isEmpty else { return [] }
        if events.count == 1 { return [0.5] }

        let start = events.first?.startTime ?? .distantPast
        let end = events.last?.startTime ?? start
        let total = max(end.timeIntervalSince(start), 1)

        return events.map { ev in
            let offset = max(ev.startTime.timeIntervalSince(start), 0)
            return CGFloat(offset / total)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(dayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                if currentEventIndex < events.count {
                    Text(events[currentEventIndex].startTime.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, _ in
                        if idx < eventPositions.count {
                            let x = eventPositions[idx] * geo.size.width
                            Circle()
                                .fill(idx == currentEventIndex ? .white : .white.opacity(idx < currentEventIndex ? 0.56 : 0.28))
                                .frame(width: idx == currentEventIndex ? 11 : 8, height: idx == currentEventIndex ? 11 : 8)
                                .position(x: x, y: geo.size.height / 2)
                        }
                    }

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.28), radius: 4)
                        .position(x: position * geo.size.width, y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !eventPositions.isEmpty else { return }
                            let raw = max(0, min(1, value.location.x / max(geo.size.width, 1)))
                            if let nearest = nearestEventIndex(to: raw) {
                                let snap = eventPositions[nearest]
                                if abs(raw - snap) < 0.03 {
                                    position = snap
                                    onEventSelected(nearest)
                                } else {
                                    position = raw
                                }
                            } else {
                                position = raw
                            }
                        }
                        .onEnded { _ in
                            guard let nearest = nearestEventIndex(to: position), nearest < eventPositions.count else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                position = eventPositions[nearest]
                            }
                            onEventSelected(nearest)
                        }
                )
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nearestEventIndex(to value: CGFloat) -> Int? {
        guard !eventPositions.isEmpty else { return nil }

        var nearest = 0
        var minDistance = abs(value - eventPositions[0])
        for index in eventPositions.indices {
            let distance = abs(value - eventPositions[index])
            if distance < minDistance {
                minDistance = distance
                nearest = index
            }
        }
        return nearest
    }
}
