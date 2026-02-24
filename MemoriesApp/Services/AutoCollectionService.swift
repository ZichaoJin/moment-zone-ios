//
//  AutoCollectionService.swift
//  MemoriesApp
//

import Foundation
import CoreLocation

/// 自动生成 Auto Collections：把一堆按时间排序的 Photo，切成若干段，每一段就是一个 auto Collection（事件块）
enum AutoCollectionService {
    /// Collection 和对应的 Photo 列表
    struct CollectionWithPhotos {
        let collection: Collection
        let photos: [Photo]
    }
    
    /// 生成 Auto Collections
    /// - Parameters:
    ///   - photos: 照片列表（需要已按时间排序）
    ///   - timeThresholdHours: 时间断点阈值（默认2小时）
    ///   - distanceThresholdMeters: 空间断点阈值（默认500米）
    static func generateAutoCollections(
        from photos: [Photo],
        timeThresholdHours: Double = 2,
        distanceThresholdMeters: Double = 500
    ) -> [CollectionWithPhotos] {
        guard !photos.isEmpty else { return [] }
        
        // 按时间排序
        let sortedPhotos = photos.sorted { $0.timestamp < $1.timestamp }
        
        var result: [CollectionWithPhotos] = []
        var currentPhotos: [Photo] = []
        var currentStartTime: Date?
        var lastPhotoLocation: CLLocationCoordinate2D?
        
        for photo in sortedPhotos {
            let photoDate = photo.timestamp
            let photoLocation = photo.coordinate
            
            // 判断是否开始新事件
            if shouldStartNewEvent(
                photo: photo,
                photoDate: photoDate,
                photoLocation: photoLocation,
                lastTime: currentStartTime,
                lastLocation: lastPhotoLocation,
                timeThresholdHours: timeThresholdHours,
                distanceThresholdMeters: distanceThresholdMeters
            ) {
                // 保存当前事件
                if !currentPhotos.isEmpty, let startTime = currentStartTime {
                    let collection = createAutoCollection(from: currentPhotos, startTime: startTime)
                    result.append(CollectionWithPhotos(collection: collection, photos: currentPhotos))
                }
                
                // 开始新事件
                currentPhotos = [photo]
                currentStartTime = photoDate
                lastPhotoLocation = photoLocation
            } else {
                // 添加到当前事件
                currentPhotos.append(photo)
                // 更新最后位置（用于下一张照片的距离判断）
                if photoLocation != nil {
                    lastPhotoLocation = photoLocation
                }
            }
        }
        
        // 保存最后一个事件
        if !currentPhotos.isEmpty, let startTime = currentStartTime {
            let collection = createAutoCollection(from: currentPhotos, startTime: startTime)
            result.append(CollectionWithPhotos(collection: collection, photos: currentPhotos))
        }
        
        return result
    }
    
    /// 判断是否应该开始新事件
    private static func shouldStartNewEvent(
        photo: Photo,
        photoDate: Date,
        photoLocation: CLLocationCoordinate2D?,
        lastTime: Date?,
        lastLocation: CLLocationCoordinate2D?,
        timeThresholdHours: Double,
        distanceThresholdMeters: Double
    ) -> Bool {
        guard let lastTime = lastTime else { return true }
        
        // 规则 1：时间间隔 > 2小时 → 新事件
        let timeDiff = abs(photoDate.timeIntervalSince(lastTime))
        if timeDiff > timeThresholdHours * 3600 {
            return true
        }
        
        // 规则 2：距离 > 500米 → 新事件（前提是都有坐标）
        if let lastLoc = lastLocation, let photoLoc = photoLocation {
            let distance = distanceBetween(lastLoc, photoLoc)
            if distance > distanceThresholdMeters {
                return true
            }
        }
        
        return false
    }
    
    /// 创建 Auto Collection
    private static func createAutoCollection(from photos: [Photo], startTime: Date) -> Collection {
        guard !photos.isEmpty else {
            return Collection(title: "未知事件", type: .auto, startTime: startTime)
        }
        
        // 计算时间范围
        let endTime = photos.map { $0.timestamp }.max() ?? startTime
        
        // 计算中心坐标（有坐标的照片的平均值）
        let photosWithLocation = photos.compactMap { $0.coordinate }
        var centerLat: Double? = nil
        var centerLng: Double? = nil
        
        if !photosWithLocation.isEmpty {
            let avgLat = photosWithLocation.map { $0.latitude }.reduce(0, +) / Double(photosWithLocation.count)
            let avgLng = photosWithLocation.map { $0.longitude }.reduce(0, +) / Double(photosWithLocation.count)
            centerLat = avgLat
            centerLng = avgLng
        }
        
        // 生成标题
        let title = generateTitle(for: photos, startTime: startTime, centerLat: centerLat, centerLng: centerLng)
        
        // 封面：第一张照片
        let coverAssetId = photos.first?.assetLocalId
        
        return Collection(
            title: title,
            type: .auto,
            startTime: startTime,
            endTime: endTime,
            centerLatitude: centerLat,
            centerLongitude: centerLng,
            coverAssetId: coverAssetId
        )
    }
    
    /// 生成 Collection 标题
    private static func generateTitle(
        for photos: [Photo],
        startTime: Date,
        centerLat: Double?,
        centerLng: Double?
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let dateStr = formatter.string(from: startTime)
        
        // 如果有地点信息，优先使用
        if let firstPhoto = photos.first,
           let locationName = firstPhoto.manualLocationName,
           !locationName.isEmpty {
            return "\(dateStr) \(locationName)"
        }
        
        // 如果有坐标，尝试反地理编码（这里先简化，后续可以异步获取）
        if centerLat != nil && centerLng != nil {
            return "\(dateStr) 位置"
        }
        
        // 默认：日期 + 照片数量
        return "\(dateStr) (\(photos.count)张)"
    }
    
    /// 计算两点间距离（米）
    private static func distanceBetween(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }
}
