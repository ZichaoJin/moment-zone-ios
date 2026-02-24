//
//  Photo.swift
//  MemoriesApp
//

import Foundation
import SwiftData
import CoreLocation

enum StoryCategory: String, CaseIterable, Codable {
    case love
    case friendship
    case birthday
    case travel
    case milestone
    case daily

    var title: String {
        switch self {
        case .love: return "爱情"
        case .friendship: return "友情"
        case .birthday: return "生日"
        case .travel: return "旅行"
        case .milestone: return "人生经历"
        case .daily: return "日常"
        }
    }

    var symbolName: String {
        switch self {
        case .love: return "heart.fill"
        case .friendship: return "person.2.fill"
        case .birthday: return "birthday.cake.fill"
        case .travel: return "airplane"
        case .milestone: return "sparkles"
        case .daily: return "sun.max.fill"
        }
    }
}

/// Photo - 原子单位：唯一真实的数据（时间+地点+照片ID+可选文字）
@Model
final class Photo: Identifiable {
    var id: UUID
    var assetLocalId: String      // Photos 的 localIdentifier（不占 App 空间）
    var timestamp: Date           // 拍摄时间（从 EXIF）
    var latitude: Double          // GPS（从 EXIF，可手动覆盖）
    var longitude: Double
    var manualLocationName: String?  // 手动添加的地点名称（解决无GPS）
    var cachedLocationName: String?  // 从坐标反地理编码缓存，用于展示（有坐标但未手动命名时）
    var note: String?             // Photo Note（照片级备注，很细的瞬间）
    var deletedAt: Date?          // 软删除：非 nil 表示在垃圾箱
    
    /// 所属 Event（同一 Story 内按时间/地点分组，用于事件备注）
    var eventId: UUID?
    
    // 多对多关系：一张 Photo 可以属于多个 Collection
    @Relationship(deleteRule: .nullify, inverse: \Collection.photos)
    var collections: [Collection] = []
    
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        assetLocalId: String,
        timestamp: Date = Date(),
        latitude: Double = 0,
        longitude: Double = 0,
        manualLocationName: String? = nil,
        cachedLocationName: String? = nil,
        note: String? = nil,
        eventId: UUID? = nil,
        deletedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assetLocalId = assetLocalId
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.manualLocationName = manualLocationName
        self.cachedLocationName = cachedLocationName
        self.note = note
        self.eventId = eventId
        self.deletedAt = deletedAt
        self.collections = []
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 获取坐标（如果有）
    var coordinate: CLLocationCoordinate2D? {
        guard latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// 展示用地点名称：优先手动，否则用反地理编码缓存，避免显示「未知地点」
    var displayLocationName: String {
        if let manual = manualLocationName, !manual.isEmpty { return manual }
        if let cached = cachedLocationName, !cached.isEmpty { return cached }
        return ""
    }
}

/// Collection - 回忆集合：一种"章节/集合"，可以是系统自动生成（auto）也可以是用户自己讲故事（story）
@Model
final class Collection: Identifiable {
    var id: UUID
    var title: String              // 集合标题（自动生成或手动）
    var note: String?              // Collection Note（集合级备注，如"第一次旅行"）
    var type: CollectionType       // auto / story
    var storyCategoryRaw: String = StoryCategory.daily.rawValue
    var startTime: Date?           // 可选时间范围
    var endTime: Date?
    var centerLatitude: Double?    // 中心坐标（可选，用于地图定位）
    var centerLongitude: Double?
    var coverAssetId: String?      // 封面照片的 assetLocalId
    
    // 多对多关系：一个 Collection 可以包含很多 Photo（inverse 在 Photo 中定义）
    var photos: [Photo] = []
    
    /// Story 下的 Event 列表（旅程节点：时间 + 地点 + 事件备注）
    @Relationship(deleteRule: .cascade, inverse: \Event.collection)
    var events: [Event] = []
    
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?  // 软删除：非 nil 表示在垃圾箱
    
    enum CollectionType: String, Codable {
        case auto   // 自动生成的事件块
        case story  // 用户创建的故事章节
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        type: CollectionType,
        storyCategoryRaw: String = StoryCategory.daily.rawValue,
        startTime: Date? = nil,
        endTime: Date? = nil,
        centerLatitude: Double? = nil,
        centerLongitude: Double? = nil,
        coverAssetId: String? = nil,
        deletedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.type = type
        self.storyCategoryRaw = storyCategoryRaw
        self.startTime = startTime
        self.endTime = endTime
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.coverAssetId = coverAssetId
        self.photos = []
        self.events = []
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 获取中心坐标（如果有）
    var centerCoordinate: CLLocationCoordinate2D? {
        guard let lat = centerLatitude, let lng = centerLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    /// 获取时间范围（如果有）
    var timeRange: DateInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return DateInterval(start: start, end: end)
    }

    var storyCategory: StoryCategory {
        get { StoryCategory(rawValue: storyCategoryRaw) ?? .daily }
        set { storyCategoryRaw = newValue.rawValue }
    }
    
}

/// Event - Story 内的一个节点：某段时间 + 地点 + 事件备注（可包含多张照片）
@Model
final class Event: Identifiable {
    var id: UUID
    var note: String?
    var startTime: Date
    var endTime: Date?
    var locationName: String?
    
    /// 所属 Story（inverse 由 Collection.events 的 @Relationship 定义）
    var collection: Collection?
    
    init(
        id: UUID = UUID(),
        note: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        locationName: String? = nil
    ) {
        self.id = id
        self.note = note
        self.startTime = startTime
        self.endTime = endTime
        self.locationName = locationName
    }
}
