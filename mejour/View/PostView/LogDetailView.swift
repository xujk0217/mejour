//
//  LogDetailView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI

struct LogDetailView: View {
    let log: LogItem
    @State private var comments: [CommentItem] = []
    @State private var newComment: String = ""
    @State private var likes: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(log.title).font(.title2).bold()
                Text("by \(log.authorName)").foregroundStyle(.secondary)
                if !log.photos.isEmpty {
                    TabView {
                        ForEach(log.photos) { p in
                            if let ui = UIImage(data: p.data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
                                    .clipped()
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 300)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
                Text(log.content)

                HStack(spacing: 16) {
                    Button { likes += 1 } label: {
                        Label("\(likes)", systemImage: "hand.thumbsup")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                Text("留言").font(.headline)
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.content)
                        Text(c.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    TextField("新增留言…", text: $newComment).textFieldStyle(.roundedBorder)
                    Button("送出") {
                        guard !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        comments.append(.init(id: UUID(), logId: log.id, authorId: UUID(), content: newComment, createdAt: .now))
                        newComment = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("日誌")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { likes = log.likeCount }
    }
}

