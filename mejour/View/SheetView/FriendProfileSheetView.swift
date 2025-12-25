//
//  FriendProfileSheetView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/20.
//


import SwiftUI
import MapKit

struct FriendProfileSheetView: View {
    let userId: Int
    let displayName: String?
    @EnvironmentObject private var vm: MapViewModel

    enum Tab: String, CaseIterable, Identifiable {
        case posts = "貼文"
        case map = "地圖"
        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .posts
    @State private var posts: [LogItem] = []
    @State private var placesIndex: [Int: Place] = [:]   // key: placeServerId
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                tabBar
                content
            }
            .padding()
            .navigationTitle("好友頁面")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 72, height: 72)
                .foregroundStyle(.secondary)

            Text(displayName ?? "User #\(userId)")
                .font(.headline)

            HStack(spacing: 24) {
                statItem(title: "探索地點", value: "\(Set(posts.map(\.placeServerId)).count)")
                statItem(title: "貼文", value: "\(posts.count)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var tabBar: some View {
        // ✅ 拆小一點，避免 type-check 太慢
        HStack(spacing: 8) {
            tabButton(.posts)
            tabButton(.map)
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
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .opacity(isSelected ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(isSelected ? 0.22 : 0.10))
        )
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack { ProgressView("載入中…"); Spacer(minLength: 80) }
        } else if let errorText, !errorText.isEmpty {
            VStack(alignment: .leading) { Text(errorText).foregroundStyle(.red).font(.caption); Spacer(minLength: 80) }
        } else {
            switch selectedTab {
            case .posts:
                postsListView
            case .map:
                friendMapView
            }
        }
    }

    private var postsListView: some View {
        Group {
            if posts.isEmpty {
                VStack(spacing: 12) {
                    Text("對方目前沒有可查看的貼文")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 80)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(posts) { p in
                            NavigationLink {
                                LogDetailView(postId: p.serverId)
                                    .environmentObject(vm)
                            } label: {
                                postRow(p)
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
            Text(log.content)
                .lineLimit(2)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Label("\(log.likeCount)", systemImage: "hand.thumbsup")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
    }

    private var friendMapView: some View {
        let explored = exploredPlaces()

        return Group {
            if explored.isEmpty {
                VStack(spacing: 12) {
                    Text("對方目前沒有可查看的探索地點")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 80)
                }
                .frame(maxWidth: .infinity)
            } else {
                Map(position: $camera) {
                    ForEach(explored, id: \.serverId) { place in
                        Annotation(place.name, coordinate: place.coordinate.cl) {
                            Image(systemName: place.type.iconName)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.25)))
                        }
                    }
                }
                .frame(minHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14)))
                .onAppear {
                    // 粗略把鏡頭移到第一個點
                    if let first = explored.first {
                        let region = MKCoordinateRegion(
                            center: first.coordinate.cl,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                        camera = .region(region)
                    }
                }
            }
        }
    }

    private func exploredPlaces() -> [Place] {
        let ids = Array(Set(posts.map(\.placeServerId)))
        return ids.compactMap { placesIndex[$0] }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        // 1) 先拿對方貼文（只會拿到後端允許你看的）
        let p = await PostsManager.shared.fetchPostsByUser(userId: userId)
        posts = p

        // 2) 再拿 places 全部，做 index（避免 N 次 fetchPlace）
        let allPlaces = await PlacesManager.shared.fetchPlaces()
        placesIndex = Dictionary(uniqueKeysWithValues: allPlaces.map { ($0.serverId, $0) })

        // 3) 如果 placesIndex 缺少某些 id，代表你「看不到」對方的該 place（或 places API 沒回）
        // 這是權限/資料範圍問題，不是 UI bug。
    }
}
