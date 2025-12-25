//
//  LogDetailView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI

struct LogDetailView: View {
    let postId: Int
    private enum SwipeDirection { case left, right }
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: MapViewModel
    @State private var current: LogItem?
    @State private var queue: [LogItem] = []
    @State private var placeType: PlaceType = .other
    @State private var placeServerId: Int?
    @State private var isLoading = false
    @State private var errorText: String?
    
    // gesture
    @State private var dragOffset: CGSize = .zero
    private let dragThreshold: CGFloat = 80
    
    var body: some View {
        let likeProgress = max(0, min(1, dragOffset.width / (dragThreshold * 1.2)))
        let dislikeProgress = max(0, min(1, -dragOffset.width / (dragThreshold * 1.2)))
        let showHints = abs(dragOffset.width) > dragThreshold * 0.6

        return ZStack(alignment: .center) {
            if let next = queue.dropFirst().first {
                cardView(next, isBackground: true, offset: .zero)
                    .opacity(0.35)
                    .offset(x: 40, y: 30)
                    .id("bg-\(next.serverId)")
            }
            
            if let log = current {
                cardView(log, isBackground: false, offset: dragOffset)
                    .id(log.serverId)
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { value in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                let dx = value.translation.width
                                if dx > dragThreshold {
                                    handleSwipe(direction: .right)
                                } else if dx < -dragThreshold {
                                    handleSwipe(direction: .left)
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )
            } else if isLoading {
                ProgressView("載入中…")
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .navigationTitle("日誌")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear {
            Task { await refreshPlacePostsIfNeeded() }
        }
        .overlay(alignment: .leading) {
            if showHints && dislikeProgress > 0 {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "hand.thumbsdown.fill").foregroundStyle(.red))
                    .padding(.leading, 16)
                    .opacity(Double(min(dislikeProgress, 1)))
            }
        }
        .overlay(alignment: .trailing) {
            if showHints && likeProgress > 0 {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "hand.thumbsup.fill").foregroundStyle(.green))
                    .padding(.trailing, 16)
                    .opacity(Double(min(likeProgress, 1)))
            }
        }
    }
    
    private func handleSwipe(direction: SwipeDirection) {
        Task {
            let reaction = (direction == .right) ? "like" : "dislike"
            await reactAndAdvance(reaction)
        }
    }
    
    // MARK: - Card
    
    private func cardView(_ log: LogItem, isBackground: Bool, offset: CGSize) -> some View {
        let parsed = PostContent.parse(log.content)
        let tags = parsed.tags
        let color = placeType.color
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth: CGFloat = min(screenWidth * 0.9, 520)
        let hasPhoto = !(log.photoURL ?? "").isEmpty
        let photoHeight: CGFloat = max(min(cardWidth * 0.6, 320), 200)
        let contentHeight: CGFloat = max(min(cardWidth * 0.5, 260), 180) + (hasPhoto ? 0 : photoHeight)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(log.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            let displayDate = PostContent.parse(log.content).photoTakenTime ?? log.createdAt
            Text(formatDate(displayDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let urlString = log.photoURL, let url = URL(string: urlString), hasPhoto {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: cardWidth)
                        .frame(height: photoHeight)
                        .clipped()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(maxWidth: cardWidth)
                        .frame(height: photoHeight)
                        .overlay(ProgressView())
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("標籤")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TagPills(tags: tags, tint: color)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("內容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(log.displayContent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }
                .frame(minHeight: contentHeight, maxHeight: contentHeight)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
            .padding(14)
        .frame(maxWidth: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(isBackground ? 0.05 : 0.15), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / 20)))
    }
    
    // MARK: - Data
    
    @MainActor
    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        
        guard let fetched = await PostsManager.shared.fetchPost(postId: postId) else {
            errorText = PostsManager.shared.errorMessage ?? "Fetch failed"
            return
        }
        placeServerId = fetched.placeServerId
        await loadPlaceType(for: fetched.placeServerId)
        
        // 拉同地點的其他貼文，當做下一則
        let more = await PostsManager.shared.fetchPostsByPlace(placeId: fetched.placeServerId)
        var merged = [fetched] + more.filter { $0.serverId != fetched.serverId }
        queue = dedupLogs(merged)
        current = queue.first
    }
    
    @MainActor
    private func reactAndAdvance(_ reaction: String) async {
        guard let log = current else { return }
        let direction: CGFloat = (reaction == "like") ? 1 : -1

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            dragOffset = CGSize(width: direction * 900, height: 0)
        }

        // 延遲一下讓動畫順暢再切換
        try? await Task.sleep(nanoseconds: 220_000_000)
        await MainActor.run {
            let nextPlaceId = queue.dropFirst().first?.placeServerId
            advanceQueue()
            dragOffset = .zero
            if let pid = nextPlaceId {
                Task { await loadPlaceType(for: pid) }
            }
        }

        Task {
            let updated = await PostsManager.shared.react(postId: log.serverId, reaction: reaction) ?? log
            await MainActor.run {
                updateCaches(with: updated)
            }
        }
    }
    
    @MainActor
    private func replaceCurrent(with updated: LogItem) {
        if !queue.isEmpty {
            queue[0] = updated
        }
        current = updated
    }
    
    @MainActor
    private func advanceQueue() {
        guard !queue.isEmpty else { dismiss(); return }
        queue.removeFirst()
        if let next = queue.first {
            current = next
            placeServerId = next.placeServerId
        } else {
            dismiss()
        }
    }
    
    private func dedupLogs(_ logs: [LogItem]) -> [LogItem] {
        var seen = Set<Int>()
        var out: [LogItem] = []
        for l in logs {
            if !seen.contains(l.serverId) {
                seen.insert(l.serverId)
                out.append(l)
            }
        }
        return out
    }

    @MainActor
    private func updateCaches(with updated: LogItem) {
        // 更新本地 queue/current
        if let idx = queue.firstIndex(where: { $0.serverId == updated.serverId }) {
            queue[idx] = updated
        }
        if current?.serverId == updated.serverId {
            current = updated
        }

        // 同步到 vm logsByPlace
        var logs = vm.logsByPlace[updated.placeServerId] ?? []
        if let i = logs.firstIndex(where: { $0.serverId == updated.serverId }) {
            logs[i] = updated
            vm.logsByPlace[updated.placeServerId] = logs
        }

        // 更新我的貼文快取（直接改陣列避免 wrapper 設定衝突）
        var my = vm.myPosts
        if let j = my.firstIndex(where: { $0.serverId == updated.serverId }) {
            my[j] = updated
        }
        vm.myPosts = my
    }
    
    @MainActor
    private func loadPlaceType(for placeId: Int) async {
        if let place = await PlacesManager.shared.fetchPlace(id: placeId) {
            placeType = place.type
        } else {
            placeType = .other
        }
    }

    @MainActor
    private func refreshPlacePostsIfNeeded() async {
        guard let pid = placeServerId else { return }
        if let place = (vm.myPlaces + vm.communityPlaces).first(where: { $0.serverId == pid }) {
            await vm.loadPosts(for: place, force: true)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: now)
        
        if components.minute! < 1 && components.hour! == 0 && components.day! == 0 {
            return "剛剛"
        }
        if components.hour! < 1 && components.day! == 0 {
            return "\(components.minute!)分鐘前"
        }
        if components.day! < 1 {
            return "\(components.hour!)小時前"
        }
        if components.day! < 7 {
            return "\(components.day!)天前"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.string(from: date)
    }
}

// MARK: - Shared tag pills

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
