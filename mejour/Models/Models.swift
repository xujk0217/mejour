//
//  MapScope.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import Foundation
import SwiftUI
import MapKit
import CoreLocation

enum MapScope { case mine, community }

enum PlaceType: String, Codable, CaseIterable, Identifiable {
    case restaurant, cafe, scenic, shop, other
    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer"
        case .scenic: "camera.viewfinder"
        case .shop: "bag"
        case .other: "mappin"
        }
    }
    var color: Color {
        switch self {
        case .restaurant: .red
        case .cafe: .brown
        case .scenic: .green
        case .shop: .blue
        case .other: .gray
        }
    }
}

enum PlaceOrigin: String, Codable { case user, apple }


struct Place: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: PlaceType
    var tags: [String]               // 地點標籤
    var coordinate: CLCodable
    var isPublic: Bool
    var ownerId: UUID
    
    var origin: PlaceOrigin = .user
    var applePlaceId: String? = nil   // Apple Maps Server API 的 Place ID
}

struct CLCodable: Codable, Hashable, Equatable {
    var latitude: Double
    var longitude: Double
    init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    init(_ coord: CLLocationCoordinate2D) { self.latitude = coord.latitude; self.longitude = coord.longitude }
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct LogPhoto: Identifiable, Hashable, Codable {
    let id: UUID = UUID()
    var data: Data                   // 直接存 Data，展示時轉 Image/UIImage
}


struct LogItem: Identifiable, Codable, Hashable {
    let id: UUID
    let placeId: UUID
    let authorId: UUID
    var authorName: String           // 作者顯示名
    var title: String
    var content: String
    var photos: [LogPhoto]           // 多張照片
    var isPublic: Bool
    var createdAt: Date
    var likeCount: Int = 0           // 可加的屬性
    var commentCount: Int = 0
}

struct CommentItem: Identifiable, Codable, Hashable {
    let id: UUID
    let logId: UUID
    let authorId: UUID
    var content: String
    var createdAt: Date
}
