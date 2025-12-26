//
//  FriendProfileView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/20.
//

import SwiftUI
import MapKit
import CoreLocation

struct FriendProfileView: View {
    let userId: Int

    @EnvironmentObject private var vm: MapViewModel
    @ObservedObject private var follow = FollowStore.shared   // ✅ 用 ObservedObject 看 ids 變化即可

    enum Tab: String, CaseIterable, Identifiable {
        case posts = "貼文"
        case map = "個人地圖"
        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .posts
    @State private var friendPosts: [LogItem] = []
    @State private var exploredPlaceIds: Set<Int> = []
    @State private var isLoading = false
    @State private var errorText: String?

    // ✅ 統一判斷：是否已追蹤
    private var isFollowed: Bool {
        follow.ids.contains(userId)
    }

    // ✅ 是否是自己
    private var isMe: Bool {
        AuthManager.shared.currentUser?.id == userId
    }
    
    // ✅ 好友的顯示名稱（優先使用 local cache）
    private var friendDisplayName: String {
        if let f = follow.friend(for: userId), let name = f.displayName, !name.isEmpty {
            return name
        }
        return "User #\(userId)"
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            tabBar
            tabContent
        }
        .padding()
        .navigationTitle("好友")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFriend() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {

            HStack {
                Spacer()

                if isMe {
                    Text("這是你自己")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    followButton
                }
            }

            // 好友頭像（使用 emoji）
            let friend = follow.friend(for: userId)
            Text(FriendAvatarPool.emoji(for: friend?.avatarId))
                .font(.system(size: 48))
                .frame(width: 72, height: 72)
                .background(.thinMaterial, in: Circle())

            HStack(spacing: 8) {
                Text(friendDisplayName)
                    .font(.headline)

                if isFollowed {
                    followedBadge
                }
            }
            
            Text("ID: \(userId)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                statItem(title: "探索地點", value: "\(friendExploredPlaces.count)")
                statItem(title: "貼文", value: "\(friendPosts.count)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var followButton: some View {
        Button {
            if isFollowed {
                follow.remove(userId)     // ✅ 明確呼叫 remove
            } else {
                follow.add(userId)        // ✅ 明確呼叫 add
            }
        } label: {
            Text(isFollowed ? "取消追蹤" : "追蹤")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(isFollowed ? .gray : .accentColor)
        .disabled(userId <= 0)
    }

    private var followedBadge: some View {
        Text("已追蹤")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = (selectedTab == tab)

        return Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12).fill(.thinMaterial)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.clear)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(isSelected ? 0.22 : 0.10))
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView("載入中…")
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        } else if let errorText, !errorText.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.caption)
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        } else {
            switch selectedTab {
            case .posts:
                friendPostsView
            case .map:
                friendMapView
            }
        }
    }

    private var friendPostsView: some View {
        Group {
            if friendPosts.isEmpty {
                VStack(spacing: 12) {
                    Text("對方目前沒有發布任何貼文")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 80)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(friendPosts) { post in
                            NavigationLink {
                                LogDetailView(postId: post.serverId)
                                    .environmentObject(vm)
                            } label: {
                                postRow(post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func postRow(_ log: LogItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(log.title).font(.headline)

            Text(log.displayContent)
                .lineLimit(2)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("\(log.likeCount)", systemImage: "hand.thumbsup")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(log.dislikeCount)", systemImage: "hand.thumbsdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.14))
        )
    }

    private var friendMapView: some View {
        Group {
            if friendExploredPlaces.isEmpty {
                VStack(spacing: 12) {
                    Text("對方還沒有留下探索過的地點")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 80)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Map(position: .constant(.automatic)) {
                        ForEach(showableFriendPlaces, id: \.id) { place in
                            Annotation(place.name, coordinate: place.coordinate.cl) {
                                GlassPin(icon: place.type.iconName, color: place.type.color)
                            }
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))

                    List {
                        ForEach(showableFriendPlaces, id: \.id) { p in
                            NavigationLink {
                                PlaceSheetView(place: p, mode: .onlyUser(userId: userId))
                                    .environmentObject(vm)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: p.type.iconName)
                                        .foregroundStyle(p.type.color)
                                    VStack(alignment: .leading) {
                                        Text(p.name).font(.headline)
                                        if !p.tags.isEmpty {
                                            Text(p.tags.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 260)
                }
            }
        }
    }

    // MARK: - Derived Places

    private var friendExploredPlaces: [Place] {
        let ids = exploredPlaceIds
        guard !ids.isEmpty else { return [] }

        var index: [Int: Place] = [:]
        for p in vm.communityPlaces {
            if index[p.serverId] == nil {
                index[p.serverId] = p
            }
        }
        return ids.compactMap { index[$0] }
    }

    private var showableFriendPlaces: [Place] {
        friendExploredPlaces.filter { $0.serverId > 0 }
    }

    // MARK: - Load

    @MainActor
    private func loadFriend() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        guard AuthManager.shared.isAuthenticated else {
            errorText = "請先登入後再查看好友"
            return
        }

        let posts = await PostsManager.shared.fetchPostsByUser(userId: userId)
        friendPosts = posts
        exploredPlaceIds = Set(posts.map(\.placeServerId))

        // ✅ 丟進 vm cache（PlaceSheetView.onlyUser 會用）
        vm.setUserPostsCache(userId: userId, posts: posts)
    }
}
