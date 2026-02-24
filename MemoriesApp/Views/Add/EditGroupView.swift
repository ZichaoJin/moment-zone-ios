//
//  EditGroupView.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import CoreLocation

struct EditGroupView: View {
    @ObservedObject var group: EditablePhotoGroup
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearchService = LocationSearchService()
    @FocusState private var isNoteFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("照片（\(group.photos.count) 张）") {
                    if group.photos.isEmpty {
                        Text("暂无照片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        PhotoPreviewView(
                            photoIds: group.photos,
                            selectedIds: Binding(
                                get: { group.photos },
                                set: { group.photos = $0 }
                            )
                        ) { deletedId in
                            group.photos.removeAll { $0 == deletedId }
                        }
                    }
                }
                
                Section("地点") {
                    LocationSearchView(
                        searchService: locationSearchService,
                        selectedCoordinate: Binding(
                            get: { group.location },
                            set: { group.location = $0 }
                        ),
                        locationName: $group.locationName
                    ) { coordinate, name in
                        group.location = coordinate
                        group.locationName = name
                    }
                }
                
                Section("在地图上选点") {
                    if let location = group.location {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: location,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Annotation(group.locationName.isEmpty ? "位置" : group.locationName, coordinate: location) {
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
                                get: { group.location },
                                set: { group.location = $0 }
                            ),
                            locationName: $group.locationName
                        )
                    }
                }
                
                Section("备注") {
                    TextField("写点什么…", text: $group.note, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isNoteFocused)
                }
                
                Section("时间") {
                    DatePicker("时间", selection: $group.date, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("编辑分组")
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
    EditGroupView(group: EditablePhotoGroup(
        photos: [],
        date: Date(),
        location: nil,
        locationName: ""
    ))
}
