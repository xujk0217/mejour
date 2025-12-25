//
//  FriendsListView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/25.
//

import SwiftUI

struct FriendsListView: View {
    @ObservedObject private var follow = FollowStore.shared
    @ObservedObject private var auth = AuthManager.shared
    
    @State private var followIdText = ""
    @State private var followError: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // 新增好友
                Section("新增好友") {
                    HStack(spacing: 8) {
                        TextField("輸入 userId（Int）", text: $followIdText)
                            .keyboardType(.numberPad)
                        Button("追蹤") {
                            Task { await submitFollow() }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let followError, !followError.isEmpty {
                        Text(followError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // 好友列表
                Section("我的好友") {
                    if follow.friends.isEmpty {
                        Text("你還沒有追蹤任何好友")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(follow.friends) { friend in
                            NavigationLink {
                                // FriendsListView is presented from RootMapView with environmentObject(vm), so
                                // FriendProfileView will inherit MapViewModel when available. To be safe we still
                                // present FriendProfileView directly here.
                                FriendProfileView(userId: friend.userId)
                            } label: {
                                HStack(spacing: 12) {
                                    // 頭像 emoji
                                    Text(FriendAvatarPool.emoji(for: friend.avatarId))
                                        .font(.title3)
                                        .frame(width: 40, height: 40)
                                        .background(.thinMaterial, in: Circle())
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName ?? "User #\(friend.userId)")
                                            .fontWeight(.semibold)
                                        Text("ID: \(friend.userId)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                        }
                        .onDelete(perform: deleteFollows)
                    }
                }
            }
            .navigationTitle("好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await follow.refreshDisplayNamesIfNeeded()
            }
        }
    }
    
    private func submitFollow() async {
        followError = nil
        let t = followIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(t), id > 0 else {
            followError = "userId 必須是正整數"
            return
        }

        // 嘗試透過後端 user API 取得較正式的 user 資訊（若後端支援）
        var displayName: String? = nil
        if let token = AuthManager.shared.accessToken, !token.isEmpty {
            let base = URL(string: "https://meejing-backend.vercel.app")!
            let url = base.appendingPathComponent("/api/users/\(id)/")
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if let u = try? JSONDecoder().decode(APIUserBrief.self, from: data) {
                        displayName = u.displayName
                    }
                }
            } catch {
                // 忽略錯誤，稍後 fallback 到 posts-based name
            }
        }

        // fallback：若 user API 沒有回傳，再用 posts 的 authorName
        if displayName == nil {
            let posts = await PostsManager.shared.fetchPostsByUser(userId: id)
            displayName = posts.first?.authorName
        }

        follow.add(id, displayName: displayName)
        followIdText = ""
    }
    
    private func deleteFollows(_ indexSet: IndexSet) {
        for i in indexSet {
            follow.remove(follow.friends[i].userId)
        }
    }
}

#Preview {
    FriendsListView()
}
