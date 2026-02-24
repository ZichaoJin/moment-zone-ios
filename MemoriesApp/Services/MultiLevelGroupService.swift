//
//  MultiLevelGroupService.swift
//  MemoriesApp
//

import Foundation
import Photos
import CoreLocation

/// 多级分组：支持不同颗粒度的分组
/// - Trip: 大组（如7天旅行）
/// - Location: 小组（如不同酒店、商场）
struct MultiLevelGroup {
    let id = UUID()
    var tripName: String
    var startDate: Date
    var endDate: Date
    var locations: [LocationGroup]
    
    struct LocationGroup {
        let id = UUID()
        var locationName: String
        var coordinate: CLLocationCoordinate2D?
        var photos: [String] // localIdentifiers
        var date: Date
    }
}

enum MultiLevelGroupService {
    /// 多级分组：先按大行程分组，再按地点分组
    /// - Parameters:
    ///   - localIdentifiers: 照片标识符
    ///   - tripTimeWindowHours: 大组时间窗口（默认7天）
    ///   - locationDistanceMeters: 小组位置距离阈值（默认1000米）
    static func createMultiLevelGroups(
        localIdentifiers: [String],
        tripTimeWindowHours: Double = 7 * 24,
        locationDistanceMeters: Double = 1000
    ) async -> [MultiLevelGroup] {
        // 获取所有照片信息
        var photoInfos: [(id: String, date: Date?, location: CLLocationCoordinate2D?)] = []
        for id in localIdentifiers {
            let info = PhotoService.photoInfo(localIdentifier: id)
            photoInfos.append((id, info.date, info.location))
        }
        
        // 按时间排序
        let sortedPhotos = photoInfos.sorted { photo1, photo2 in
            let date1 = photo1.date ?? Date.distantPast
            let date2 = photo2.date ?? Date.distantPast
            return date1 < date2
        }
        
        var trips: [MultiLevelGroup] = []
        var currentTripPhotos: [(id: String, date: Date?, location: CLLocationCoordinate2D?)] = []
        var currentTripStartDate: Date?
        
        // 第一步：按时间窗口分组成大行程（Trip）
        for photo in sortedPhotos {
            let photoDate = photo.date ?? Date()
            
            if let tripStartDate = currentTripStartDate {
                let timeDiff = abs(photoDate.timeIntervalSince(tripStartDate))
                
                if timeDiff > tripTimeWindowHours * 3600 {
                    // 时间差超过窗口，创建新行程
                    if !currentTripPhotos.isEmpty, let startDate = currentTripStartDate {
                        let trip = await createTrip(from: currentTripPhotos, startDate: startDate, locationDistanceMeters: locationDistanceMeters)
                        trips.append(trip)
                    }
                    currentTripPhotos = [photo]
                    currentTripStartDate = photoDate
                } else {
                    // 添加到当前行程
                    currentTripPhotos.append(photo)
                }
            } else {
                // 第一个照片
                currentTripPhotos = [photo]
                currentTripStartDate = photoDate
            }
        }
        
        // 保存最后一个行程
        if !currentTripPhotos.isEmpty, let startDate = currentTripStartDate {
            let trip = await createTrip(from: currentTripPhotos, startDate: startDate, locationDistanceMeters: locationDistanceMeters)
            trips.append(trip)
        }
        
        return trips
    }
    
