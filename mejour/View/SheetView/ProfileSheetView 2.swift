//
//  ProfileSheetView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//

import SwiftUI

// MARK: - ProfileSheetView
struct ProfileSheetView: View {
    @EnvironmentObject private var vm: MapViewModel

    enum Tab: String, CaseIterable, Identifiable {
        case mine = "我的"
        case liked = "愛心"
        case saved = "收藏"
        var id: String { rawValue }
    }

    @ObservedObject private var auth = AuthManager.shared

    @State private var selectedTab: Tab = .mine

    @State private var myPosts: [LogItem] = []
    @State private var likedPosts: [LogItem] = []
    @State private var savedPosts: [LogItem] = []

    @State private var isLoading = false
    @State private var errorText: String?

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                profileHeader
                tabBar
                contentView
            }
            .padding()
            .navigationTitle("個人頁面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ProfileSettingsView(
                    onNeedAuth: {        // 登出後要跳登入/註冊
                        // 設定頁內會自己顯示 AuthSheetView
                    }
                )
            }
            .task {
                await loadData()
            }
            .onChange(of: auth.isAuthenticated) { _ in
                // 登入狀態變化時重載
                Task { await loadData() }
            }
        }
    }
}

// MARK: - Header
private extension ProfileSheetView {

    var profileHeader: some View {
        VStack(spacing: 12) {
            avatarView

            Text(displayNameText)
                .font(.headline)

            // 顯示使用者 id
            if let me = auth.currentUser {
                Text("ID: \(me.id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                statItem(title: "探索地點", value: placeCountText)
                statItem(title: "發文數", value: "\(myPosts.count)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)))
    }

    var avatarView: some View {
        // 你之後有 avatar URL 可以換 AsyncImage
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .frame(width: 72, height: 72)
            .foregroundStyle(.secondary)
    }

    var displayNameText: String {
        guard let me = auth.currentUser else { return "尚未登入" }
        return me.displayName.isEmpty ? me.username : me.displayName
    }

    func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    var placeCountText: String {
        // 你 LogItem 沒有 placeId(UUID)，用 placeServerId(Int)
        let ids = myPosts.map { $0.placeServerId }
        return "\(Set(ids).count)"
    }
}

// MARK: - Tabs
private extension ProfileSheetView {

    var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.thinMaterial)
                                .opacity(isSelected ? 1 : 0)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(isSelected ? 0.22 : 0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }


    var currentPosts: [LogItem] {
        switch selectedTab {
        case .mine: return myPosts
        case .liked: return likedPosts
        case .saved: return savedPosts
        }
    }

    var emptyMessage: String {
        switch selectedTab {
        case .mine: return auth.isAuthenticated ? "你還沒有發布任何貼文" : "登入後才能看到你的貼文"
        case .liked: return auth.isAuthenticated ? "你現在沒有按愛心的貼文" : "登入後才能看到你按愛心的貼文"
        case .saved: return auth.isAuthenticated ? "你目前沒有收藏的貼文" : "登入後才能看到你收藏的貼文"
        }
    }
}

// MARK: - Content (拆開避免 type-check 爆炸)
private extension ProfileSheetView {

    var contentView: some View {
        Group {
            if isLoading {
                loadingView
            } else if let errorText, !errorText.isEmpty {
                errorView(text: errorText)
            } else if currentPosts.isEmpty {
                emptyView
            } else {
                postListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView("載入中…")
            Spacer(minLength: 80)
        }
    }

    func errorView(text: String) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer(minLength: 80)
        }
    }

    var emptyView: some View {
        VStack(spacing: 12) {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // ✅ 你要的：沒有資料就用 Spacer 讓資訊置頂
            Spacer(minLength: 80)
        }
    }

    var postListView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 我的貼文分組顯示（依日期）
                if selectedTab == .mine {
                    let groups = groupedPosts(myPosts)
                    ForEach(groups.indices, id: \.self) { idx in
                        let group = groups[idx]
                        VStack(alignment: .leading, spacing: 8) {
                            Text(shortDateTitle(group.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 8) {
                                ForEach(group.posts) { post in
                                    NavigationLink {
                                        LogDetailView(postId: post.serverId)
                                            .environmentObject(vm)
                                    } label: {
                                        postRow(post)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(currentPosts) { post in
                        NavigationLink {
                            LogDetailView(postId: post.serverId)
                                .environmentObject(vm)
                        } label: {
                            postRow(post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 8)
        }
        .refreshable {
            await loadData(forceRefresh: true)
        }
    }

    func postRow(_ log: LogItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(log.title)
                .font(.headline)

            // 顯示已移除時間標記的內容
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
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
    }
}

// MARK: - Data
private extension ProfileSheetView {

    @MainActor
    func loadData(forceRefresh: Bool = false) async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        guard let me = auth.currentUser, auth.isAuthenticated else {
            // 未登入：清空資料但不算 error（避免紅字）
            myPosts = []
            likedPosts = []
            savedPosts = []
            return
        }

        // ✅ 我的貼文：你已經有 API
        myPosts = await PostsManager.shared.fetchPostsByUser(userId: me.id, forceRefresh: forceRefresh)

        // ⚠️ 愛心 / 收藏：你目前沒給 API → 先空
        likedPosts = []
        savedPosts = []
    }

    // MARK: - Helpers for grouping and formatting
    func groupedPosts(_ posts: [LogItem]) -> [(date: Date?, posts: [LogItem])] {
        let cal = Calendar.current
        var dict: [Date: [LogItem]] = [:]
        var unknown: [LogItem] = []
        for p in posts {
            // 優先使用 photoTakenTime，再 fallback 到 createdAt；若兩者皆無則歸為 unknown
            if let d = p.photoTakenTime ?? p.createdAt as Date? {
                let key = cal.startOfDay(for: d)
                dict[key, default: []].append(p)
            } else {
                unknown.append(p)
            }
        }
        // sort posts within each day by time desc
        var arr = dict.map { (date: $0.key as Date?, posts: $0.value.sorted { (a, b) in
            let at = a.photoTakenTime ?? a.createdAt
            let bt = b.photoTakenTime ?? b.createdAt
            return at > bt
        }) }
        // sort days desc (non-nil first)
        arr.sort { (l, r) in
            guard let ld = l.date else { return false }
            guard let rd = r.date else { return true }
            return ld > rd
        }
        var result: [(Date?, [LogItem])] = arr.map { ($0.date, $0.posts) }
        if !unknown.isEmpty {
            result.append((nil, unknown))
        }
        return result
    }

    func shortDateTitle(_ date: Date?) -> String {
        guard let date else { return "時間未知" }
        let fm = DateFormatter()
        fm.locale = Locale(identifier: "zh_TW")
        fm.dateStyle = .medium
        fm.timeStyle = .none
        return fm.string(from: date)
    }
}


//struct ProfileSettingsView: View {
//    @ObservedObject private var auth = AuthManager.shared
//    @Environment(\.dismiss) private var dismiss
//    
//
//    @State private var showAuthSheet = false
//
//    var onNeedAuth: () -> Void
//
//    var body: some View {
//        NavigationStack {
//            List {
//                Section("帳號") {
//                    if let me = auth.currentUser, auth.isAuthenticated {
//                        row(key: "Username", value: me.username)
//                        row(key: "Display Name", value: me.displayName)
//                        row(key: "Email", value: me.email)
//                    } else {
//                        Text("未登入")
//                            .foregroundStyle(.secondary)
//                    }
//                }
//
//                Section {
//                    if auth.isAuthenticated {
//                        Button(role: .destructive) {
//                            auth.logout()
//                            showAuthSheet = true
//                        } label: {
//                            Text("登出")
//                        }
//                    } else {
//                        Button {
//                            showAuthSheet = true
//                        } label: {
//                            Text("登入或註冊")
//                        }
//                    }
//                }
//            }
//            .navigationTitle("設定")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button("完成") { dismiss() }
//                }
//            }
//            .sheet(isPresented: $showAuthSheet) {
//                AuthSheetView(
//                    onDone: {
//                        showAuthSheet = false
//                    }
//                )
//            }
//        }
//    }
//
//    private func row(key: String, value: String) -> some View {
//        HStack {
//            Text(key)
//            Spacer()
//            Text(value).foregroundStyle(.secondary)
//        }
//    }
//}

////////////////////////////////////////////////////////////////
// MARK: - Auth Sheet (Login / Register)
// 避免你專案已有 AuthEntryView → 這裡改名 AuthSheetView
////////////////////////////////////////////////////////////////

struct AuthSheetView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case login = "登入"
        case register = "註冊"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .login

    // login
    @State private var username = ""
    @State private var password = ""

    // register
    @State private var email = ""
    @State private var displayName = ""

    @State private var localError: String?
    @State private var isBusy = false

    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("模式", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let localError, !localError.isEmpty {
                    Section {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let err = auth.errorMessage, !err.isEmpty {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section(mode == .login ? "登入" : "註冊") {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if mode == .register {
                        TextField("email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        TextField("display name", text: $displayName)
                    }

                    SecureField("password", text: $password)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(isBusy ? "處理中…" : (mode == .login ? "登入" : "註冊"))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isBusy)
                }
            }
            .navigationTitle("登入 / 註冊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") {
                        dismiss()
                        onDone()
                    }
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        localError = nil
        auth.errorMessage = nil

        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !u.isEmpty else { localError = "username 不能為空"; return }
        guard !p.isEmpty else { localError = "password 不能為空"; return }

        isBusy = true
        defer { isBusy = false }

        switch mode {
        case .login:
            await auth.login(username: u, password: p)
            if auth.isAuthenticated {
                dismiss()
                onDone()
            }

        case .register:
            let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !e.isEmpty else { localError = "email 不能為空"; return }
            guard !d.isEmpty else { localError = "display name 不能為空"; return }

            let ok = await auth.register(username: u, email: e, password: p, displayName: d)
            if ok {
                // 註冊成功後直接幫你登入（常見 UX）
                await auth.login(username: u, password: p)
                if auth.isAuthenticated {
                    dismiss()
                    onDone()
                }
            }
        }
    }
}
