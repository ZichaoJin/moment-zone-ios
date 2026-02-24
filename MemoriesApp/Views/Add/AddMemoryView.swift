//
//  AddMemoryView.swift
//  MemoriesApp
//

import SwiftUI
import SwiftData
import MapKit
import PhotosUI
import CoreLocation

struct AddMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearchService = LocationSearchService()
    @State private var note = ""
    @State private var locationName = ""
    @State private var timestamp = Date()
    @State private var saved = false
    @State private var saveMessage = "回忆已添加到列表"
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPhotoIds: [String] = []
    @FocusState private var isNoteFocused: Bool
    @State private var showBatchAdd = false
    
    // 编辑模式（暂时保留，后续可以改为编辑 Photo）
    var editingMemory: Memory?
    var isEditMode: Bool { editingMemory != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片") {
                    PhotoPickerView(selectedLocalIds: $selectedPhotoIds)
                    if !selectedPhotoIds.isEmpty {
                        Text("已选 \(selectedPhotoIds.count) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        PhotoPreviewView(photoIds: selectedPhotoIds, selectedIds: $selectedPhotoIds) { deletedId in
                            selectedPhotoIds.removeAll { $0 == deletedId }
                        }
                    }
                }
                Section("地点") {
                    LocationSearchView(
                        searchService: locationSearchService,
                        selectedCoordinate: $selectedCoordinate,
                        locationName: $locationName
                    ) { coordinate, name in
                        // 搜索选中后，地图会自动更新
                    }
                }
                Section("在地图上选点") {
                    LocationPickerMap(
                        coordinate: $selectedCoordinate,
                        locationName: $locationName
                    )
                }
                Section("备注") {
                    TextField("写点什么…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isNoteFocused)
                }
                Section("时间") {
                    DatePicker("时间", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: selectedPhotoIds) { _, newIds in
                // 从最早的照片（按时间排序）自动获取时间和地点
                if !newIds.isEmpty {
                    // 按时间排序，取最早的
                    let sortedIds = newIds.sorted { id1, id2 in
                        let date1 = PhotoService.creationDate(localIdentifier: id1) ?? Date.distantFuture
                        let date2 = PhotoService.creationDate(localIdentifier: id2) ?? Date.distantFuture
                        return date1 < date2
                    }
                    
                    if let earliestId = sortedIds.first {
                        let info = PhotoService.photoInfo(localIdentifier: earliestId)
                        
                        // 自动设置时间
                        if let date = info.date {
                            timestamp = date
                        }
                        
                        // 自动设置地点（如果有 GPS 信息）
                        if let location = info.location {
                            selectedCoordinate = location
                            // 反地理编码获取地点名称
                            reverseGeocode(coordinate: location)
                        }
                    }
                }
            }
            .onAppear {
                if let memory = editingMemory {
                    // 编辑模式：填充现有数据
                    note = memory.note
                    locationName = memory.locationName
                    timestamp = memory.timestamp
                    selectedCoordinate = (memory.latitude != 0 || memory.longitude != 0) ? 
                        CLLocationCoordinate2D(latitude: memory.latitude, longitude: memory.longitude) : nil
                    selectedPhotoIds = memory.assetLocalIds
                }
            }
            .navigationTitle(isEditMode ? "编辑回忆" : "添加回忆")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !isEditMode {
                        Button {
                            showBatchAdd = true
                        } label: {
                            Image(systemName: "square.stack.3d.up")
                        }
                    } else {
                        Button("取消") {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveMemory()
                    }
                    .disabled(note.isEmpty && locationName.isEmpty && selectedPhotoIds.isEmpty)
                }
            }
            .sheet(isPresented: $showBatchAdd) {
                BatchAddView()
            }
            .alert("已保存", isPresented: $saved) {
                Button("确定", role: .cancel) {
                    if isEditMode {
                        dismiss()
                    } else {
                        resetForm()
                    }
                }
            } message: {
                Text(saveMessage)
            }
        }
    }

    private func saveMemory() {
        let lat = selectedCoordinate?.latitude ?? 0
        let lng = selectedCoordinate?.longitude ?? 0
        
        if let existingMemory = editingMemory {
            // 编辑模式：更新现有回忆
            existingMemory.timestamp = timestamp
            existingMemory.latitude = lat
            existingMemory.longitude = lng
            existingMemory.locationName = locationName
            existingMemory.note = note
            existingMemory.assetLocalIds = selectedPhotoIds
            existingMemory.updatedAt = Date()
        } else {
            // 新建模式
            let memory = Memory(
                timestamp: timestamp,
                latitude: lat,
                longitude: lng,
                locationName: locationName,
                note: note,
                assetLocalIds: selectedPhotoIds
            )
            modelContext.insert(memory)
        }
        
        try? modelContext.save()
        saveMessage = isEditMode ? "回忆已更新" : "回忆已添加到列表"
        saved = true
    }

    private func resetForm() {
        note = ""
        locationName = ""
        timestamp = Date()
        selectedCoordinate = nil
        selectedPhotoIds = []
        isNoteFocused = false
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        Task {
            if let name = await GeocodeService.landmarkStyleName(coordinate: coordinate) {
                await MainActor.run {
                    locationName = name
                }
            }
        }
    }
}

#Preview {
    AddMemoryView()
        .modelContainer(for: [Memory.self], inMemory: true)
}
