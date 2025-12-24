//
//  Friend.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/25.
//

import Foundation

/// 好友模型：儲存 userId + 本地頭像 id
struct Friend: Codable, Identifiable, Hashable {
    let userId: Int
    var avatarId: Int? // 本地隨機頭像 id（1-12）
    var displayName: String?

    var id: Int { userId }
}

/// 頭像池：提供隨機可選擇的預設頭像
struct FriendAvatarPool {
    static let avatars = [
        (id: 1, emoji: "😊"),
        (id: 2, emoji: "😎"),
        (id: 3, emoji: "🤗"),
        (id: 4, emoji: "😄"),
        (id: 5, emoji: "🥳"),
        (id: 6, emoji: "😍"),
        (id: 7, emoji: "😌"),
        (id: 8, emoji: "😇"),
        (id: 9, emoji: "🤔"),
        (id: 10, emoji: "😎"),
        (id: 11, emoji: "🌟"),
        (id: 12, emoji: "🎯"),
    ]
    
    static func randomAvatarId() -> Int {
        avatars.randomElement()?.id ?? 1
    }
    
    static func emoji(for id: Int?) -> String {
        guard let id = id else { return "👤" }
        return avatars.first(where: { $0.id == id })?.emoji ?? "👤"
    }
}
