//
//  CalendarStoriesView.swift
//  MemoriesApp

import SwiftUI
import SwiftData
import UIKit

/// 日历形式的 Stories 视图
struct CalendarStoriesView: View {
    let storyCollections: [Collection]
    var onStoryTap: (Collection, Date?) -> Void
    var onStoryTagTap: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    var onTrash: (() -> Void)? = nil
    /// 外部高亮的日期（照片选中时）
    var highlightedDate: Date? = nil
    /// 选中照片真正所属的 story IDs（用于高亮标记）
    var highlightedStoryIds: Set<UUID> = []

    @Query(filter: #Predicate<Photo> { p in p.deletedAt == nil }) private var activePhotos: [Photo]

    @State private var scrollTarget: String?
    @State private var showMonthPicker = false
    @State private var collapsedMonthIds: Set<String> = []
    @State private var selectedStoryId: UUID? = nil
    @State private var suppressRecommendedHighlight = false
    @State private var hasInitialScrollPerformed = false
    @State private var lastAutoScrollMonthId: String?

    private let calendar = Calendar.current

    // MARK: - Data

    private var monthRange: [Date] {
        let now = Date()
        let currentMonth = calendar.startOfMonth(for: now)
        guard let earliest = storyCollections.compactMap({ $0.startTime }).min() else {
            return recentMonths(count: 12)
        }
        let earliestMonth = calendar.startOfMonth(for: earliest)
        var months: [Date] = []
        var current = earliestMonth
        while current <= currentMonth {
            months.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return months
    }

    private func recentMonths(count: Int) -> [Date] {
        let now = Date()
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: calendar.startOfMonth(for: now))
        }.reversed()
    }

