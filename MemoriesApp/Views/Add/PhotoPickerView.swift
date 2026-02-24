//
//  PhotoPickerView.swift
//  MemoriesApp
//

import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @Binding var selectedLocalIds: [String]
    var maxSelectionCount: Int = 20

    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("选择照片", systemImage: "photo.on.rectangle.angled")
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                var ids: [String] = []
                for item in newItems {
                    if let id = item.itemIdentifier {
                        ids.append(id)
                    }
                }
                await MainActor.run {
                    selectedLocalIds = ids
                }
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var ids: [String] = []
        var body: some View {
            PhotoPickerView(selectedLocalIds: $ids)
        }
    }
    return PreviewWrapper()
}
