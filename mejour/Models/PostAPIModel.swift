//
//  APIUserBrief.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//


import Foundation

struct APIUserBrief: Codable {
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

struct APIPost: Codable {
    let id: Int
    let uuid: String
    let place: APIPlace
    let author: APIUserBrief
    let title: String
    let body: String
    let visibility: APIVisibility
    let createdAt: String
    let updatedAt: String
    let photo: String?
    let likeCount: Int
    let dislikeCount: Int

    enum CodingKeys: String, CodingKey {
        case id, uuid, place, author, title, body, visibility, photo
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case likeCount = "like_count"
        case dislikeCount = "dislike_count"
    }
}
