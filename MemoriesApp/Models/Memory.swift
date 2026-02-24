//
//  Memory.swift
//  MemoriesApp
//

import Foundation
import SwiftData

@Model
final class Memory: Identifiable {
    var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var locationName: String
    var note: String
    var assetLocalIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double = 0,
        longitude: Double = 0,
        locationName: String = "",
        note: String = "",
        assetLocalIds: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.note = note
        self.assetLocalIds = assetLocalIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
