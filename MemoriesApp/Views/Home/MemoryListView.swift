//
//  MemoryListView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData

struct MemoryListView: View {
    @Environment(\.modelContext) private var modelContext
    let memories: [Memory]
    var scrollToId: UUID?
    var onMemoryTap: ((Memory) -> Void)?
    var onEdit: ((Memory) -> Void)?

    var body: some View {
        Group {
            if memories.isEmpty {
                ContentUnavailableView(
                    "还没有回忆",
                    systemImage: "heart.text.square",
                    description: Text("去「添加」里创建第一条回忆吧")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(memories, id: \.id) { memory in
                            MemoryRowView(memory: memory, onEdit: {
                                onEdit?(memory)
                            })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onMemoryTap?(memory)
                            }
                            .id(memory.id)
                        }
                        .onDelete(perform: deleteMemories)
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

    private func deleteMemories(at offsets: IndexSet) {
        for index in offsets {
            guard index < memories.count else { continue }
            modelContext.delete(memories[index])
        }
    }
}

struct MemoryRowView: View {
    let memory: Memory
    var onEdit: (() -> Void)?
    
    @State private var showEditSheet = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.note.isEmpty ? "无备注" : memory.note)
                    .lineLimit(2)
                    .font(.body)
                HStack {
                    if !memory.locationName.isEmpty {
                        Text(memory.locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(memory.timestamp, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("编辑", systemImage: "pencil") {
                    onEdit?()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MemoryListView(memories: [], scrollToId: nil, onMemoryTap: nil, onEdit: nil)
        .modelContainer(for: [Memory.self], inMemory: true)
}