    private var dateToStories: [Date: [Collection]] {
        var map: [Date: [Collection]] = [:]
        for story in storyCollections {
            let active = story.photos.filter { $0.deletedAt == nil }
            guard !active.isEmpty else { continue }
            let ts = active.map(\.timestamp)
            guard let earliest = ts.min(), let latest = ts.max() else { continue }
            let startDay = calendar.startOfDay(for: earliest)
            let endDay = calendar.startOfDay(for: latest)
            var day = startDay
            while day <= endDay {
                map[day, default: []].append(story)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return map
    }

    private var storyColors: [UUID: Color] {
        var map: [UUID: Color] = [:]
        for story in storyCollections {
            map[story.id] = AppTheme.storyColor(category: story.storyCategory, storyId: story.id)
        }
        return map
    }

    private func monthId(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    private var highlightedDay: Date? {
        guard let d = highlightedDate else { return nil }
        return calendar.startOfDay(for: d)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        Color.clear.frame(height: 36)

                        ForEach(monthRange, id: \.self) { monthDate in
                            let id = monthId(monthDate)
                            MonthCalendarView(
                                monthDate: monthDate,
                                monthId: id,
                                dateToStories: dateToStories,
                                storyColors: storyColors,
                                highlightedDay: selectedStoryId == nil ? highlightedDay : nil,
                                highlightedStoryIds: selectedStoryId == nil ? highlightedStoryIds : [],
                                suppressRecommendedHighlight: suppressRecommendedHighlight,
                                selectedStoryId: selectedStoryId,
                                isCollapsed: collapsedMonthIds.contains(id),
                                onToggleCollapse: {
                                    if collapsedMonthIds.contains(id) {
                                        collapsedMonthIds.remove(id)
                                    } else {
                                        collapsedMonthIds.insert(id)
                                    }
                                },
                                onStoryHighlight: { story in
                                    suppressRecommendedHighlight = true
                                    onStoryTagTap?()
                                    if selectedStoryId == story.id {
                                        selectedStoryId = nil
                                    } else {
                                        selectedStoryId = story.id
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                onDayTap: { date, stories in
                                    if stories.count == 1, let s = stories.first {
                                        onStoryTap(s, date)
                                    }
                                    // 多个 story 时由 DayCellView 的 popover 处理
                                },
                                onStoryTitleTap: { story in
                                    onStoryTap(story, nil)
                                },
                                onPopoverStoryTap: { story, date in
                                    onStoryTap(story, date)
                                }
                            )
                            .id(id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if collapsedMonthIds.isEmpty {
                        collapsedMonthIds = Set(monthRange.map { monthId($0) })
                    }
                    guard !hasInitialScrollPerformed else { return }
                    hasInitialScrollPerformed = true
                    let initialAnchorDate = highlightedDate ?? Date()
                    let targetMonthId = monthId(calendar.startOfMonth(for: initialAnchorDate))
                    lastAutoScrollMonthId = targetMonthId
                    DispatchQueue.main.async {
                        proxy.scrollTo(targetMonthId, anchor: .top)
                    }
                }
                .onChange(of: scrollTarget) { _, t in
                    guard let t else { return }
                    lastAutoScrollMonthId = t
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(t, anchor: .top) }
                    scrollTarget = nil
                }
                .onChange(of: highlightedDate) { _, newDate in
                    guard let d = newDate else { return }
                    // 外部触发了“照片定位高亮”时，清掉 tag 高亮
                    selectedStoryId = nil
                    suppressRecommendedHighlight = false
                    let target = monthId(calendar.startOfMonth(for: d))
                    guard target != lastAutoScrollMonthId else { return }
                    lastAutoScrollMonthId = target
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
                .onChange(of: highlightedStoryIds) { _, newValue in
                    if !newValue.isEmpty {
                        suppressRecommendedHighlight = false
                    }
                }
            }

            // 悬浮按钮组
            floatingButtons
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(
                months: monthRange,
                onSelect: { date in
                    scrollTarget = monthId(date)
                    showMonthPicker = false
                }
            )
            .presentationDetents([.height(360)])
        }
    }

    // MARK: - 悬浮按钮（无背景条，纯圆形按钮）

    private var floatingButtons: some View {
        HStack(spacing: 10) {
            fab(icon: "calendar") { showMonthPicker = true }
            fab(icon: "arrow.down") { scrollTarget = monthId(Date()) }
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
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

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    let monthDate: Date
    let monthId: String
    let dateToStories: [Date: [Collection]]
    let storyColors: [UUID: Color]
    var highlightedDay: Date? = nil
    var highlightedStoryIds: Set<UUID> = []
    var suppressRecommendedHighlight: Bool = false
    var selectedStoryId: UUID? = nil
    var isCollapsed: Bool = false
    var onToggleCollapse: () -> Void
    var onStoryHighlight: (Collection) -> Void
    var onDayTap: (Date, [Collection]) -> Void
    var onStoryTitleTap: (Collection) -> Void
    var onPopoverStoryTap: (Collection, Date) -> Void

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月"; return f.string(from: monthDate)
    }

    private var daysInMonth: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthDate)!
        let firstDay = calendar.startOfMonth(for: monthDate)
        let fw = calendar.component(.weekday, from: firstDay)
        var days: [Date?] = []
        for _ in 0..<((fw - calendar.firstWeekday + 7) % 7) { days.append(nil) }
        for d in range {
            if let date = calendar.date(byAdding: .day, value: d - 1, to: firstDay) { days.append(date) }
        }
        return days
    }

    private var storiesThisMonth: [(collection: Collection, color: Color)] {
        var seen = Set<UUID>()
        var result: [(collection: Collection, color: Color)] = []
        for day in daysInMonth.compactMap({ $0 }) {
            let ds = calendar.startOfDay(for: day)
            if let stories = dateToStories[ds] {
                for s in stories where !seen.contains(s.id) {
                    seen.insert(s.id)
                    result.append((collection: s, color: storyColors[s.id] ?? AppTheme.accent))
                }
            }
        }
        return result
    }

    private var recommendedStoryId: UUID? {
        guard selectedStoryId == nil, !suppressRecommendedHighlight else { return nil }
        return storiesThisMonth.first(where: { highlightedStoryIds.contains($0.collection.id) })?.collection.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(monthTitle)
                .font(.title3.weight(.bold))
                .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let ds = calendar.startOfDay(for: date)
                        let stories = dateToStories[ds] ?? []
                        let containsSelected = selectedStoryId != nil && stories.contains(where: { $0.id == selectedStoryId })
                        let isHL = highlightedDay == ds || containsSelected
                        DayCellView(
                            date: date,
                            stories: stories,
                            storyColors: storyColors,
                            isHighlighted: isHL,
                            highlightedStoryIds: highlightedStoryIds,
                            selectedStoryId: selectedStoryId,
                            onTap: onDayTap,
                            onPopoverStoryTap: onPopoverStoryTap
                        )
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fill)
                    }
                }
            }

