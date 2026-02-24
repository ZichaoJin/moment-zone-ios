//
//  PhotoListView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

struct PhotoListView: View {
    @Environment(\.modelContext) private var modelContext
    let photos: [Photo]
    var scrollToId: UUID?
    var onPhotoTap: ((Photo) -> Void)?
    var onEdit: ((Photo) -> Void)?
    var onDelete: ((Photo) -> Void)?

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "还没有照片",
                    systemImage: "photo",
                    description: Text("去「添加」里上传照片吧")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(photos, id: \.id) { photo in
                            PhotoRowView(photo: photo, modelContext: modelContext)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onPhotoTap?(photo)
                                }
                                .id(photo.id)
                                .contextMenu {
                                    if let onEdit = onEdit {
                                        Button {
                                            onEdit(photo)
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                    }
                                    if let onDelete = onDelete {
                                        Button(role: .destructive) {
                                            onDelete(photo)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if let onDelete = onDelete {
                                        Button(role: .destructive) {
                                            onDelete(photo)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if let onEdit = onEdit {
                                        Button {
                                            onEdit(photo)
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                    }
                                }
                        }
                    }
                    .onChange(of: scrollToId) { _, newId in
                        guard let id = newId else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

struct PhotoRowView: View {
    let photo: Photo
    var modelContext: ModelContext?
    
    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                let titleText: String = {
                    if let note = photo.note, !note.isEmpty { return note }
                    let loc = photo.displayLocationName
                    let time = photo.timestamp.formatted(date: .abbreviated, time: .shortened)
                    if loc.isEmpty { return time }
                    return "\(loc) · \(time)"
                }()
                Text(titleText)
                    .font(.body)
                    .lineLimit(2)
                
                HStack {
                    if !photo.displayLocationName.isEmpty {
                        Text(photo.displayLocationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .task(id: photo.id) {
            guard let ctx = modelContext,
                  photo.coordinate != nil,
                  (photo.manualLocationName ?? "").isEmpty,
                  (photo.cachedLocationName ?? "").isEmpty else { return }
            if let name = await GeocodeService.reverseGeocode(coordinate: photo.coordinate!) {
                photo.cachedLocationName = name
                try? ctx.save()
            }
        }
    }
}

#Preview {
    PhotoListView(photos: [], scrollToId: nil, onPhotoTap: nil)
        .modelContainer(for: [Photo.self], inMemory: true)
}
