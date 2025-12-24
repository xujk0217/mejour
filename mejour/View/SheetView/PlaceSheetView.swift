//
//  PlaceSheetView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//

//
//  PlaceSheetView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//

import SwiftUI

enum PlaceSheetMode: Equatable {
    case normal                 // 地點頁（社群）：用 by-place 顯示公開貼文
    case onlyMine               // 個人地圖：只顯示我的貼文（by-user 推導）
    case onlyUser(userId: Int)  // 好友個人地圖：只顯示該 user 貼文（by-user 推導）
}

struct PlaceSheetView: View {
    let place: Place
    let mode: PlaceSheetMode

    init(place: Place, mode: PlaceSheetMode = .normal) {
        self.place = place
        self.mode = mode
    }

    @EnvironmentObject private var vm: MapViewModel
    @ObservedObject private var follow = FollowStore.shared

    @State private var logs: [LogItem] = []
    @State private var showEdit = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("地點資訊")
                .navigationBarTitleDisplayMode(.inline)
                .task { await loadLogs() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider().opacity(0.2)

                if isLoading {
                    ProgressView("載入中…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if logs.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(logs) { log in
                            logRow(log)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .normal:
            return "目前沒有公開日誌"
        case .onlyMine:
            return "你在這個地點還沒有發布日誌"
        case .onlyUser:
            return "對方在這個地點還沒有發布日誌"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                GlassPin(icon: place.type.iconName, color: place.type.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(.headline)
                    if place.tags.isEmpty {
                        Text("無標籤")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }

                Spacer()

                // 個人/好友地圖一般不給編輯
                if mode == .normal {
                    Button { showEdit = true } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showEdit) {
                        EditPlaceSheet(place: place) { updated in
                            // ✅ 用 EnvironmentObject 的 backing wrapper 取出真正的物件
                            _vm.wrappedValue.updatePlace(updated)
                        }
                        .environmentObject(vm)
                    }
                }
            }

            if !place.tags.isEmpty {
                ChipsGrid(items: place.tags, removable: false, onTap: { _ in })
            }
        }
    }

    private func logRow(_ log: LogItem) -> some View {
        let myId = AuthManager.shared.currentUser?.id
        let isMe = (myId == log.authorServerId)

        // ✅ FollowStore 沒 isFollowing，就用 contains
        let isFollowed = (!isMe) && follow.contains(log.authorServerId)

        return VStack(alignment: .leading, spacing: 8) {
            Text(log.title).font(.headline)

            NavigationLink {
                FriendProfileView(userId: log.authorServerId)
                    .environmentObject(vm)
            } label: {
                HStack(spacing: 8) {
                    Text("by \(log.authorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isFollowed {
                        Text("已追蹤")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.18)))
                    }
                }
            }
            .buttonStyle(.plain)

            logPhotoPreview(log)

            Text(log.content)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                // ✅ 不要用舊的 platformButtonStyle，避免你專案裡衝突
                Label("\(log.likeCount)", systemImage: "hand.thumbsup")
                    .buttonStyle(.bordered)

                NavigationLink {
                    LogDetailView(postId: log.serverId)
                } label: {
                    Label("查看全文", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func logPhotoPreview(_ log: LogItem) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } placeholder: {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thinMaterial)
                    .frame(height: 220)
                    .overlay(ProgressView())
            }
        } else {
            EmptyView()
        }
    }

    @MainActor
    private func loadLogs() async {
        isLoading = true
        defer { isLoading = false }

        switch mode {
        case .normal:
            // 社群地點頁：by-place（使用快取，非必要不強制 reload）
            await vm.loadPosts(for: place) // 內部已檢查快取
            logs = vm.logsByPlace[place.serverId] ?? []

        case .onlyMine:
            // 個人地圖：優先使用 vm.myPosts 快取，若為空則按需載入一次
            var my = vm.myPostsAtPlace(placeServerId: place.serverId)
            if my.isEmpty {
                await vm.loadMyPostsAndExploredPlaces()
                my = vm.myPostsAtPlace(placeServerId: place.serverId)
            }
            logs = my

        case .onlyUser(let userId):
            // 好友地圖：先用快取，若該 user 尚未快取則只為該 user 取得一次
            var posts = vm.postsOfUserAtPlace(userId: userId, placeServerId: place.serverId)
            let cached = vm.userPostsCache[userId] ?? []
            if cached.isEmpty {
                // 只抓該 user 的貼文，不會影響其他 cache
                let fetched = await PostsManager.shared.fetchPostsByUser(userId: userId)
                vm.setUserPostsCache(userId: userId, posts: fetched)
                posts = vm.postsOfUserAtPlace(userId: userId, placeServerId: place.serverId)
            }
            logs = posts
        }
    }
}

// MARK: - ChipsGrid
private struct ChipsGrid: View {
    let items: [String]
    var removable: Bool
    var onTap: (String) -> Void
    var isSelected: ((String) -> Bool)? = nil

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { tag in
                Button { onTap(tag) } label: {
                    HStack(spacing: 6) {
                        if removable {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                        } else if let isSelected {
                            Image(systemName: isSelected(tag) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(tag).font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension View {
    func platformButtonStyle() -> some View {
        self.buttonStyle(.bordered)
    }
}
