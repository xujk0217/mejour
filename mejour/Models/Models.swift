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

struct AuthResponse: Codable {
    let refresh: String
    let access: String
}

struct MeUser: Codable, Identifiable {
    let id: Int
    let uuid: String
    let username: String
    let email: String
    let displayName: String
    let avatar: String?
    let profileVisibility: String

    enum CodingKeys: String, CodingKey {
        case id, uuid, username, email, avatar
        case displayName = "display_name"
        case profileVisibility = "profile_visibility"
    }
}

struct Place: Identifiable, Codable, Hashable {
    // local
    let id: UUID

    // server
    let serverId: Int

    // display
    var name: String
    var type: PlaceType
    var tags: [String]
    var coordinate: CLCodable
    var isPublic: Bool
    var ownerId: UUID

    var origin: PlaceOrigin = .user
    var applePlaceId: String? = nil
}

struct CLCodable: Codable, Hashable, Equatable {
    var latitude: Double
    var longitude: Double
    init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    init(_ coord: CLLocationCoordinate2D) { self.latitude = coord.latitude; self.longitude = coord.longitude }
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// ✅ 正式版：LogItem 只處理「後端 post」
struct LogItem: Identifiable, Codable, Hashable {
    // server identity
    let serverId: Int
    let uuid: String?

    // relations (server ids)
    let placeServerId: Int
    let authorServerId: Int
    let authorUUID: String?   // 可選：debug / 之後要做 profile link 也方便

    // display
    var authorName: String
    var title: String
    var content: String
    var isPublic: Bool
    var createdAt: Date
    var likeCount: Int
    var dislikeCount: Int
    var photoURL: String?

    // SwiftUI identity
    var id: Int { serverId }
    
    // 計算屬性：從 content 中提取拍攝時間
    var photoTakenTime: Date? {
        PostContent.parse(content).photoTakenTime
    }
    
    // 計算屬性：返回不含時間標記的純文本內容
    var displayContent: String {
        PostContent.parse(content).text
    }
}

struct CommentItem: Identifiable, Codable, Hashable {
    // ✅ 建議跟後端一致：用 Int
    let serverId: Int
    let postServerId: Int
    let authorServerId: Int
    var content: String
    var createdAt: Date

    var id: Int { serverId }
}

// MARK: - Mapping

extension Place {
    init?(api: APIPlace) {
        guard
            let placeUUID = UUID(uuidString: api.uuid),
            let ownerUUID = UUID(uuidString: api.createdBy.uuid),
            let lat = Double(api.latitude),
            let lon = Double(api.longitude)
        else { return nil }

        let meta = PlaceMetadataCodec.decode(api.metadata)
        let mappedType: PlaceType = meta?.type ?? .other
        let mappedTags: [String] = meta?.tags ?? []

        self.id = placeUUID
        self.serverId = api.id

        self.name = api.name
        self.type = mappedType
        self.tags = mappedTags
        self.coordinate = CLCodable(latitude: lat, longitude: lon)
        self.isPublic = (api.visibility == .public)
        self.ownerId = ownerUUID
        self.origin = .user
        self.applePlaceId = nil
    }
}

extension LogItem {
    init?(api: APIPost) {
        // ✅ 正式版：不要因為 uuid 壞掉就整筆丟掉
        // serverId / place.id / author.id 這些是必要的
        self.serverId = api.id
        self.uuid = api.uuid

        self.placeServerId = api.place.id
        self.authorServerId = api.author.id
        self.authorUUID = api.author.uuid

        self.authorName = api.author.displayName
        self.title = api.title
        self.content = api.body
        self.photoURL = api.photo
        self.isPublic = (api.visibility == .public)

        // createdAt 解析
        self.createdAt = ISO8601DateFormatter().date(from: api.createdAt) ?? .now

        self.likeCount = api.likeCount
        self.dislikeCount = api.dislikeCount
    }
}
