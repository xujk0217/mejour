//
//  LogDetailView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI

struct LogDetailView: View {
    let postId: Int
    
    @State private var log: LogItem?
    @State private var isLoading = false
    @State private var errorText: String?
    
    // comments 先留本地（等你之後有 comment API 再接）
    @State private var comments: [CommentItem] = []
    @State private var newComment: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                
                // Header
                if let log {
                    Text(log.title).font(.title2).bold()
                    
                    HStack(spacing: 12) {
                        NavigationLink {
                            FriendProfileView(userId: log.authorServerId)
                        } label: {
                            Text("by \(log.authorName)")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        // 顯示時間
                        if let photoTime = log.photoTakenTime {
                            Text(formatDate(photoTime))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(formatDate(log.createdAt))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    
                    // Photo (正式版：單張 URL)
                    if let urlString = log.photoURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
                                    .clipped()
                            case .failure:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.quaternary)
                                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
                                    .overlay {
                                        Label("圖片載入失敗", systemImage: "exclamationmark.triangle")
                                            .foregroundStyle(.secondary)
                                    }
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Text(log.displayContent)
                    
                    // Reactions (正式版：打 API)
                    HStack(spacing: 12) {
                        Button {
                            Task { await react("like") }
                        } label: {
                            Label("\(log.likeCount)", systemImage: "hand.thumbsup")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                        
                        Button {
                            Task { await react("dislike") }
                        } label: {
                            Label("\(log.dislikeCount)", systemImage: "hand.thumbsdown")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                    }
                } else if isLoading {
                    ProgressView("載入中…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
                
                //                Divider()
                //
                //                // Comments (暫時本地)
                //                Text("留言").font(.headline)
                //
                //                ForEach(comments) { c in
                //                    VStack(alignment: .leading, spacing: 4) {
                //                        Text(c.content)
                //                        Text(c.createdAt, style: .date)
                //                            .font(.caption)
                //                            .foregroundStyle(.secondary)
                //                    }
                //                    .padding(.vertical, 4)
                //                }
                //
                //                HStack {
                //                    TextField("新增留言…", text: $newComment)
                //                        .textFieldStyle(.roundedBorder)
                //
                //                    Button("送出") {
                //                        let t = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                //                        guard !t.isEmpty else { return }
                //                        comments.append(.init(id: UUID(), logId: UUID(), authorId: UUID(), content: t, createdAt: .now))
                //                        newComment = ""
                //                    }
                //                    .buttonStyle(.bordered)
                //                }
            }
            .padding()
        }
        .navigationTitle("日誌")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    
    @MainActor
    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        
        let fetched = await PostsManager.shared.fetchPost(postId: postId)
        if let fetched {
            self.log = fetched
        } else {
            self.errorText = PostsManager.shared.errorMessage ?? "Fetch failed"
        }
    }
    
    @MainActor
    private func react(_ reaction: String) async {
        guard let log else { return }
        isLoading = true
        defer { isLoading = false }
        
        let updated = await PostsManager.shared.react(postId: log.serverId, reaction: reaction)
        if let updated {
            self.log = updated
        } else {
            self.errorText = PostsManager.shared.errorMessage ?? "Reaction failed"
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