    /// 从照片创建行程，并按地点分组
    private static func createTrip(
        from photos: [(id: String, date: Date?, location: CLLocationCoordinate2D?)],
        startDate: Date,
        locationDistanceMeters: Double
    ) async -> MultiLevelGroup {
        var locations: [MultiLevelGroup.LocationGroup] = []
        var currentLocationPhotos: [(id: String, date: Date?, location: CLLocationCoordinate2D?)] = []
        var currentLocationCoord: CLLocationCoordinate2D?
        var currentLocationName: String?
        var currentLocationDate: Date?
        
        // 第二步：按地点分组
        for photo in photos {
            let photoDate = photo.date ?? Date()
            
            if let locationCoord = currentLocationCoord, let photoLocation = photo.location {
                // 检查位置距离
                let distance = distanceBetween(locationCoord, photoLocation)
                
                if distance > locationDistanceMeters {
                    // 距离太远，创建新地点组
                    if !currentLocationPhotos.isEmpty, let date = currentLocationDate {
                        var locationName = currentLocationName ?? "未知地点"
                        if locationName == "未知地点" {
                            locationName = await reverseGeocode(coordinate: locationCoord) ?? "未知地点"
                        }
                        locations.append(MultiLevelGroup.LocationGroup(
                            locationName: locationName,
                            coordinate: locationCoord,
                            photos: currentLocationPhotos.map { $0.id },
                            date: date
                        ))
                    }
                    currentLocationPhotos = [photo]
                    currentLocationCoord = photoLocation
                    currentLocationDate = photoDate
                    currentLocationName = await reverseGeocode(coordinate: photoLocation)
                } else {
                    // 添加到当前地点组
                    currentLocationPhotos.append(photo)
                    if photoDate < (currentLocationDate ?? Date.distantFuture) {
                        currentLocationDate = photoDate
                    }
                }
            } else if let photoLocation = photo.location {
                // 新地点组
                if !currentLocationPhotos.isEmpty {
                    let locationName = currentLocationName ?? "未知地点"
                    locations.append(MultiLevelGroup.LocationGroup(
                        locationName: locationName,
                        coordinate: currentLocationCoord,
                        photos: currentLocationPhotos.map { $0.id },
                        date: currentLocationDate ?? Date()
                    ))
                }
                currentLocationPhotos = [photo]
                currentLocationCoord = photoLocation
                currentLocationDate = photoDate
                let geocodedName = await reverseGeocode(coordinate: photoLocation)
                currentLocationName = geocodedName
            } else {
                // 无位置照片，添加到当前组或创建新组
                if currentLocationPhotos.isEmpty || currentLocationCoord == nil {
                    // 创建无位置组
                    if !currentLocationPhotos.isEmpty {
                        locations.append(MultiLevelGroup.LocationGroup(
                            locationName: currentLocationName ?? "无位置信息",
                            coordinate: nil,
                            photos: currentLocationPhotos.map { $0.id },
                            date: currentLocationDate ?? Date()
                        ))
                    }
                    currentLocationPhotos = [photo]
                    currentLocationCoord = nil
                    currentLocationDate = photoDate
                    currentLocationName = "无位置信息"
                } else {
                    // 添加到当前组
                    currentLocationPhotos.append(photo)
                }
            }
        }
        
        // 保存最后一个地点组
        if !currentLocationPhotos.isEmpty {
            var locationName = currentLocationName ?? "无位置信息"
            if locationName == "无位置信息" && currentLocationCoord != nil {
                let geocodedName = await reverseGeocode(coordinate: currentLocationCoord!)
                locationName = geocodedName ?? "无位置信息"
            }
            locations.append(MultiLevelGroup.LocationGroup(
                locationName: locationName,
                coordinate: currentLocationCoord,
                photos: currentLocationPhotos.map { $0.id },
                date: currentLocationDate ?? Date()
            ))
        }
        
        // 生成行程名称
        let endDate = photos.compactMap { $0.date }.max() ?? startDate
        let tripName = generateTripName(locations: locations, startDate: startDate, endDate: endDate)
        
        return MultiLevelGroup(
            tripName: tripName,
            startDate: startDate,
            endDate: endDate,
            locations: locations
        )
    }
    
    private static func distanceBetween(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }
    
    private static func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    let name = placemark.locality ?? placemark.administrativeArea ?? placemark.country
                    continuation.resume(returning: name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private static func generateTripName(locations: [MultiLevelGroup.LocationGroup], startDate: Date, endDate: Date) -> String {
        // 找出主要地点（照片最多的地点）
        if let mainLocation = locations.max(by: { $0.photos.count < $1.photos.count }) {
            if !mainLocation.locationName.isEmpty && mainLocation.locationName != "无位置信息" {
                let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                if days > 0 {
                    return "\(mainLocation.locationName) \(days)天"
                }
                return mainLocation.locationName
            }
        }
        
        // 如果没有主要地点，使用日期范围
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}
