//
//  BatchAddView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import MapKit

/// 简化的添加视图：选照片 → 输入名字/备注 → 补位置 → 保存
struct BatchAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPhotoIds: [String] = []
    @State private var isProcessing = false
    @State private var photos: [Photo] = []
    @State private var autoCollections: [EditableCollection] = []
    @State private var storyTitle = ""
    @State private var storyNote = ""
    @State private var storyCategory: StoryCategory = .daily
    @State private var eventTitles: [UUID: String] = [:]
    @State private var eventNotes: [UUID: String] = [:]
    @State private var showSaveSuccessBanner = false
    @State private var addMorePickerItems: [PhotosPickerItem] = []
    @State private var showLocationEditor = false
    
    private var photosWithoutLocation: [Photo] {
        photos.filter { $0.coordinate == nil }
    }
    
    private var photosWithLocation: [Photo] {
        photos.filter { $0.coordinate != nil }
    }
    
    /// 从已有位置照片推荐地点（去重）
    private var recommendedLocations: [(name: String, coordinate: CLLocationCoordinate2D)] {
        let withLoc = photosWithLocation.sorted { $0.timestamp < $1.timestamp }
        var seen = Set<String>()
        var results: [(name: String, coordinate: CLLocationCoordinate2D)] = []
        for photo in withLoc {
            let name = photo.displayLocationName
            if !name.isEmpty && !seen.contains(name), let coord = photo.coordinate {
                seen.insert(name)
                results.append((name: name, coordinate: coord))
            }
        }
        return results
    }
    
    var body: some View {
        NavigationStack {
            Form {
                photosSection
                
                if !photos.isEmpty {
                    storyInfoSection
                    
                    if !photosWithoutLocation.isEmpty {
                        missingLocationSection
                    }
                }
            }
            .navigationTitle("添加回忆")
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
                    Button("保存") { saveAll() }
                        .fontWeight(.semibold)
                        .disabled(photos.isEmpty)
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("正在分析照片...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
            .onChange(of: addMorePickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    let newIds = newItems.compactMap { $0.itemIdentifier }
                    await addMorePhotos(newIds)
                    addMorePickerItems = []
                }
            }
            .sheet(isPresented: $showLocationEditor) {
                PerPhotoLocationEditor(
                    photos: $photos,
                    recommendedLocations: recommendedLocations,
                    onLocationApplied: { _ in }
                )
            }
        }
    }
    
    // MARK: - Photos Section
    
    private var photosSection: some View {
        Section {
            if photos.isEmpty {
                PhotosPicker(
                    selection: Binding(
                        get: { [] },
                        set: { newItems in
                            Task {
                                let ids = newItems.compactMap { $0.itemIdentifier }
                                await processSelectedPhotos(ids)
                            }
                        }
                    ),
                    maxSelectionCount: 500,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("选择照片")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedPhotoIds, id: \.self) { photoId in
                            ZStack(alignment: .topTrailing) {
                                PhotoThumbnailView(localIdentifier: photoId)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                // 无地点标注
                                if let photo = photos.first(where: { $0.assetLocalId == photoId }),
                                   photo.coordinate == nil {
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
                                
                                Button {
                                    removePhoto(id: photoId)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .offset(x: 4, y: -4)
                            }
                            .frame(width: 64, height: 64)
                        }
                        
                        PhotosPicker(
                            selection: $addMorePickerItems,
                            maxSelectionCount: 500,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 64, height: 64)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Text("\(photos.count) 张照片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Story Info
    
    private var storyInfoSection: some View {
        Section("回忆") {
            TextField("回忆名称", text: $storyTitle)
                .font(.headline)
            TextField("写一段关于这段回忆的话…", text: $storyNote, axis: .vertical)
                .lineLimit(2...5)
                .font(.subheadline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoryCategory.allCases, id: \.self) { category in
                        Button {
                            storyCategory = category
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.symbolName)
                                    .font(.caption.weight(.semibold))
                                Text(category.title)
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(storyCategory == category ? .white : AppTheme.categoryColor(category))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (storyCategory == category ? AppTheme.categoryColor(category) : AppTheme.categoryColor(category).opacity(0.13)),
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
    
    // MARK: - Missing Location
    
    private var missingLocationSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "location.slash")
                    .foregroundStyle(AppTheme.clusterBadgeHighlight)
                Text("\(photosWithoutLocation.count) 张照片无地点")
                    .font(.subheadline)
                if photosWithLocation.count > 0 {
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.successGreen)
                        Text("已设 \(photosWithLocation.count) 张")
                            .font(.caption)
                            .foregroundStyle(AppTheme.successGreen)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            
            if !recommendedLocations.isEmpty {
                ForEach(Array(recommendedLocations.prefix(5).enumerated()), id: \.offset) { _, loc in
                    Button {
                        applyLocationToAllMissing(coordinate: loc.coordinate, name: loc.name)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("应用到全部无位置照片")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
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
    
    // MARK: - Actions
    
    private func processSelectedPhotos(_ ids: [String]) async {
        isProcessing = true
        defer { isProcessing = false }
        
        selectedPhotoIds = ids
        var createdPhotos: [Photo] = []
        for id in ids {
            let info = PhotoService.photoInfo(localIdentifier: id)
            let photo = Photo(
                assetLocalId: id,
                timestamp: info.date ?? Date(),
                latitude: info.location?.latitude ?? 0,
                longitude: info.location?.longitude ?? 0
            )
            createdPhotos.append(photo)
        }
        photos = createdPhotos
        
        let collectionResults = AutoCollectionService.generateAutoCollections(from: createdPhotos)
        autoCollections = collectionResults.map { result in
            EditableCollection(from: result.collection, photos: result.photos)
        }
        await geocodePhotosWithLocation()
        if !autoCollections.isEmpty {
            storyTitle = defaultStoryTitle()
            await fillEventTitlesWithLandmarks()
        }
    }
    
    /// 对有坐标的照片做反地理编码，填充 cachedLocationName 以供推荐
    private func geocodePhotosWithLocation() async {
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
    
    private func addMorePhotos(_ newIds: [String]) async {
        isProcessing = true
        defer { isProcessing = false }
        
        let existingIds = Set(selectedPhotoIds)
        let uniqueNewIds = newIds.filter { !existingIds.contains($0) }
        guard !uniqueNewIds.isEmpty else { return }
        
        selectedPhotoIds.append(contentsOf: uniqueNewIds)
        
        var newPhotos: [Photo] = []
        for id in uniqueNewIds {
            let info = PhotoService.photoInfo(localIdentifier: id)
            let photo = Photo(
                assetLocalId: id,
                timestamp: info.date ?? Date(),
                latitude: info.location?.latitude ?? 0,
                longitude: info.location?.longitude ?? 0
            )
            newPhotos.append(photo)
        }
        photos.append(contentsOf: newPhotos)
        
        let allPhotos = photos
        let collectionResults = AutoCollectionService.generateAutoCollections(from: allPhotos)
        autoCollections = collectionResults.map { result in
            EditableCollection(from: result.collection, photos: result.photos)
        }
        await geocodePhotosWithLocation()
        if !autoCollections.isEmpty {
            storyTitle = defaultStoryTitle()
            await fillEventTitlesWithLandmarks()
        }
    }
    
    private func removePhoto(id: String) {
        selectedPhotoIds.removeAll { $0 == id }
        photos.removeAll { $0.assetLocalId == id }
        for editable in autoCollections {
            editable.photoIds.removeAll { $0 == id }
        }
        autoCollections.removeAll { $0.photoIds.isEmpty }
        if photos.isEmpty {
            storyTitle = ""
            storyNote = ""
        }
    }
    
    private func applyLocationToAllMissing(coordinate: CLLocationCoordinate2D, name: String) {
        var count = 0
        for photo in photos where photo.coordinate == nil {
            photo.latitude = coordinate.latitude
            photo.longitude = coordinate.longitude
            photo.manualLocationName = name
            count += 1
        }
    }
    
    private func fillEventTitlesWithLandmarks() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        for editable in autoCollections {
            let firstPhoto = photos.first(where: { editable.photoIds.contains($0.assetLocalId) })
            if let coord = firstPhoto?.coordinate,
               let name = await GeocodeService.landmarkStyleName(coordinate: coord) {
                await MainActor.run { eventTitles[editable.id] = name }
            } else if let start = firstPhoto?.timestamp ?? Optional(editable.startTime) {
                await MainActor.run { eventTitles[editable.id] = formatter.string(from: start) }
            }
        }
    }
    
    private func defaultStoryTitle() -> String {
        guard let first = autoCollections.first else { return "回忆" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let dateStr = formatter.string(from: first.startTime)
        let firstPhotos = photos.filter { first.photoIds.contains($0.assetLocalId) }
        if let loc = firstPhotos.first?.displayLocationName, !loc.isEmpty {
            return "\(dateStr) \(loc)"
        }
        return "\(dateStr) 回忆"
    }
    
    private func saveAll() {
        guard !photos.isEmpty else { return }
        
        for photo in photos { modelContext.insert(photo) }
        
        let allStarts = autoCollections.map(\.startTime)
        let allEnds = autoCollections.map(\.endTime)
        let startTime = allStarts.min() ?? photos.first?.timestamp ?? Date()
        let endTime = allEnds.max() ?? photos.last?.timestamp ?? Date()
        let title = storyTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultStoryTitle() : storyTitle
        let withLoc = photos.compactMap(\.coordinate)
        let centerLat = withLoc.isEmpty ? nil : withLoc.map(\.latitude).reduce(0, +) / Double(withLoc.count)
        let centerLng = withLoc.isEmpty ? nil : withLoc.map(\.longitude).reduce(0, +) / Double(withLoc.count)
        
        let story = Collection(
            title: title,
            note: storyNote.isEmpty ? nil : storyNote,
            type: .story,
            storyCategoryRaw: storyCategory.rawValue,
            startTime: startTime,
            endTime: endTime,
            centerLatitude: centerLat,
            centerLongitude: centerLng,
            coverAssetId: photos.first?.assetLocalId
        )
        modelContext.insert(story)
        
        for editable in autoCollections {
            let displayName = eventTitles[editable.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? eventTitles[editable.id]
                : photos.first(where: { editable.photoIds.contains($0.assetLocalId) })?.displayLocationName
            let event = Event(
                note: eventNotes[editable.id]?.isEmpty == false ? eventNotes[editable.id] : nil,
                startTime: editable.startTime,
                endTime: editable.endTime,
                locationName: displayName
            )
            event.collection = story
            modelContext.insert(event)
            
            for photo in photos where editable.photoIds.contains(photo.assetLocalId) {
                photo.collections.append(story)
                photo.eventId = event.id
            }
        }
        
        for photo in photos where photo.eventId == nil {
            if !photo.collections.contains(where: { $0.id == story.id }) {
                photo.collections.append(story)
            }
        }
        
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveSuccessBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismiss()
        }
    }
}

// MARK: - Per-Photo Location Editor

/// 逐张照片设置位置：每张照片独立设位置，支持推荐 + 搜索 + 地图选点，有成功反馈
struct PerPhotoLocationEditor: View {
    @Binding var photos: [Photo]
    let recommendedLocations: [(name: String, coordinate: CLLocationCoordinate2D)]
    var onLocationApplied: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = LocationSearchService()
    @State private var editingCoordinate: CLLocationCoordinate2D?
    @State private var editingLocationName = ""
    @State private var selectedPhotoIndex: Int = 0
    @State private var showSuccessBanner = false
    @State private var successMessage = ""
    
    private var missingPhotos: [Photo] {
        photos.filter { $0.coordinate == nil }
    }
    
    private var currentPhoto: Photo? {
        guard selectedPhotoIndex < missingPhotos.count else { return nil }
        return missingPhotos[selectedPhotoIndex]
    }
    
    /// 针对当前照片的推荐（按拍照时间接近排序）
    private var currentPhotoRecommendations: [(name: String, coordinate: CLLocationCoordinate2D)] {
        guard let photo = currentPhoto else { return recommendedLocations }
        let withLoc = photos.filter { $0.coordinate != nil && !$0.displayLocationName.isEmpty }
        if withLoc.isEmpty { return recommendedLocations }
        
        var seen = Set<String>()
        return withLoc
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
            Form {
                if !missingPhotos.isEmpty {
                    photoSelectorSection
                    if !currentPhotoRecommendations.isEmpty {
                        recommendSection
                    }
                    searchSection
                    mapSection
                    if !currentPhotoRecommendations.isEmpty, !missingPhotos.isEmpty {
                        applyAllSection
                    }
                }
            }
            .navigationTitle("添加地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .top) {
                if showSuccessBanner {
                    successBannerView
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
    
    private var photoSelectorSection: some View {
        Section("选择照片 (\(selectedPhotoIndex + 1)/\(missingPhotos.count))") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(missingPhotos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            selectedPhotoIndex = index
                            editingCoordinate = nil
                            editingLocationName = ""
                        } label: {
                            VStack(spacing: 4) {
                                PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(index == selectedPhotoIndex ? Color.accentColor : .clear, lineWidth: 3)
                                    )
                                    .padding(index == selectedPhotoIndex ? 0 : 1.5) // 选中时无padding，未选中时有padding，避免边框被遮
                                Text(photo.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4) // 增加垂直padding，避免被遮住
            }
            .scrollClipDisabled()
        }
    }
    
    private var recommendSection: some View {
        Section("推荐地点（按时间接近排序）") {
            ForEach(Array(currentPhotoRecommendations.prefix(5).enumerated()), id: \.offset) { _, loc in
                Button {
                    applyToCurrentPhoto(coordinate: loc.coordinate, name: loc.name)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(loc.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("应用")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var searchSection: some View {
        Section("搜索地点") {
            LocationSearchView(
                searchService: searchService,
                selectedCoordinate: $editingCoordinate,
                locationName: $editingLocationName
            ) { _, _ in
                // 仅更新坐标与名称，由下方「确认应用到当前照片」统一应用（与编辑地点一致）
            }
            
            if editingCoordinate != nil && !editingLocationName.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(editingLocationName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                    
                    Button {
                        if let coord = editingCoordinate {
                            applyToCurrentPhoto(coordinate: coord, name: editingLocationName)
                        }
                    } label: {
                        Text("确认应用到当前照片")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    /// 已有位置照片的中心区域（用于初始化地图）
    private var knownPhotosRegion: MKCoordinateRegion? {
        let withLoc = photos.compactMap { $0.coordinate }
        guard !withLoc.isEmpty else { return nil }
        let lats = withLoc.map(\.latitude)
        let lngs = withLoc.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.3, 0.02),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.3, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
    
    private var mapSection: some View {
        Section("在地图上选点") {
            LocationPickerMap(
                coordinate: $editingCoordinate,
                locationName: $editingLocationName,
                initialRegion: knownPhotosRegion
            )
            
            if editingCoordinate != nil && !editingLocationName.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(editingLocationName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                    
                    Button {
                        if let coord = editingCoordinate {
                            applyToCurrentPhoto(coordinate: coord, name: editingLocationName)
                        }
                    } label: {
                        Text("确认应用到当前照片")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var applyAllSection: some View {
        Section {
            if let first = currentPhotoRecommendations.first {
                Button {
                    applyToAllMissing(coordinate: first.coordinate, name: first.name)
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(AppTheme.clusterBadgeHighlight)
                        Text("将「\(first.name)」应用到全部 \(missingPhotos.count) 张无位置照片")
                            .font(.subheadline)
                    }
                }
            }
        }
    }
    
    private var successBannerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(successMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.successGreen)
        .clipShape(Capsule())
        .shadow(radius: 4)
        .padding(.top, 8)
    }
    
    private func applyToCurrentPhoto(coordinate: CLLocationCoordinate2D, name: String) {
        guard let photo = currentPhoto else { return }
        photo.latitude = coordinate.latitude
        photo.longitude = coordinate.longitude
        photo.manualLocationName = name
        onLocationApplied(1)

        showSuccess("成功添加地点")

        // 自动跳到下一张，或全部完成后用当前成功提示拉下
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if missingPhotos.isEmpty {
                // 用当前成功提示显示完后自动拉下
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    dismiss()
                }
            } else if selectedPhotoIndex < missingPhotos.count - 1 {
                selectedPhotoIndex += 1
            } else if selectedPhotoIndex > 0 {
                selectedPhotoIndex = max(0, selectedPhotoIndex - 1)
            }
            editingCoordinate = nil
            editingLocationName = ""
        }
    }
    
    private func applyToAllMissing(coordinate: CLLocationCoordinate2D, name: String) {
        var count = 0
        for photo in photos where photo.coordinate == nil {
            photo.latitude = coordinate.latitude
            photo.longitude = coordinate.longitude
            photo.manualLocationName = name
            count += 1
        }
        onLocationApplied(count)
        showSuccess("成功添加地点")
        // 用成功提示显示完后自动拉下
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            dismiss()
        }
    }
    
    private func showSuccess(_ message: String) {
        successMessage = message
        withAnimation(.easeInOut) { showSuccessBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut) { showSuccessBanner = false }
        }
    }
}

#Preview {
    BatchAddView()
}
