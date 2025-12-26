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
    let detentSelection: Binding<PresentationDetent>?

    init(
        place: Place,
        mode: PlaceSheetMode = .normal,
        detentSelection: Binding<PresentationDetent>? = nil
    ) {
        self.place = place
        self.mode = mode
        self.detentSelection = detentSelection
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
        let parsed = PostContent.parse(log.content)
        let tags = parsed.tags
        let typeColor = place.type.color
        let displayDate = parsed.photoTakenTime ?? log.createdAt

        return NavigationLink {
            LogDetailView(postId: log.serverId)
                .environmentObject(vm)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                logPhotoSquare(log)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.title)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(formatDate(displayDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        let total = log.likeCount + log.dislikeCount
                        let diff = log.likeCount - log.dislikeCount
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(.orange)
                                Text("\(total)")
                                    .font(.subheadline).bold()
                            }
                            Text("(\(diff >= 0 ? "+" : "")\(diff))")
                                .font(.caption)
                                .foregroundStyle(diff >= 0 ? .green : .red)
                        }
                    }

                    HStack(spacing: 8) {
                        authorAvatar(log.authorName)
                        Text(log.authorName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
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

                    if !tags.isEmpty {
                        TagPills(tags: tags, tint: typeColor)
                    }
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(typeColor.opacity(0.35), lineWidth: 1)
            )
            .frame(height: 130, alignment: .center)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            detentSelection?.wrappedValue = .large
        })
    }

    @ViewBuilder
    private func logPhotoSquare(_ log: LogItem) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial)
                    ProgressView()
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func authorAvatar(_ name: String) -> some View {
        let initial = name.first.map { String($0) } ?? "?"
        return Text(initial)
            .font(.caption.bold())
            .frame(width: 28, height: 28)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().stroke(.white.opacity(0.18)))
    }

    private struct TagPills: View {
        let tags: [String]
        let tint: Color

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(tint.opacity(0.15))
                            .foregroundStyle(tint)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
                    }
                }
            }
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

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: now)
        
        // 不超過1分鐘
        if components.minute! < 1 && components.hour! == 0 && components.day! == 0 {
            return "剛剛"
        }
        // 不超過1小時
        if components.hour! < 1 && components.day! == 0 {
            return "\(components.minute!)分鐘前"
        }
        // 不超過24小時
        if components.day! < 1 {
            return "\(components.hour!)小時前"
        }
        // 不超過7天
        if components.day! < 7 {
            return "\(components.day!)天前"
        }
        
        // 超過7天，顯示完整日期
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.string(from: date)
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
