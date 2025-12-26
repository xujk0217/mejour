//
//  FollowStore.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/20.
//

import Foundation
import Combine

@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()

    @Published private(set) var friends: [Friend] = []

    private let key = "follow.friends"
    private let base = URL(string: "https://meejing-backend.vercel.app")!
    private var tokenCancellable: AnyCancellable?

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

        // 初始化時先嘗試補正式 display name（若 token 已存在）
        Task { await refreshDisplayNamesIfNeeded() }

        // 監聽 token 變化後補拉正式 display name（預設好友也會更新）
        tokenCancellable = AuthManager.shared.$accessToken
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshDisplayNamesIfNeeded() }
            }
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
        var updated = friends
        var changed = false

        for idx in updated.indices {
            guard needsDisplayNameFetch(for: updated[idx]) else { continue }

            if let name = await resolveDisplayName(for: updated[idx].userId) {
                updated[idx].displayName = name
                changed = true
            }
        }

        if changed {
            friends = updated
            persist()
        }
    }

    private func needsDisplayNameFetch(for friend: Friend) -> Bool {
        let trimmed = (friend.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        // 預設假資料或舊版 fallback 視為缺少正式名稱
        let placeholders = [
            "好友\(friend.userId)",
            "好友#\(friend.userId)",
            "User #\(friend.userId)"
        ]
        let lower = trimmed.lowercased()

        if placeholders.contains(where: { $0.lowercased() == lower }) {
            return true
        }

        // 其他泛用占位格式
        let patterns = ["^好友#?\\d+$", "^user #?\\d+$", "^friend #?\\d+$"]
        if patterns.contains(where: { lower.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        return false
    }

    private func resolveDisplayName(for userId: Int) async -> String? {
        let token = AuthManager.shared.accessToken

        // 優先用 user API（需 token）
        if let token, !token.isEmpty, let fromAPI = await fetchDisplayNameViaAPI(userId: userId, token: token) {
            return fromAPI
        }

        // 後備：抓該使用者貼文的 authorName（需要後端允許）
        let posts = await PostsManager.shared.fetchPostsByUser(userId: userId)
        return posts.first?.authorName
    }

    private func fetchDisplayNameViaAPI(userId: Int, token: String) async -> String? {
        var req = URLRequest(url: base.appendingPathComponent("/api/users/\(userId)/"))
        req.httpMethod = "GET"
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let user = try? JSONDecoder().decode(APIUserBrief.self, from: data) {
                return user.displayName
            }
        } catch { }

        return nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
