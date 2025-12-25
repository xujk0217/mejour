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

    /// 重新拉取缺少的 display name（需已登入）
    func refreshDisplayNamesIfNeeded() async {
        guard let token = AuthManager.shared.accessToken, !token.isEmpty else { return }
        let base = URL(string: "https://meejing-backend.vercel.app")!

        var updated = friends
        var changed = false

        for idx in updated.indices {
            let friend = updated[idx]
            if let name = friend.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            var req = URLRequest(url: base.appendingPathComponent("/api/users/\(friend.userId)/"))
            req.httpMethod = "GET"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let user = try? JSONDecoder().decode(APIUserBrief.self, from: data) {
                    updated[idx].displayName = user.displayName
                    changed = true
                }
            } catch {
                continue
            }
        }

        if changed {
            friends = updated
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
