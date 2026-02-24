//
//  EditStoryView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import CoreLocation
import MapKit

/// Story 编辑：合并名称/备注/照片/事件到一个界面
struct EditStoryView: View {
    @Bindable var collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Photo> { p in p.deletedAt == nil }, sort: \Photo.timestamp, order: .reverse) private var allPhotos: [Photo]
    
    @State private var showAlbumPickerPresented = false
    @State private var albumPickerItems: [PhotosPickerItem] = []
    @State private var confirmDeletePhoto: Photo?
    @State private var confirmDeleteEvent: Event?
    @State private var editingEventId: UUID?
    @State private var editingEventName: String = ""
    @State private var showSaveSuccessBanner = false
    @State private var selectedPhotoForDetail: Photo?
    @State private var showLocationEditor = false
    
    private var storyPhotos: [Photo] {
        collection.photos.filter { $0.deletedAt == nil }.sorted { $0.timestamp < $1.timestamp }
    }
    
    private var storyEvents: [Event] {
        collection.events.sorted { $0.startTime < $1.startTime }
    }
    
    private var storyPhotoIds: Set<UUID> {
        Set(storyPhotos.map { $0.id })
    }
    
    private var addablePhotos: [Photo] {
        allPhotos.filter { $0.deletedAt == nil && !storyPhotoIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                infoSection
                photosSection
                if !photosWithoutLocation.isEmpty {
                    missingLocationSection
                }
                eventsSection
            }
            .navigationTitle("编辑回忆")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        updateCollectionTimeRange()
                        try? modelContext.save()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSaveSuccessBanner = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .photosPicker(isPresented: $showAlbumPickerPresented, selection: $albumPickerItems, maxSelectionCount: 100, matching: .images, photoLibrary: .shared())
            .onChange(of: albumPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await addFromAlbumAndAssignEvents(newItems)
                    albumPickerItems = []
                }
            }
            .alert("删除照片", isPresented: Binding(
                get: { confirmDeletePhoto != nil },
                set: { if !$0 { confirmDeletePhoto = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let photo = confirmDeletePhoto {
                        let removedEventId = photo.eventId
                        photo.deletedAt = Date()
                        cleanupEmptyEvents(removedEventId: removedEventId)
                        updateCollectionTimeRange()
                        try? modelContext.save()
                    }
                    confirmDeletePhoto = nil
                }
                Button("取消", role: .cancel) { confirmDeletePhoto = nil }
            } message: {
                Text("将此照片删除？（可在垃圾箱中恢复）")
            }
            .alert("删除事件", isPresented: Binding(
                get: { confirmDeleteEvent != nil },
                set: { if !$0 { confirmDeleteEvent = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let event = confirmDeleteEvent {
                        deleteEvent(event)
                    }
                    confirmDeleteEvent = nil
                }
                Button("取消", role: .cancel) { confirmDeleteEvent = nil }
            } message: {
                Text("删除此事件及其照片？（照片可在垃圾箱中恢复）")
            }
            .overlay(alignment: .top) {
                if showSaveSuccessBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("保存成功")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.successGreen.opacity(0.95), in: Capsule())
                    .shadow(radius: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(item: $selectedPhotoForDetail) { photo in
                PhotoDetailView(photos: storyPhotos, initialPhoto: photo) {
                    rebuildEventsByStandardRules()
                    try? modelContext.save()
                }
            }
            .sheet(isPresented: $showLocationEditor) {
                PerPhotoLocationEditor(
                    photos: Binding(
                        get: { storyPhotos },
                        set: { _ in }
                    ),
                    recommendedLocations: storyLocationRecommendations,
                    onLocationApplied: { _ in
                        rebuildEventsByStandardRules()
                        try? modelContext.save()
                    }
                )
            }
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        Section("名称与备注") {
            TextField("回忆名称", text: $collection.title)
                .font(.headline)
            
            TextField("写一段备注…", text: Binding(
                get: { collection.note ?? "" },
                set: { collection.note = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...5)
            .font(.subheadline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoryCategory.allCases, id: \.self) { category in
                        let selected = collection.storyCategory == category
                        Button {
                            collection.storyCategory = category
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.symbolName)
                                    .font(.caption.weight(.semibold))
                                Text(category.title)
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(selected ? .white : AppTheme.categoryColor(category))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (selected ? AppTheme.categoryColor(category) : AppTheme.categoryColor(category).opacity(0.13)),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    // MARK: - Photos Section
    
    private var photosSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(storyPhotos, id: \.id) { photo in
                        photoCell(photo: photo)
                    }
                    
                    addPhotoButtons
                }
                .padding(.vertical, 4)
            }
            
            Text("\(storyPhotos.count) 张照片")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("照片")
        }
    }
    
    private func photoCell(photo: Photo) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                ZStack(alignment: .bottomLeading) {
                    PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            selectedPhotoForDetail = photo
                        }
                    // 无位置标记（与添加回忆一致）
                    if photo.coordinate == nil {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "location.slash.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(AppTheme.clusterBadgeHighlight.opacity(0.9))
                                    .clipShape(Circle())
                                Spacer()
                            }
                            .padding(4)
                        }
                        .frame(width: 64, height: 64)
                    }
                }
                .frame(width: 64, height: 64)

                if let eventId = photo.eventId,
                   let event = storyEvents.first(where: { $0.id == eventId }) {
                    Text(event.locationName ?? "事件")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 64)
                } else {
                    Text("无归属")
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.clusterBadgeHighlight)
                        .frame(width: 64)
                }
            }

            Button {
                confirmDeletePhoto = photo
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .offset(x: 4, y: -4)
        }
    }
    
    private var addPhotoButtons: some View {
        Button {
            showAlbumPickerPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Missing Location
    
    private var photosWithoutLocation: [Photo] {
        storyPhotos.filter { $0.coordinate == nil }
    }
    
    /// 从 story 中已有位置的照片推荐地点（按时间接近排序）
    private var storyLocationRecommendations: [(name: String, coordinate: CLLocationCoordinate2D)] {
        let withLoc = storyPhotos.filter { $0.coordinate != nil && !$0.displayLocationName.isEmpty }
        var seen = Set<String>()
        return withLoc
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { p -> (name: String, coordinate: CLLocationCoordinate2D)? in
                let name = p.displayLocationName
                guard !seen.contains(name), let coord = p.coordinate else { return nil }
                seen.insert(name)
                return (name: name, coordinate: coord)
            }
    }
    
    /// 当前有位置的照片数（用于“已设 n 张”实时显示）
    private var photosWithLocationCount: Int {
        storyPhotos.filter { $0.coordinate != nil }.count
    }
    
    private var missingLocationSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "location.slash")
                    .foregroundStyle(AppTheme.clusterBadgeHighlight)
                Text("\(photosWithoutLocation.count) 张照片无地点")
                    .font(.subheadline)
                if photosWithLocationCount > 0 {
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.successGreen)
                        Text("已设 \(photosWithLocationCount) 张")
                            .font(.caption)
                            .foregroundStyle(AppTheme.successGreen)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            
            Button {
                showLocationEditor = true
            } label: {
                Label("逐张为照片添加地点", systemImage: "map")
                    .font(.subheadline)
            }
        } header: {
            Text("补充位置")
        }
    }
    
    // MARK: - Events Section
    
    private var eventsSection: some View {
        Section {
            if storyEvents.isEmpty {
                Text("暂无事件，添加照片后将自动生成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(storyEvents, id: \.id) { event in
                    eventRow(event: event)
                }
            }
        } header: {
            Text("事件")
        }
    }
    
    private func eventRow(event: Event) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.subheadline)
                
                if editingEventId == event.id {
                    TextField("事件名称", text: $editingEventName, onCommit: {
                        event.locationName = editingEventName.isEmpty ? nil : editingEventName
                        try? modelContext.save()
                        editingEventId = nil
                    })
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .textFieldStyle(.roundedBorder)
                    
                    Button {
                        event.locationName = editingEventName.isEmpty ? nil : editingEventName
                        try? modelContext.save()
                        editingEventId = nil
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.successGreen)
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(event.locationName ?? event.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .onTapGesture {
                            editingEventName = event.locationName ?? ""
                            editingEventId = event.id
                        }
                    
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            editingEventName = event.locationName ?? ""
                            editingEventId = event.id
                        }
                }
                
                Spacer()
                let eventPhotos = storyPhotos.filter { $0.eventId == event.id }
                Text("\(eventPhotos.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button {
                    confirmDeleteEvent = event
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            let eventPhotos = storyPhotos.filter { $0.eventId == event.id }
            if !eventPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(eventPhotos, id: \.id) { photo in
                            PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
            
            if let note = event.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func deleteEvent(_ event: Event) {
        let now = Date()
        for photo in storyPhotos where photo.eventId == event.id {
            photo.deletedAt = now
        }
        modelContext.delete(event)
        updateCollectionTimeRange()
        try? modelContext.save()
    }
    
    /// 从相册添加照片并自动归入/生成 events
    private func addFromAlbumAndAssignEvents(_ items: [PhotosPickerItem]) async {
        // 只排除未删除的照片，已删除的允许再次添加（恢复）
        let existingIds = Set(collection.photos.filter { $0.deletedAt == nil }.map { $0.assetLocalId })
        var newPhotos: [Photo] = []
        
        // 查询所有照片（包括已删除的），用于恢复已删除的照片
        let allPhotosIncludingDeleted = try? modelContext.fetch(FetchDescriptor<Photo>())
        
        for item in items {
            guard let id = item.itemIdentifier, !existingIds.contains(id) else { continue }
            let info = PhotoService.photoInfo(localIdentifier: id)
            
            // 检查是否已有这个 assetLocalId 的照片（包括已删除的）
            let existingPhoto = allPhotosIncludingDeleted?.first { $0.assetLocalId == id }
            
            let photo: Photo
            if let existing = existingPhoto {
                // 恢复已删除的照片：清除手动地址，使用照片原始GPS
                photo = existing
                photo.deletedAt = nil
                photo.manualLocationName = nil  // 清除之前编辑的地址
                // 使用照片的原始GPS（从相册EXIF获取）
                if let originalLocation = info.location {
                    photo.latitude = originalLocation.latitude
                    photo.longitude = originalLocation.longitude
                    // 清除之前的缓存，让系统重新从GPS反地理编码
                    photo.cachedLocationName = nil
                } else {
                    // 如果没有原始GPS，保持为0（无位置），会显示"无归属"
                    photo.latitude = 0
                    photo.longitude = 0
                    photo.cachedLocationName = nil
                }
            } else {
                // 创建新照片：默认使用导入照片的地址（从相册EXIF获取）
                photo = Photo(
                    assetLocalId: id,
                    timestamp: info.date ?? Date(),
                    latitude: info.location?.latitude ?? 0,
                    longitude: info.location?.longitude ?? 0
                )
                await MainActor.run {
                    modelContext.insert(photo)
                }
            }
            
            await MainActor.run {
                if !collection.photos.contains(where: { $0.id == photo.id }) {
                    collection.photos.append(photo)
                }
            }
            newPhotos.append(photo)
        }
        
        guard !newPhotos.isEmpty else { return }
        
        // 对新添加的照片做反地理编码，填充 cachedLocationName
        await geocodeNewPhotos(newPhotos)
        
        await MainActor.run {
            rebuildEventsByStandardRules()
            updateCollectionTimeRange()
            try? modelContext.save()
        }
    }
    
    /// 对新添加的照片做反地理编码，填充 cachedLocationName
    private func geocodeNewPhotos(_ photos: [Photo]) async {
        let photosNeedingGeocode = photos.filter { $0.coordinate != nil && $0.displayLocationName.isEmpty }
        for photo in photosNeedingGeocode {
            guard let coord = photo.coordinate else { continue }
            if let name = await GeocodeService.landmarkStyleName(coordinate: coord) {
                await MainActor.run {
                    photo.cachedLocationName = name
                }
            }
        }
    }
    
    /// 更新 collection 的时间范围，确保日历能正确显示
    private func updateCollectionTimeRange() {
        let activePhotos = collection.photos.filter { $0.deletedAt == nil }
        guard !activePhotos.isEmpty else { return }
        let timestamps = activePhotos.map(\.timestamp)
        collection.startTime = timestamps.min()
        collection.endTime = timestamps.max()
    }
    
    /// 统一事件分组规则（与创建 story 一致）：
    /// 1) 时间差 > 2 小时
    /// 2) 距离 > 500 米（两张都有坐标时）
    /// 3) 跨天
    private func rebuildEventsByStandardRules() {
        let activePhotos = storyPhotos.sorted { $0.timestamp < $1.timestamp }
        guard !activePhotos.isEmpty else { return }
        let timeThreshold: TimeInterval = 2 * 3600
        let distanceThreshold: CLLocationDistance = 500

        var groups: [[Photo]] = []
        var currentGroup: [Photo] = []
        var groupStartTime: Date?
        var lastLocation: CLLocationCoordinate2D?

        for photo in activePhotos {
            let shouldStartNewGroup = shouldStartNewEvent(
                photoTime: photo.timestamp,
                photoLocation: photo.coordinate,
                groupStartTime: groupStartTime,
                lastLocation: lastLocation,
                timeThreshold: timeThreshold,
                distanceThreshold: distanceThreshold
            )

            if shouldStartNewGroup {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [photo]
                groupStartTime = photo.timestamp
                lastLocation = photo.coordinate
            } else {
                currentGroup.append(photo)
                if let coord = photo.coordinate {
                    lastLocation = coord
                }
            }
        }

        if !currentGroup.isEmpty { groups.append(currentGroup) }

        for event in storyEvents {
            modelContext.delete(event)
        }

        for group in groups where !group.isEmpty {
            let sortedGroup = group.sorted { $0.timestamp < $1.timestamp }
            let title = sortedGroup.first(where: { !$0.displayLocationName.isEmpty })?.displayLocationName

            let event = Event(
                startTime: sortedGroup.first?.timestamp ?? Date(),
                endTime: sortedGroup.last?.timestamp,
                locationName: title
            )
            event.collection = collection
            modelContext.insert(event)

            for photo in sortedGroup {
                photo.eventId = event.id
            }
        }
    }

    private func shouldStartNewEvent(
        photoTime: Date,
        photoLocation: CLLocationCoordinate2D?,
        groupStartTime: Date?,
        lastLocation: CLLocationCoordinate2D?,
        timeThreshold: TimeInterval,
        distanceThreshold: CLLocationDistance
    ) -> Bool {
        guard let groupStartTime else { return true }

        if abs(photoTime.timeIntervalSince(groupStartTime)) > timeThreshold {
            return true
        }

        if !Calendar.current.isDate(photoTime, inSameDayAs: groupStartTime) {
            return true
        }

        if let lastLocation, let photoLocation {
            let from = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
            let to = CLLocation(latitude: photoLocation.latitude, longitude: photoLocation.longitude)
            if from.distance(from: to) > distanceThreshold {
                return true
            }
        }

        return false
    }
    
    /// 移除照片后，检查其所属 event 是否还有照片，没有则自动删除 event
    private func cleanupEmptyEvents(removedEventId: UUID?) {
        guard let eventId = removedEventId else { return }
        let remainingPhotos = collection.photos.filter { $0.deletedAt == nil && $0.eventId == eventId }
        if remainingPhotos.isEmpty {
            if let event = storyEvents.first(where: { $0.id == eventId }) {
                modelContext.delete(event)
            }
        }
    }
}

// MARK: - Album Photo Picker (from system album, creates new Photo records)

struct AlbumPhotoPickerSheet: View {
    @Bindable var collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    var body: some View {
        NavigationStack {
            VStack {
                PhotosPicker(
                    selection: Binding(
                        get: { [] },
                        set: { newItems in
                            Task {
                                await addFromAlbum(newItems)
                            }
                        }
                    ),
                    maxSelectionCount: 100,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("从相册选择照片添加到此回忆")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                if isProcessing {
                    ProgressView("正在添加...")
                        .padding()
                }
            }
            .navigationTitle("从相册添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
    
    private func addFromAlbum(_ items: [PhotosPickerItem]) async {
        isProcessing = true
        defer { isProcessing = false }
        
        let existingIds = Set(collection.photos.map { $0.assetLocalId })
        
        for item in items {
            guard let id = item.itemIdentifier, !existingIds.contains(id) else { continue }
            let info = PhotoService.photoInfo(localIdentifier: id)
            let photo = Photo(
                assetLocalId: id,
                timestamp: info.date ?? Date(),
                latitude: info.location?.latitude ?? 0,
                longitude: info.location?.longitude ?? 0
            )
            await MainActor.run {
                modelContext.insert(photo)
                collection.photos.append(photo)
            }
        }
        
        await MainActor.run {
            try? modelContext.save()
            dismiss()
        }
    }
}

/// 从全部照片多选添加到 Story
struct AddPhotosToStorySheet: View {
    @Bindable var collection: Collection
    let addablePhotos: [Photo]
    var onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedIds: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(addablePhotos, id: \.id) { photo in
                    Button {
                        if selectedIds.contains(photo.id) {
                            selectedIds.remove(photo.id)
                        } else {
                            selectedIds.insert(photo.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                                .frame(width: 50, height: 50)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                if !photo.displayLocationName.isEmpty {
                                    Text(photo.displayLocationName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedIds.contains(photo.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.successGreen)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选择照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加 \(selectedIds.count) 张") {
                        for photo in addablePhotos where selectedIds.contains(photo.id) {
                            if !collection.photos.contains(where: { $0.id == photo.id }) {
                                collection.photos.append(photo)
                            }
                        }
                        try? modelContext.save()
                        dismiss()
                        onDismiss()
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
    }
}
