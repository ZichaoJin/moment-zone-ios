//
//  EditCollectionView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import CoreLocation

struct EditCollectionView: View {
    @ObservedObject var collection: EditableCollection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearchService = LocationSearchService()
    @FocusState private var isNoteFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("照片（\(collection.photoIds.count) 张）") {
                    if collection.photoIds.isEmpty {
                        Text("暂无照片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(collection.photoIds, id: \.self) { photoId in
                                    PhotoThumbnailView(localIdentifier: photoId)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Section("标题") {
                    TextField("集合标题", text: $collection.title)
                }
                
                Section("地点") {
                    LocationSearchView(
                        searchService: locationSearchService,
                        selectedCoordinate: Binding(
                            get: {
                                if let lat = collection.centerLatitude, let lng = collection.centerLongitude {
                                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                                }
                                return nil
                            },
                            set: { newCoord in
                                if let coord = newCoord {
                                    collection.centerLatitude = coord.latitude
                                    collection.centerLongitude = coord.longitude
                                } else {
                                    collection.centerLatitude = nil
                                    collection.centerLongitude = nil
                                }
                            }
                        ),
                        locationName: Binding(
                            get: { "" },
                            set: { _ in }
                        )
                    ) { coordinate, name in
                        collection.centerLatitude = coordinate.latitude
                        collection.centerLongitude = coordinate.longitude
                    }
                }
                
                Section("在地图上选点") {
                    if let lat = collection.centerLatitude, let lng = collection.centerLongitude {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Annotation("位置", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 32, height: 32)
                                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                        .font(.title2)
                                }
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        LocationPickerMap(
                            coordinate: Binding(
                                get: { nil },
                                set: { newCoord in
                                    if let coord = newCoord {
                                        collection.centerLatitude = coord.latitude
                                        collection.centerLongitude = coord.longitude
                                    }
                                }
                            ),
                            locationName: Binding(
                                get: { "" },
                                set: { _ in }
                            )
                        )
                    }
                }
                
                Section("备注") {
                    TextField("写点什么…", text: $collection.note, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isNoteFocused)
                }
                
                Section("时间") {
                    DatePicker("开始时间", selection: $collection.startTime, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束时间", selection: $collection.endTime, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("编辑集合")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

#Preview {
    EditCollectionView(collection: EditableCollection(
        title: "测试",
        startTime: Date(),
        endTime: Date()
    ))
}
