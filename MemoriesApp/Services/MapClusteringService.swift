//
//  MapClusteringService.swift
//  MemoriesApp
//

import Foundation
import MapKit
import CoreLocation

/// 地图层级聚合服务：根据 zoom level 自动聚合照片
enum MapClusteringService {
    /// 聚合点：包含位置和照片数量
    struct Cluster: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let photoCount: Int
        let photos: [Photo]
        let label: String  // 显示标签，如 "USA 128" / "Pittsburgh 32"
    }
    
    /// 根据地图的 zoom level（通过 span 计算）聚合照片
    /// - Parameters:
    ///   - photos: 要聚合的照片列表
    ///   - mapSpan: 地图当前的 span（latitudeDelta, longitudeDelta）
    ///   - visibleRegion: 地图当前可见区域（可选，用于优化）
    /// - Returns: 聚合点列表
    static func clusterPhotos(
        _ photos: [Photo],
        mapSpan: MKCoordinateSpan,
        visibleRegion: MKCoordinateRegion? = nil
    ) -> [Cluster] {
        let photosWithLocation = photos.compactMap { photo -> (Photo, CLLocationCoordinate2D)? in
            guard let coord = photo.coordinate else { return nil }
            return (photo, coord)
        }
        
        guard !photosWithLocation.isEmpty else { return [] }
        
        // 根据 span 计算聚类距离阈值（连续公式，更平滑）
        // 1° 纬度 ≈ 111km，用 span 换算为真实距离
        // 聚合阈值 = span 对应实际距离的 ~12%，确保屏幕上近距离的点会合并
        let avgSpan = (mapSpan.latitudeDelta + mapSpan.longitudeDelta) / 2
        let clusterDistance: Double

        if avgSpan < 0.0045 {
            // 更近的 zoom 保持单点，降低“误合并”
            clusterDistance = 0
        } else {
            // 连续公式：avgSpan 度 × 111km/度 × 0.08（降低合并敏感度）
            clusterDistance = avgSpan * 111_000 * 0.08
        }
        
        // 如果不需要聚合（clusterDistance = 0），直接返回每个照片一个点
        if clusterDistance == 0 {
            return photosWithLocation.map { photo, coord in
                Cluster(
                    id: makeClusterId(from: [photo]),
                    coordinate: coord,
                    photoCount: 1,
                    photos: [photo],
                    label: generateLabel(for: [photo], at: coord)
                )
            }
        }
        
        // 执行聚类算法（两遍：先聚，再合并近距离的簇）
        var clusters: [Cluster] = []
        var processed = Set<UUID>()

        for (photo, coord) in photosWithLocation {
            if processed.contains(photo.id) { continue }

            // 找到这个照片附近的所有照片
            var nearbyPhotos: [(Photo, CLLocationCoordinate2D)] = [(photo, coord)]
            processed.insert(photo.id)

            for (otherPhoto, otherCoord) in photosWithLocation {
                if processed.contains(otherPhoto.id) { continue }

                let distance = distanceBetween(coord, otherCoord)
                if distance <= clusterDistance {
                    nearbyPhotos.append((otherPhoto, otherCoord))
                    processed.insert(otherPhoto.id)
                }
            }

            let avgLat = nearbyPhotos.map { $0.1.latitude }.reduce(0, +) / Double(nearbyPhotos.count)
            let avgLng = nearbyPhotos.map { $0.1.longitude }.reduce(0, +) / Double(nearbyPhotos.count)
            let centerCoord = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng)
            let label = generateLabel(for: nearbyPhotos.map { $0.0 }, at: centerCoord)

            clusters.append(Cluster(
                id: makeClusterId(from: nearbyPhotos.map { $0.0 }),
                coordinate: centerCoord,
                photoCount: nearbyPhotos.count,
                photos: nearbyPhotos.map { $0.0 },
                label: label
            ))
        }

        // 第二遍：只做更保守的簇合并，避免过度吞并邻近 batch
        clusters = mergeClusters(clusters, threshold: clusterDistance * 0.75)
        
        return clusters
    }
    
    /// 合并中心距离小于阈值的簇
    private static func mergeClusters(_ input: [Cluster], threshold: Double) -> [Cluster] {
        guard threshold > 0 else { return input }
        var result = input
        var merged = true
        while merged {
            merged = false
            var i = 0
            while i < result.count {
                var j = i + 1
                while j < result.count {
                    if distanceBetween(result[i].coordinate, result[j].coordinate) <= threshold {
                        // 合并 j 到 i
                        let allPhotos = result[i].photos + result[j].photos
                        let allCoords = allPhotos.compactMap { $0.coordinate }
                        let avgLat = allCoords.map(\.latitude).reduce(0, +) / Double(allCoords.count)
                        let avgLng = allCoords.map(\.longitude).reduce(0, +) / Double(allCoords.count)
                        let center = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng)
                        result[i] = Cluster(
                            id: makeClusterId(from: allPhotos),
                            coordinate: center,
                            photoCount: allPhotos.count,
                            photos: allPhotos,
                            label: generateLabel(for: allPhotos, at: center)
                        )
                        result.remove(at: j)
                        merged = true
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }
        return result
    }

    /// 生成聚合点标签（如 "USA 128" / "Pittsburgh 32"）
    private static func generateLabel(for photos: [Photo], at coordinate: CLLocationCoordinate2D) -> String {
        // 优先使用照片的手动地点名称
        let locationNames = photos.compactMap { $0.manualLocationName }.filter { !$0.isEmpty }
        
        if let mostCommonName = locationNames.mostCommon {
            return "\(mostCommonName) \(photos.count)"
        }
        
        // 无统一地点名时只显示数量，不再用「位置 N」
        return "\(photos.count) 张照片"
    }
    
    /// 计算两点间距离（米）
    private static func distanceBetween(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }

    /// 聚合点稳定 ID：由包含照片的 UUID 集合生成，避免高亮切换时其它点闪烁
    private static func makeClusterId(from photos: [Photo]) -> String {
        photos
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: "|")
    }
}

// 扩展：找到数组中最常见的元素
extension Array where Element: Hashable {
    var mostCommon: Element? {
        let counts = Dictionary(grouping: self, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
