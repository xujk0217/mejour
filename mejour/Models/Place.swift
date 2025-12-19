//
//  PlaceUser.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//


import Foundation

// MARK: - API Models (Places)

enum APIVisibility: String, Codable {
    case `public`
    case `private`
}

// created_by 使用者
struct APIPlaceUser: Codable {
    let id: Int
    let uuid: String
    let username: String
    let displayName: String
    let profileVisibility: String
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id, uuid, username, avatar
        case displayName = "display_name"
        case profileVisibility = "profile_visibility"
    }
}

// Place
struct APIPlace: Codable {
    let id: Int
    let uuid: String
    let name: String
    let description: String?
    let latitude: String
    let longitude: String
    let visibility: APIVisibility
    let createdBy: APIPlaceUser
    let metadata: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, latitude, longitude, visibility, metadata
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Pagination
struct APIPaginated<T: Codable>: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [T]
}

// POST body
struct APICreatePlaceRequest: Codable {
    let name: String
    let description: String
    let latitude: String
    let longitude: String
    let visibility: APIVisibility
    let metadata: String
}