            if !storiesThisMonth.isEmpty {
                monthStorySection
            }
        }
        .padding(.vertical, 6)
    }

    private var monthStorySection: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleCollapse()
                }
            } label: {
                HStack(spacing: 8) {
                    Label("本月回忆 \(storiesThisMonth.count)", systemImage: "rectangle.stack.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)

            if isCollapsed {
                compactStoryRow
            } else {
                storyCards
            }
        }
    }

    private var storyCards: some View {
        VStack(spacing: 6) {
            ForEach(storiesThisMonth, id: \.collection.id) { item in
                Button { onStoryTitleTap(item.collection) } label: { storyCardRow(item: item) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private var compactStoryRow: some View {
        ScrollViewReader { proxy in
            let targetHighlightedId: UUID? = {
                if let selectedStoryId,
                   storiesThisMonth.contains(where: { $0.collection.id == selectedStoryId }) {
                    return selectedStoryId
                }
                if let matched = storiesThisMonth.first(where: { highlightedStoryIds.contains($0.collection.id) }) {
                    return matched.collection.id
                }
                if let recommendedStoryId,
                   storiesThisMonth.contains(where: { $0.collection.id == recommendedStoryId }) {
                    return recommendedStoryId
                }
                return nil
            }()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(storiesThisMonth, id: \.collection.id) { item in
                        let highlighted = item.collection.id == selectedStoryId || (selectedStoryId == nil && item.collection.id == recommendedStoryId)
                        let lightBrown = Color(red: 0.86, green: 0.62, blue: 0.33)
                        Button { onStoryHighlight(item.collection) } label: {
                            HStack(spacing: 6) {
                                StoryTypeDot(symbolName: item.collection.storyCategory.symbolName, color: item.color, size: 16, iconSize: 9)
                                Text(item.collection.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((highlighted ? lightBrown.opacity(0.18) : Color(.secondarySystemBackground)), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(highlighted ? lightBrown.opacity(0.9) : Color.black.opacity(0.08), lineWidth: highlighted ? 1.2 : 0.8)
                            )
                            .shadow(color: highlighted ? lightBrown.opacity(0.34) : .clear, radius: 6, y: 0)
                        }
                        .buttonStyle(.plain)
                        .id(item.collection.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .frame(minHeight: 40)
            .padding(.top, 2)
            .onChange(of: selectedStoryId) { _, newValue in
                guard let storyId = newValue,
                      storiesThisMonth.contains(where: { $0.collection.id == storyId }) else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(storyId, anchor: .center)
                }
            }
            .onChange(of: highlightedStoryIds) { _, _ in
                guard let targetHighlightedId else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(targetHighlightedId, anchor: .center)
                }
            }
            .onAppear {
                guard let targetHighlightedId else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(targetHighlightedId, anchor: .center)
                }
            }
        }
    }

    private func storyCardRow(item: (collection: Collection, color: Color)) -> some View {
        let photos = item.collection.photos.filter { $0.deletedAt == nil }
        let covers = Array(photos.sorted { $0.timestamp > $1.timestamp }.prefix(3))

        return HStack(spacing: 10) {
            ZStack {
                ForEach(Array(covers.enumerated().reversed()), id: \.element.id) { i, p in
                    PhotoThumbnailView(
                        localIdentifier: p.assetLocalId,
                        size: nil, cornerRadius: 5,
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
                    StoryTypeDot(symbolName: item.collection.storyCategory.symbolName, color: item.color, size: 11, iconSize: 7)
                    Text("\(photos.count) 张")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("· \(dateRangeText(for: item.collection, photos: photos))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func dateRangeText(for collection: Collection, photos: [Photo]) -> String {
        let start = collection.startTime ?? photos.map(\.timestamp).min()
        let end = collection.endTime ?? photos.map(\.timestamp).max()
        guard let start else { return "" }
        guard let end else { return start.formatted(.dateTime.month().day()) }
        let from = start.formatted(.dateTime.month().day())
        let to = end.formatted(.dateTime.month().day())
        return from == to ? from : "\(from)-\(to)"
    }
}

// MARK: - Day Cell

struct DayCellView: View {
    let date: Date
    let stories: [Collection]
    let storyColors: [UUID: Color]
    var isHighlighted: Bool = false
    var highlightedStoryIds: Set<UUID> = []
    var selectedStoryId: UUID? = nil
    var onTap: (Date, [Collection]) -> Void
    var onPopoverStoryTap: (Collection, Date) -> Void

    @State private var showPopover = false

    private let calendar = Calendar.current
    private var dayNumber: Int { calendar.component(.day, from: date) }
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var primaryColor: Color {
        guard let first = stories.first else { return .clear }
        return storyColors[first.id] ?? AppTheme.accent
    }
    private var secondaryColor: Color {
        guard stories.count > 1 else { return primaryColor }
        let second = stories[1]
        return storyColors[second.id] ?? primaryColor
    }

    var body: some View {
        Button {
            guard !stories.isEmpty else { return }
            // 任何有 story 的日期，点击都弹出 popover 选择
            showPopover = true
        } label: {
            ZStack {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.highlightFill)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppTheme.highlightBorder, lineWidth: 2)
                        .shadow(color: AppTheme.highlightBorder.opacity(0.36), radius: 5, y: 0)
                } else if !stories.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    primaryColor.opacity(0.16 + min(Double(stories.count), 3) * 0.03),
                                    secondaryColor.opacity(0.11 + min(Double(stories.count), 3) * 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .animation(.easeInOut(duration: 0.22), value: stories.map(\.id))
                }

                VStack(spacing: 1) {
                    Spacer(minLength: 0)
                    if isToday {
                        Text("\(dayNumber)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.accentColor))
                    } else {
                        Text("\(dayNumber)")
                            .font(.system(size: 13, weight: (stories.isEmpty && !isHighlighted) ? .regular : .semibold, design: .rounded))
                            .foregroundStyle(isHighlighted ? Color.accentColor : (stories.isEmpty ? .primary : primaryColor))
                            .frame(height: 26)
                    }
                    HStack(spacing: 3) {
                        if !stories.isEmpty {
                            ForEach(stories.prefix(3), id: \.id) { s in
                                StoryTypeDot(symbolName: s.storyCategory.symbolName, color: storyColors[s.id] ?? AppTheme.accent, size: 11, iconSize: 7)
                            }
                        }
                    }
                    .frame(height: 12)
                    Spacer(minLength: 0)
                }
            }
            .aspectRatio(1, contentMode: .fill)
        }
        .buttonStyle(.plain)
        .disabled(stories.isEmpty)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            storyPopoverContent
        }
    }

    /// 悬浮弹出的 story 选择列表
    private var storyPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
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
                    Text(date.formatted(.dateTime.month().day()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(stories.count == 1 ? "1 个回忆" : "\(stories.count) 个回忆")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)

            ForEach(stories, id: \.id) { story in
                let lightBrown = Color(red: 0.86, green: 0.62, blue: 0.33)
                let isOwned = highlightedStoryIds.contains(story.id) || selectedStoryId == story.id
                let photos = story.photos.filter { $0.deletedAt == nil }
                let cover = photos.sorted { $0.timestamp > $1.timestamp }.first

                Button {
                    showPopover = false
                    onPopoverStoryTap(story, date)
                } label: {
                    HStack(spacing: 10) {
                        if let coverId = cover?.assetLocalId {
                            PhotoThumbnailView(
                                localIdentifier: coverId,
                                size: nil,
                                cornerRadius: 6,
                                requestSize: CGSize(width: 72, height: 72)
                            )
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            StoryTypeDot(symbolName: story.storyCategory.symbolName, color: lightBrown, size: 20, iconSize: 11)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(story.title)
                                .font(.subheadline.weight(isOwned ? .bold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(dateRangeText(for: story, photos: photos))
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
                    .background(
                        (isOwned ? lightBrown.opacity(0.14) : Color(.secondarySystemBackground).opacity(0.85)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOwned ? lightBrown.opacity(0.9) : Color.black.opacity(0.08), lineWidth: isOwned ? 1.2 : 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(minWidth: 230)
        .presentationCompactAdaptation(.popover)
    }

    private func dateRangeText(for story: Collection, photos: [Photo]) -> String {
        let start = story.startTime ?? photos.map(\.timestamp).min()
        let end = story.endTime ?? photos.map(\.timestamp).max()
        guard let start else { return "未设置日期" }
        guard let end else { return start.formatted(.dateTime.month().day()) }
        let from = start.formatted(.dateTime.month().day())
        let to = end.formatted(.dateTime.month().day())
        return from == to ? from : "\(from)-\(to)"
    }
}

private struct StoryTypeDot: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 11
    var iconSize: CGFloat = 7

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

// MARK: - Month Picker Sheet

struct MonthPickerSheet: View {
    let months: [Date]
    var onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedYear: Int
    @State private var selectedMonth: Int
    private let calendar = Calendar.current

    private var yearRange: [Int] {
        Set(months.map { calendar.component(.year, from: $0) }).sorted()
    }

    private var monthsForSelectedYear: [Int] {
        months
            .filter { calendar.component(.year, from: $0) == selectedYear }
            .map { calendar.component(.month, from: $0) }
            .sorted()
    }

    init(months: [Date], onSelect: @escaping (Date) -> Void) {
        self.months = months
        self.onSelect = onSelect
        let cal = Calendar.current
        let last = months.last ?? Date()
        _selectedYear = State(initialValue: cal.component(.year, from: last))
        _selectedMonth = State(initialValue: cal.component(.month, from: last))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 0) {
                    Picker("年", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { y in
                            Text(verbatim: "\(y)年").tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("月", selection: $selectedMonth) {
                        ForEach(monthsForSelectedYear, id: \.self) { m in
                            Text(verbatim: "\(m)月").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 190)
                .onChange(of: selectedYear) { _, _ in
                    let available = monthsForSelectedYear
                    if !available.contains(selectedMonth) {
                        selectedMonth = available.last ?? 1
                    }
                }

                Button {
                    var comp = DateComponents()
                    comp.year = selectedYear
                    comp.month = selectedMonth
                    if let date = calendar.date(from: comp) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(date)
                    }
                    dismiss()
                } label: {
                    Text("跳转")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 12)
            .navigationTitle("选择月份").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

// MARK: - Calendar Extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let c = dateComponents([.year, .month], from: date)
        return self.date(from: c) ?? date
    }
}
