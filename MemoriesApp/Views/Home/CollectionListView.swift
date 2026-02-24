//
//  CollectionListView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

struct CollectionListView: View {
    let collections: [Collection]
    var scrollToId: UUID?
    var onCollectionTap: ((Collection) -> Void)?

    var body: some View {
        Group {
            if collections.isEmpty {
                ContentUnavailableView(
                    "还没有回忆集合",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("去「添加」里上传照片吧")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(collections, id: \.id) { collection in
                            CollectionRowView(collection: collection)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onCollectionTap?(collection)
                                }
                                .id(collection.id)
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

struct CollectionRowView: View {
    let collection: Collection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(collection.title)
                    .font(.headline)
                Spacer()
                Text("\(collection.photos.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 照片缩略图
            if !collection.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(collection.photos.prefix(5)), id: \.id) { photo in
                            PhotoThumbnailView(localIdentifier: photo.assetLocalId)
                        }
                        if collection.photos.count > 5 {
                            Text("+\(collection.photos.count - 5)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, height: 60)
                                .background(.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            
            if let note = collection.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            if let startTime = collection.startTime, let endTime = collection.endTime {
                Text("\(startTime.formatted(date: .abbreviated, time: .shortened)) - \(endTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CollectionListView(collections: [], scrollToId: nil, onCollectionTap: nil)
        .modelContainer(for: [Collection.self], inMemory: true)
}
