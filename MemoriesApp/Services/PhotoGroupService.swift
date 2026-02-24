//
//  PhotoGroupService.swift
//  MemoriesApp
//

import Foundation
import Photos
import CoreLocation

struct PhotoGroup {
    let photos: [String] // localIdentifiers
    let date: Date
    let location: CLLocationCoordinate2D?
    let locationName: String?
}

enum PhotoGroupService {
    /// 按地址和时间分组照片（时间窗口：1天）
    static func groupPhotos(localIdentifiers: [String], timeWindowHours: Double = 24) async -> [PhotoGroup] {
        var photoInfos: [(id: String, date: Date?, location: CLLocationCoordinate2D?)] = []
        
        // 获取所有照片信息
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
        
        var groups: [PhotoGroup] = []
        var currentGroup: [String] = []
        var currentDate: Date?
        var currentLocation: CLLocationCoordinate2D?
        
        for photo in sortedPhotos {
            let photoDate = photo.date ?? Date()
            
            // 判断是否开始新组
            if let groupDate = currentDate {
                let timeDiff = abs(photoDate.timeIntervalSince(groupDate))
                var shouldStartNewGroup = false
                
                // 如果时间差超过窗口，开始新组
                if timeDiff > timeWindowHours * 3600 {
                    shouldStartNewGroup = true
                }
                // 如果位置差异太大（>1km），也开始新组
                else if let currentLoc = currentLocation, let photoLoc = photo.location {
                    let locationDiff = distanceBetween(currentLoc, photoLoc)
                    if locationDiff > 1000 {
                        shouldStartNewGroup = true
                    }
                }
                // 如果当前组没有位置，但新照片有位置，且时间差较大（>6小时），开始新组
                else if currentLocation == nil && photo.location != nil && timeDiff > 6 * 3600 {
                    shouldStartNewGroup = true
                }
                
                if shouldStartNewGroup {
                    // 保存当前组
                    if !currentGroup.isEmpty, let date = currentDate {
                        groups.append(PhotoGroup(
                            photos: currentGroup,
                            date: date,
                            location: currentLocation,
                            locationName: nil
                        ))
                    }
                    // 开始新组
                    currentGroup = [photo.id]
                    currentDate = photoDate
                    currentLocation = photo.location
                } else {
                    // 添加到当前组
                    currentGroup.append(photo.id)
                    // 更新位置（优先使用有位置的照片）
                    if currentLocation == nil && photo.location != nil {
                        currentLocation = photo.location
                    }
                    // 更新时间（使用组内最早的时间）
                    if let groupDate = currentDate, photoDate < groupDate {
                        currentDate = photoDate
                    }
                }
            } else {
                // 第一个照片
                currentGroup = [photo.id]
                currentDate = photoDate
                currentLocation = photo.location
            }
        }
        
        // 保存最后一组
        if !currentGroup.isEmpty, let date = currentDate {
            groups.append(PhotoGroup(
                photos: currentGroup,
                date: date,
                location: currentLocation,
                locationName: nil
            ))
        }
        
        // 为每个组反地理编码获取地点名称
        var groupsWithNames: [PhotoGroup] = []
        for group in groups {
            var locationName: String? = nil
            if let location = group.location {
                locationName = await reverseGeocode(coordinate: location)
            }
            groupsWithNames.append(PhotoGroup(
                photos: group.photos,
                date: group.date,
                location: group.location,
                locationName: locationName
            ))
        }
        
        return groupsWithNames
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
                    let name = placemark.name ?? 
                               (placemark.locality != nil && placemark.subLocality != nil ? 
                                "\(placemark.subLocality!), \(placemark.locality!)" : 
                                placemark.locality)
                    continuation.resume(returning: name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
