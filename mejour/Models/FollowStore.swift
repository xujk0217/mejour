//
//  FollowStore.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/20.
//

import Foundation

@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()

    @Published private(set) var friends: [Friend] = []

    private let key = "follow.friends"

    private init() {
        // Try to decode Friend array
        if let data = UserDefaults.standard.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
                self.friends = decoded
                return
            }
        }
        // 沒有舊資料時，預設幾個好友
        let defaults = [10, 11, 12, 13].map {
            Friend(userId: $0, avatarId: FriendAvatarPool.randomAvatarId(), displayName: "好友\($0)")
        }
        self.friends = defaults
        persist()
    }

    func add(_ userId: Int, displayName: String? = nil) {
        guard userId > 0 else { return }
        if !friends.contains(where: { $0.userId == userId }) {
            let avatarId = FriendAvatarPool.randomAvatarId()
            friends.append(Friend(userId: userId, avatarId: avatarId, displayName: displayName))
            persist()
        }
    }

    func remove(_ userId: Int) {
        friends.removeAll { $0.userId == userId }
        persist()
    }

    func contains(_ userId: Int) -> Bool {
        friends.contains(where: { $0.userId == userId })
    }
    
    func friend(for userId: Int) -> Friend? {
        friends.first(where: { $0.userId == userId })
    }
    
    var ids: [Int] { friends.map(\.userId) }

    private func persist() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
