//
//  TrashView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

/// 回忆垃圾箱：显示已删除的照片与 Story，可恢复或彻底删除
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Photo> { p in p.deletedAt != nil }, sort: \Photo.deletedAt, order: .reverse) private var deletedPhotos: [Photo]
    @Query(filter: #Predicate<Collection> { c in c.deletedAt != nil }, sort: \Collection.deletedAt, order: .reverse) private var deletedCollections: [Collection]

    private var hasAnyDeleted: Bool {
        !deletedPhotos.isEmpty || !deletedCollections.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            List {
                if hasAnyDeleted {
                    Section {
                        Button(role: .destructive) {
                            for c in deletedCollections {
                                for event in c.events {
                                    modelContext.delete(event)
                                }
                                modelContext.delete(c)
                            }
                            for p in deletedPhotos {
                                modelContext.delete(p)
                            }
                            try? modelContext.save()
                        } label: {
                            Label("一键清空", systemImage: "trash.slash")
                        }
                    }
                }
                if !deletedCollections.isEmpty {
                    Section("已删除的 Story") {
                        ForEach(deletedCollections.filter { $0.type == .story }, id: \.id) { collection in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(collection.title)
                                        .font(.headline)
                                    if let at = collection.deletedAt {
                                        Text("删除于 \(at.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("恢复") {
                                    collection.deletedAt = nil
                                    for photo in collection.photos {
                                        photo.deletedAt = nil
                                    }
                                    try? modelContext.save()
                                }
                                .buttonStyle(.bordered)
                                Button(role: .destructive) {
                                    for event in collection.events {
                                        modelContext.delete(event)
                                    }
                                    modelContext.delete(collection)
                                    try? modelContext.save()
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
                if !deletedPhotos.isEmpty {
                    Section("已删除的照片") {
                        ForEach(deletedPhotos, id: \.id) { photo in
                            HStack(spacing: 12) {
                                PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                    if let at = photo.deletedAt {
                                        Text("删除于 \(at.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("恢复") {
                                    photo.deletedAt = nil
                                    try? modelContext.save()
                                }
                                .buttonStyle(.bordered)
                                Button(role: .destructive) {
                                    modelContext.delete(photo)
                                    try? modelContext.save()
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
                if deletedPhotos.isEmpty && deletedCollections.isEmpty {
                    ContentUnavailableView(
                        "垃圾箱为空",
                        systemImage: "trash",
                        description: Text("删除的照片或 Story 会出现在这里，可恢复或彻底删除")
                    )
                }
            }
            .navigationTitle("垃圾箱")
        }
    }
}
