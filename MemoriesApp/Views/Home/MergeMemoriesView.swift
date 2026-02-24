//
//  MergeMemoriesView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

struct MergeMemoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Memory.timestamp, order: .reverse) private var allMemories: [Memory]
    
    @State private var selectedMemoryIds: Set<UUID> = []
    @State private var undoStack: [[Memory]] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("选择要合并的回忆（至少2个）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("选择回忆") {
                    ForEach(allMemories) { memory in
                        MemorySelectionRow(
                            memory: memory,
                            isSelected: selectedMemoryIds.contains(memory.id)
                        ) {
                            if selectedMemoryIds.contains(memory.id) {
                                selectedMemoryIds.remove(memory.id)
                            } else {
                                selectedMemoryIds.insert(memory.id)
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
            .navigationTitle("合并回忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("合并") {
                        mergeSelectedMemories()
                    }
                    .disabled(selectedMemoryIds.count < 2)
                }
            }
        }
    }
    
    private func mergeSelectedMemories() {
        guard selectedMemoryIds.count >= 2 else { return }
        
        let selectedMemories = allMemories.filter { selectedMemoryIds.contains($0.id) }
        guard selectedMemories.count >= 2 else { return }
        
        // 保存当前状态到撤回栈
        undoStack.append(selectedMemories.map { memory in
            Memory(
                id: memory.id,
                timestamp: memory.timestamp,
                latitude: memory.latitude,
                longitude: memory.longitude,
                locationName: memory.locationName,
                note: memory.note,
                assetLocalIds: memory.assetLocalIds,
                createdAt: memory.createdAt,
                updatedAt: memory.updatedAt
            )
        })
        
        // 选择目标回忆（使用最早的那个）
        let targetMemory = selectedMemories.min(by: { $0.timestamp < $1.timestamp })!
        
        // 合并所有选中的回忆到目标回忆
        for memory in selectedMemories where memory.id != targetMemory.id {
            // 合并照片
            targetMemory.assetLocalIds.append(contentsOf: memory.assetLocalIds)
            
            // 如果目标回忆没有位置，使用源回忆的位置
            if (targetMemory.latitude == 0 && targetMemory.longitude == 0) &&
               (memory.latitude != 0 || memory.longitude != 0) {
                targetMemory.latitude = memory.latitude
                targetMemory.longitude = memory.longitude
                targetMemory.locationName = memory.locationName
            }
            
            // 合并备注
            if !memory.note.isEmpty {
                if targetMemory.note.isEmpty {
                    targetMemory.note = memory.note
                } else {
                    targetMemory.note += "\n" + memory.note
                }
            }
            
            // 使用更早的时间
            if memory.timestamp < targetMemory.timestamp {
                targetMemory.timestamp = memory.timestamp
            }
            
            // 删除源回忆
            modelContext.delete(memory)
        }
        
        targetMemory.updatedAt = Date()
        
        try? modelContext.save()
        selectedMemoryIds.removeAll()
    }
    
    private func undoLastMerge() {
        // 撤回功能需要更复杂的实现，这里先留空
        // 因为 SwiftData 不支持直接恢复已删除的对象
        // 可以考虑使用 Core Data 的 undo manager 或者保存完整快照
    }
}

struct MemorySelectionRow: View {
    let memory: Memory
    let isSelected: Bool
    var onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.note.isEmpty ? "无备注" : memory.note)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        if !memory.locationName.isEmpty {
                            Text(memory.locationName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(memory.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(memory.assetLocalIds.count) 张照片")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MergeMemoriesView()
        .modelContainer(for: [Memory.self], inMemory: true)
}
