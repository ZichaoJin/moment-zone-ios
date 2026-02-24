//
//  GeocodeService.swift
//  MemoriesApp
//

import Foundation
import CoreLocation

enum GeocodeService {
    /// 反地理编码：坐标 → 地点名称（用于展示）
    static func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            if let name = p.name, !name.isEmpty { return name }
            if let locality = p.locality, let sub = p.subLocality, !sub.isEmpty { return "\(sub), \(locality)" }
            if let locality = p.locality { return locality }
            if let admin = p.administrativeArea { return admin }
            return nil
        } catch {
            return nil
        }
    }
    
    /// 地标/可读名称：优先 POI 名（如 Whole Foods、CMU），否则城市/街区，弱化门牌号
    static func landmarkStyleName(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            
            // 优先：POI 名称（name，通常是建筑/商铺名，如 Whole Foods、Carnegie Mellon University）
            if let name = p.name, !name.isEmpty {
                // 如果 name 不是街道名（thoroughfare），直接返回
                if name != p.thoroughfare {
                    return name
                }
                // 如果 name 是街道名，但还有 areasOfInterest（POI），优先返回 POI
                if let areasOfInterest = p.areasOfInterest, !areasOfInterest.isEmpty {
                    return areasOfInterest.first
                }
            }
            
            // 次优：areasOfInterest（POI 列表，如 ["Whole Foods Market", "CMU"]）
            if let areasOfInterest = p.areasOfInterest, !areasOfInterest.isEmpty {
                return areasOfInterest.first
            }
            
            // 再次：thoroughfare（街道名，避免国内只显示“北京”而无法选街道）
            if let thoroughfare = p.thoroughfare, !thoroughfare.isEmpty {
                if let sub = p.subLocality, !sub.isEmpty, sub != thoroughfare {
                    return "\(thoroughfare), \(sub)"
                }
                return thoroughfare
            }
            
            // 再次：subLocality（街区/区域）
            if let sub = p.subLocality, !sub.isEmpty {
                return sub
            }
            
            // 最后：locality（城市）或其他
            if let locality = p.locality { return locality }
            if let admin = p.administrativeArea { return admin }
            return nil
        } catch {
            return nil
        }
    }
}
