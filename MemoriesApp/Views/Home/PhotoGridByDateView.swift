//
//  PhotoGridByDateView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

/// 按日期分组的照片网格（仿 iPhone 相册：5列正方形、按天分组）
struct PhotoGridByDateView: View {
    let photos: [Photo]
    var isSelectionMode: Bool = false
    @Binding var selectedIds: Set<UUID>
    var extraBottomPadding: CGFloat = 0
    var highlightedPhotoId: UUID? = nil
    var onPhotoTap: ((Photo) -> Void)?
    var onPhotoDoubleTap: ((Photo) -> Void)?
    var onPhotoLongPress: ((Photo) -> Void)?
    var onEdit: ((Photo) -> Void)?
    var onDelete: ((Photo) -> Void)?

    private let columnCount = 5
    private let gridSpacing: CGFloat = 2

    /// 按日期（天）分组，每天一组，按时间倒序
    private var sections: [(date: Date, photos: [Photo])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: photos, by: { cal.startOfDay(for: $0.timestamp) })
        return grouped
            .map { (date: $0.key, photos: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "还没有照片",
                    systemImage: "photo",
                    description: Text("去「添加」里上传照片吧")
                )
            } else {
                // 用 GeometryReader 拿到宽度，提前算好精确的格子边长
                // 这样 PhotoThumbnailView 知道请求尺寸，LazyVGrid 格子也严格正方形
                GeometryReader { geo in
                    let totalSpacing = gridSpacing * CGFloat(columnCount - 1)
                    let cellSize = floor((geo.size.width - totalSpacing) / CGFloat(columnCount))
                    let columns = Array(
                        repeating: GridItem(.fixed(cellSize), spacing: gridSpacing),
                        count: columnCount
                    )
                    let requestSize = CGSize(width: cellSize * 2, height: cellSize * 2) // @2x

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sections, id: \.date) { section in
                                // 日期标题
                                Text(section.date.formatted(date: .complete, time: .omitted))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 12)
                                    .padding(.bottom, 6)

                                // 照片网格
                                LazyVGrid(columns: columns, spacing: gridSpacing) {
                                    ForEach(section.photos, id: \.id) { photo in
                                        gridCell(photo: photo, cellSize: cellSize, requestSize: requestSize)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20 + extraBottomPadding)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private func gridCell(photo: Photo, cellSize: CGFloat, requestSize: CGSize) -> some View {
        let isSelected = selectedIds.contains(photo.id)
        let isHighlighted = highlightedPhotoId == photo.id

        ZStack(alignment: .bottomLeading) {
            PhotoThumbnailView(
                localIdentifier: photo.assetLocalId,
                size: nil,
                cornerRadius: 9,
                requestSize: requestSize
            )
            // 严格固定正方形，超出部分裁切
            .frame(width: cellSize, height: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            if isSelectionMode {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.8), lineWidth: 2)
                    .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear))
                    .frame(width: 22, height: 22)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(5)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .inset(by: 1.5)
                .stroke(Color.accentColor.opacity(isHighlighted ? 1 : 0), lineWidth: isHighlighted ? 3 : 0)
        )
        .shadow(color: isHighlighted ? Color.accentColor.opacity(0.34) : .clear, radius: 6, y: 0)
        .animation(.none, value: isHighlighted)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    guard !isSelectionMode else { return }
                    onPhotoDoubleTap?(photo)
                }
                .exclusively(before: TapGesture().onEnded {
                    if isSelectionMode {
                        if isSelected { selectedIds.remove(photo.id) }
                        else { selectedIds.insert(photo.id) }
                    } else {
                        onPhotoTap?(photo)
                    }
                })
        )
        .id(photo.id)
        .onLongPressGesture {
            onPhotoLongPress?(photo)
        }
        .contextMenu {
            if let onEdit {
                Button { onEdit(photo) } label: { Label("编辑", systemImage: "pencil") }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete(photo) } label: { Label("删除", systemImage: "trash") }
            }
        }
    }
}
