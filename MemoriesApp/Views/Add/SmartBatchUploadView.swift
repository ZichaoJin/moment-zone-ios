//
//  SmartBatchUploadView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import PhotosUI

/// 智能批量上传：唯一入口，自动生成 Auto Collections
struct SmartBatchUploadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPhotoIds: [String] = []
    @State private var isProcessing = false
    @State private var photos: [Photo] = []
    @State private var autoCollections: [EditableCollection] = []
    @State private var showCollections = false
    @State private var editingCollectionIndex: Int?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(
                        selection: Binding(
                            get: { [] },
                            set: { newItems in
                                Task {
                                    var ids: [String] = []
                                    for item in newItems {
                                        if let id = item.itemIdentifier {
                                            ids.append(id)
                                        }
                                    }
                                    await processSelectedPhotos(ids)
                                }
                            }
                        ),
                        maxSelectionCount: 200,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("选择照片（可多选）", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    if !selectedPhotoIds.isEmpty {
                        Text("已选 \(selectedPhotoIds.count) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("智能批量上传")
                } footer: {
                    Text("上传照片后，系统会自动按时间和地点分组生成回忆集合")
                }
                
                if showCollections && !autoCollections.isEmpty {
                    Section {
                        Text("已自动分成 \(autoCollections.count) 个回忆集合，可点击编辑")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Section("回忆集合（点击可编辑）") {
                        ForEach(Array(autoCollections.enumerated()), id: \.element.id) { index, collection in
                            CollectionPreviewRow(
                                collection: collection,
                                index: index,
                                onEdit: {
                                    editingCollectionIndex = index
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("智能批量上传")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveCollections()
                    }
                    .disabled(autoCollections.isEmpty)
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("正在智能分组...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(isPresented: Binding(
                get: { editingCollectionIndex != nil },
                set: { if !$0 { editingCollectionIndex = nil } }
            )) {
                if let index = editingCollectionIndex, index < autoCollections.count {
                    EditCollectionView(collection: autoCollections[index])
                }
            }
        }
    }
    
    private func processSelectedPhotos(_ ids: [String]) async {
        isProcessing = true
        defer { isProcessing = false }
        
        selectedPhotoIds = ids
        
        // 第一步：创建 Photo 记录（读 EXIF 时间/GPS）
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
        
        // 第二步：生成 Auto Collections（切分）
        let collectionResults = AutoCollectionService.generateAutoCollections(from: createdPhotos)
        
        // 转换为可编辑的 Collection
        autoCollections = collectionResults.map { result in
            EditableCollection(from: result.collection, photos: result.photos)
        }
        
        showCollections = true
    }
    
    private func saveCollections() {
        // 保存所有 Photo
        for photo in photos {
            modelContext.insert(photo)
        }
        
        // 保存所有 Collection 并建立关系
        for editableCollection in autoCollections {
            let collection = editableCollection.toCollection()
            modelContext.insert(collection)
            
            // 建立 Photo 和 Collection 的关系（SwiftData 会自动处理多对多）
            for photo in photos where editableCollection.photoIds.contains(photo.assetLocalId) {
                // SwiftData 的 @Relationship 会自动处理，直接 append 即可
                photo.collections.append(collection)
            }
        }
        
        try? modelContext.save()
        dismiss()
    }
}

// 可编辑的 Collection（用于预览和编辑）
class EditableCollection: ObservableObject, Identifiable {
    let id: UUID
    var title: String
    var note: String
    var startTime: Date
    var endTime: Date
    var centerLatitude: Double?
    var centerLongitude: Double?
    var coverAssetId: String?
    var photoIds: [String]  // assetLocalIds
    var isStory: Bool  // 用户合并成的 Story
    
    init(from collection: Collection, photos: [Photo]) {
        self.id = collection.id
        self.title = collection.title
        self.note = collection.note ?? ""
        self.startTime = collection.startTime ?? Date()
        self.endTime = collection.endTime ?? Date()
        self.centerLatitude = collection.centerLatitude
        self.centerLongitude = collection.centerLongitude
        self.coverAssetId = collection.coverAssetId
        self.photoIds = photos.map { $0.assetLocalId }
        self.isStory = (collection.type == .story)
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        startTime: Date,
        endTime: Date,
        centerLatitude: Double? = nil,
        centerLongitude: Double? = nil,
        coverAssetId: String? = nil,
        photoIds: [String] = [],
        isStory: Bool = false
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.startTime = startTime
        self.endTime = endTime
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.coverAssetId = coverAssetId
        self.photoIds = photoIds
        self.isStory = isStory
    }
    
    func toCollection() -> Collection {
        Collection(
            id: id,
            title: title,
            note: note.isEmpty ? nil : note,
            type: isStory ? .story : .auto,
            startTime: startTime,
            endTime: endTime,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            coverAssetId: coverAssetId
        )
    }
}

struct CollectionPreviewRow: View {
    @ObservedObject var collection: EditableCollection
    let index: Int
    var onEdit: () -> Void
    
    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(collection.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(collection.photoIds.count) 张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                // 照片缩略图
                if !collection.photoIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(collection.photoIds.prefix(5)), id: \.self) { photoId in
                                PhotoThumbnailView(localIdentifier: photoId)
                            }
                            if collection.photoIds.count > 5 {
                                Text("+\(collection.photoIds.count - 5)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, height: 60)
                                    .background(.gray.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                
                if !collection.note.isEmpty {
                    Text(collection.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Text("\(collection.startTime.formatted(date: .abbreviated, time: .shortened)) - \(collection.endTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct TripView: View {
    let trip: MultiLevelGroup
    let tripIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 行程标题
            HStack {
                Text(trip.tripName)
                    .font(.headline)
                Spacer()
                Text("\(trip.locations.count) 个地点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 时间范围
            Text("\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) - \(trip.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 地点列表
            ForEach(Array(trip.locations.enumerated()), id: \.element.id) { locationIndex, location in
                LocationGroupRow(location: location, locationIndex: locationIndex)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LocationGroupRow: View {
    let location: MultiLevelGroup.LocationGroup
    let locationIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(location.locationName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(location.photos.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 照片缩略图
            if !location.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(location.photos.prefix(4)), id: \.self) { photoId in
                            PhotoThumbnailView(localIdentifier: photoId)
                        }
                        if location.photos.count > 4 {
                            Text("+\(location.photos.count - 4)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, height: 50)
                                .background(.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            
            Text(location.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.leading, 8)
    }
}

#Preview {
    SmartBatchUploadView()
        .modelContainer(for: [Memory.self], inMemory: true)
}
