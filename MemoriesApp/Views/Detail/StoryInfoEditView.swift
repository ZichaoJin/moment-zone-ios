//
//  StoryInfoEditView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

/// 编辑 Story 标题与总述
struct StoryInfoEditView: View {
    @Bindable var collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("回忆标题", text: $collection.title)
                }
                Section("总述") {
                    TextField("写一句这段回忆为什么重要…", text: Binding(
                        get: { collection.note ?? "" },
                        set: { collection.note = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
            }
            .navigationTitle("编辑回忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        try? modelContext.save()
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}
