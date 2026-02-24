//
//  PhotoService.swift
//  MemoriesApp
//

import UIKit
import Photos
import CoreLocation

enum PhotoService {
    private static let imageCache = NSCache<NSString, UIImage>()
    private static let imageManager = PHCachingImageManager()

    /// 根据 localIdentifier 加载缩略图，避免加载原图卡顿
    static func loadThumbnail(localIdentifier: String, targetSize: CGSize = CGSize(width: 400, height: 400), completion: @escaping (UIImage?) -> Void) {
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: max(targetSize.width, 1) * scale, height: max(targetSize.height, 1) * scale)
        let cacheKey = "\(localIdentifier)_\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current
        imageManager.requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image {
                    if !isDegraded {
                        imageCache.setObject(image, forKey: cacheKey)
                    }
                }
                completion(image)
            }
        }
    }

    /// 预热图片缓存，降低进入详情/左右翻页时的卡顿
    static func prefetch(localIdentifier: String, targetSize: CGSize = CGSize(width: 400, height: 400)) {
        loadThumbnail(localIdentifier: localIdentifier, targetSize: targetSize) { _ in }
    }

    /// 获取照片的 creationDate（拍摄时间）
    static func creationDate(localIdentifier: String) -> Date? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject?.creationDate
    }
    
    /// 获取照片的拍摄位置（GPS坐标）
    static func location(localIdentifier: String) -> CLLocationCoordinate2D? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject,
              let location = asset.location else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
    
    /// 从照片获取完整信息（时间 + 位置）
    static func photoInfo(localIdentifier: String) -> (date: Date?, location: CLLocationCoordinate2D?) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            return (nil, nil)
        }
        let date = asset.creationDate
        let location = asset.location?.coordinate
        return (date, location)
    }

    /// 生成用于上传的图片数据（压缩后的 JPEG）
    /// - Note: 统一输出中等分辨率，避免上传过大导致 data URI 超限
    static func imageDataForUpload(
        localIdentifier: String,
        maxPixelSize: CGFloat = 1920,
        compressionQuality: CGFloat = 0.86
    ) async -> Data? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return nil }

        let scale = await MainActor.run { UIScreen.main.scale }
        let pixel = max(maxPixelSize * scale, 1)
        let targetSize = CGSize(width: pixel, height: pixel)

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current

        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if resumed { return }

                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    return
                }

                guard let image else {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }

                resumed = true
                continuation.resume(returning: image.jpegData(compressionQuality: compressionQuality))
            }
        }
    }
}
