//
//  MergeGroupsView.swift
//  MemoriesApp
//

import SwiftUI

struct MergeGroupsView: View {
    @Binding var groups: [EditablePhotoGroup]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndices: Set<Int> = []
    @State private var undoStack: [[EditablePhotoGroup]] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("选择要合并的分组（至少2个）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("选择分组") {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        GroupSelectionRow(
                            group: group,
                            index: index,
                            isSelected: selectedIndices.contains(index)
                        ) {
                            if selectedIndices.contains(index) {
                                selectedIndices.remove(index)
                            } else {
                                selectedIndices.insert(index)
                            }
                        }
                    }
                }
                
                if !undoStack.isEmpty {
                    Section {
                        Button("撤回上一步") {
                            undoLastMerge()
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .navigationTitle("合并分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("合并") {
                        mergeSelectedGroups()
                    }
                    .disabled(selectedIndices.count < 2)
                }
            }
        }
    }
    
    private func mergeSelectedGroups() {
        guard selectedIndices.count >= 2 else { return }
        
        // 保存当前状态到撤回栈（深拷贝）
        undoStack.append(groups.map { group in
            let copy = EditablePhotoGroup(
                photos: Array(group.photos),
                date: group.date,
                location: group.location,
                locationName: group.locationName
            )
            copy.note = group.note
            return copy
        })
        
        // 按索引排序（从大到小，避免删除时索引变化）
        let sortedIndices = selectedIndices.sorted(by: >)
        let targetIndex = sortedIndices.last!
        let targetGroup = groups[targetIndex]
        
        // 合并所有选中的组到目标组
        for index in sortedIndices.dropLast() {
            let sourceGroup = groups[index]
            
            // 合并照片
            targetGroup.photos.append(contentsOf: sourceGroup.photos)
            
            // 如果目标组没有位置，使用源组的位置
            if targetGroup.location == nil && sourceGroup.location != nil {
                targetGroup.location = sourceGroup.location
                targetGroup.locationName = sourceGroup.locationName
            }
            
            // 合并备注
            if !sourceGroup.note.isEmpty {
                if targetGroup.note.isEmpty {
                    targetGroup.note = sourceGroup.note
                } else {
                    targetGroup.note += "\n" + sourceGroup.note
                }
            }
            
            // 使用更早的时间
            if sourceGroup.date < targetGroup.date {
                targetGroup.date = sourceGroup.date
            }
        }
        
        // 删除已合并的组（从大到小删除）
        for index in sortedIndices.dropLast() {
            groups.remove(at: index)
        }
        
        selectedIndices.removeAll()
    }
    
    private func undoLastMerge() {
        guard !undoStack.isEmpty else { return }
        groups = undoStack.removeLast()
        selectedIndices.removeAll()
    }
}

struct GroupSelectionRow: View {
    @ObservedObject var group: EditablePhotoGroup
    let index: Int
    let isSelected: Bool
    var onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("组 \(index + 1)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if !group.locationName.isEmpty {
                        Text(group.locationName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(group.photos.count) 张 · \(group.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MergeGroupsView(groups: .constant([]))
}
