//
//  PhotoEditView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import SwiftData
import UIKit

/// 单张照片编辑：地点（推荐+搜索+地图选点，选好后确认应用）
struct PhotoEditView: View {
    @Bindable var photo: Photo
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearchService = LocationSearchService()
    /// 可选：初始地图区域（如从 Story 无位置补充进入时传入 Story 范围）
    var initialMapRegion: MKCoordinateRegion?
    /// 可选：推荐地点列表（从同一个 story 中按时间接近排序）
    var recommendedLocations: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    /// 可选：地址变更后的回调（用于重新聚合 events）
    var onLocationChanged: (() -> Void)?
    
    @State private var editingCoordinate: CLLocationCoordinate2D?
    @State private var editingLocationName = ""
    @State private var showSaveSuccess = false
    
    /// 针对当前照片的推荐（按拍照时间接近排序）
    private var currentPhotoRecommendations: [(name: String, coordinate: CLLocationCoordinate2D)] {
        guard !recommendedLocations.isEmpty else { return [] }
        // 如果已经有推荐列表，直接使用（已经按时间接近排序）
        return recommendedLocations
    }
    
    /// 地图初始区域：优先当前照片的已有位置，否则用传入的 initialMapRegion，再否则用同 story 其他照片范围，无则 nil（地图会定位到当前所在位置）
    private var knownPhotosRegion: MKCoordinateRegion? {
        // 优先：当前照片已有位置 → 定位到该点
        if let coord = photo.coordinate {
            return MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        if let initialMapRegion = initialMapRegion {
            return initialMapRegion
        }
        // 同 story 其他照片的范围
        let storyPhotos = photo.collections.flatMap { $0.photos.filter { $0.deletedAt == nil && $0.coordinate != nil } }
        let withLoc = storyPhotos.compactMap { $0.coordinate }
        guard !withLoc.isEmpty else { return nil }
        let lats = withLoc.map(\.latitude)
        let lngs = withLoc.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.3, 0.02),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.3, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 推荐地点
                if !currentPhotoRecommendations.isEmpty {
                    recommendSection
                }
                
                // 搜索地点
                searchSection
                
                // 地图选点
                mapSection
            }
            .navigationTitle("编辑地点")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if showSaveSuccess {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("成功修改地点")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.successGreen)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        try? modelContext.save()
                        onLocationChanged?()
                        dismiss()
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                // 初始化编辑状态为当前照片的地址
                editingCoordinate = photo.coordinate
                editingLocationName = photo.manualLocationName ?? photo.cachedLocationName ?? ""
            }
        }
    }
    
    private var recommendSection: some View {
        Section("推荐地点（按时间接近排序）") {
            ForEach(Array(currentPhotoRecommendations.prefix(5).enumerated()), id: \.offset) { _, loc in
                Button {
                    applyToPhoto(coordinate: loc.coordinate, name: loc.name)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(loc.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("应用")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var searchSection: some View {
        Section("搜索地点") {
            LocationSearchView(
                searchService: locationSearchService,
                selectedCoordinate: $editingCoordinate,
                locationName: $editingLocationName
            ) { coord, name in
                editingCoordinate = coord
                editingLocationName = name
            }
            
            if editingCoordinate != nil && !editingLocationName.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(editingLocationName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                    
                    Button {
                        if let coord = editingCoordinate {
                            applyToPhoto(coordinate: coord, name: editingLocationName)
                        }
                    } label: {
                        Text("确认应用到当前照片")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var mapSection: some View {
        Section("在地图上选点") {
            LocationPickerMap(
                coordinate: $editingCoordinate,
                locationName: $editingLocationName,
                initialRegion: knownPhotosRegion
            )
            
            if editingCoordinate != nil && !editingLocationName.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text(editingLocationName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                    
                    Button {
                        if let coord = editingCoordinate {
                            applyToPhoto(coordinate: coord, name: editingLocationName)
                        }
                    } label: {
                        Text("确认应用到当前照片")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func applyToPhoto(coordinate: CLLocationCoordinate2D, name: String) {
        photo.latitude = coordinate.latitude
        photo.longitude = coordinate.longitude
        photo.manualLocationName = name
        editingCoordinate = nil
        editingLocationName = ""
        try? modelContext.save()
        onLocationChanged?()
        withAnimation(.easeInOut) { showSaveSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}
