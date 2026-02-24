//
//  BatchPhotoUploadView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import PhotosUI
import MapKit
import CoreLocation

struct BatchPhotoUploadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearchService = LocationSearchService()
    
    @State private var selectedPhotoIds: [String] = []
    @State private var isProcessing = false
    @State private var groups: [EditablePhotoGroup] = []
    @State private var showGroups = false
    @State private var editingGroupIndex: Int?
    @State private var showMergeView = false
    
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
                        maxSelectionCount: 100,
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
                    Text("批量上传")
                } footer: {
                    Text("选择照片后，系统会自动按时间和地点分组创建回忆")
                }
                
                if showGroups && !groups.isEmpty {
                    Section {
                        Text("已自动分成 \(groups.count) 组，可点击编辑修改")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Section("分组结果（点击可编辑）") {
                        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                            GroupPreviewRow(
                                group: group,
                                index: index,
                                onEdit: {
                                    editingGroupIndex = index
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("批量上传")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showGroups && groups.count > 1 {
                        Button("合并") {
                            showMergeView = true
                        }
                    }
                    Button("创建") {
                        createMemoriesFromGroups()
                    }
                    .disabled(groups.isEmpty)
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("正在处理照片...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(isPresented: Binding(
                get: { editingGroupIndex != nil },
                set: { if !$0 { editingGroupIndex = nil } }
            )) {
                if let index = editingGroupIndex, index < groups.count {
                    EditGroupView(group: groups[index])
                }
            }
            .sheet(isPresented: $showMergeView) {
                MergeGroupsView(groups: $groups)
            }
        }
    }
    
    private func processSelectedPhotos(_ ids: [String]) async {
        isProcessing = true
        defer { isProcessing = false }
        
        selectedPhotoIds = ids
        
        // 按地址和时间分组
        let photoGroups = await PhotoGroupService.groupPhotos(localIdentifiers: ids, timeWindowHours: 24)
        
        // 转换为可编辑的分组
        groups = photoGroups.map { group in
            EditablePhotoGroup(
                photos: group.photos,
                date: group.date,
                location: group.location,
                locationName: group.locationName ?? ""
            )
        }
        showGroups = true
    }
    
    private func createMemoriesFromGroups() {
        for group in groups {
            let memory = Memory(
                timestamp: group.date,
                latitude: group.location?.latitude ?? 0,
                longitude: group.location?.longitude ?? 0,
                locationName: group.locationName,
                note: group.note,
                assetLocalIds: group.photos
            )
            modelContext.insert(memory)
        }
        
        try? modelContext.save()
        dismiss()
    }
    
}

// 可编辑的分组数据
class EditablePhotoGroup: ObservableObject, Identifiable {
    let id = UUID()
    var photos: [String]
    var date: Date
    var location: CLLocationCoordinate2D?
    var locationName: String
    var note: String = ""
    
    init(photos: [String], date: Date, location: CLLocationCoordinate2D?, locationName: String) {
        self.photos = photos
        self.date = date
        self.location = location
        self.locationName = locationName
    }
}

struct GroupPreviewRow: View {
    @ObservedObject var group: EditablePhotoGroup
    let index: Int
    var onEdit: () -> Void
    
    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("组 \(index + 1)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(group.photos.count) 张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                // 照片缩略图预览
                if !group.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(group.photos.prefix(5)), id: \.self) { photoId in
                                PhotoThumbnailView(localIdentifier: photoId)
                            }
                            if group.photos.count > 5 {
                                Text("+\(group.photos.count - 5)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, height: 60)
                                    .background(.gray.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                
                if !group.locationName.isEmpty {
                    Label(group.locationName, systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if group.location == nil {
                    Label("无位置信息", systemImage: "location.slash")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                
                Label(group.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct PhotoThumbnailView: View {
    let localIdentifier: String
    var size: CGFloat? = 60
    var cornerRadius: CGFloat = 8
    var requestSize: CGSize? = nil
    @State private var image: UIImage?
    @State private var requestToken: String = ""
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.18))
            }
        }
        .ifLet(size) { view, value in
            view.frame(width: value, height: value)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear {
            loadImage()
        }
        .onChange(of: localIdentifier) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        let target = requestSize ?? {
            let side = max((size ?? 120) * 1.8, 120)
            return CGSize(width: side, height: side)
        }()
        let token = "\(localIdentifier)_\(Int(target.width))x\(Int(target.height))"
        requestToken = token
        PhotoService.loadThumbnail(localIdentifier: localIdentifier, targetSize: target) { img in
            guard requestToken == token else { return }
            image = img
        }
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

#Preview {
    BatchPhotoUploadView()
        .modelContainer(for: [Memory.self], inMemory: true)
}
