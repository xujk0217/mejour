//
//  RootMapView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//

import SwiftUI
import MapKit

// MARK: - ActiveSheet

enum ActiveSheet: Identifiable, Equatable {
    case place(Place)
    case addLog
    case profile // 個人頁面
    case friendsList // 好友列表
    case friendPlace(Place, Int) // place + userId
    case randomFeed(LogItem)
    
    var id: String {
        switch self {
        case .place(let p): return "place-\(p.id)"
        case .addLog:       return "addLog"
        case .profile:      return "profile" // 個人頁面
        case .friendsList:  return "friendsList" // 好友列表
        case .friendPlace(let p, let uid): return "friendPlace-\(p.id)-\(uid)"
        case .randomFeed(let p): return "randomFeed-\(p.serverId)"
        }
    }
}

// MARK: - RootMapView
private enum MapTab: Int { case mine = 0, friends = 1, everyone = 2 }

struct RootMapView: View {
    @StateObject private var vm = MapViewModel()
    @StateObject private var auth = AuthManager.shared

    @State private var activeSheet: ActiveSheet?
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    // friend-place selector
    @State private var friendSelectPlace: Place? = nil
    @State private var friendSelectFriends: [Friend] = []
    @State private var isShowingFriendSelector: Bool = false
    
    // 隨機貼文
    @State private var randomPosts: [LogItem] = []
    @State private var randomPlaceLookup: [Int: Place] = [:]
    @State private var isLoadingRandom = false
    @State private var randomError: String?
    @State private var placeSheetDetent: PresentationDetent = .medium
    @State private var hasCenteredOnUser = false
    @State private var didFinishInitialPlacesLoad = false

    @SceneStorage("selectedMapTab") private var selectedTab: Int = MapTab.mine.rawValue

    var body: some View {
        ZStack {
            // 如果已登入，顯示地圖
            if auth.isAuthenticated {
                TabView(selection: $selectedTab) {
                    // Tab 1: 個人
                    mapContent(scope: .mine)
                        .tabItem { Label("個人", systemImage: "person.crop.circle") }
                        .tag(MapTab.mine.rawValue)

                    // Tab 2: 朋友（目前行為與社群相同）
                    mapContent(scope: .community)
                        .tabItem { Label("朋友", systemImage: "person.2") }
                        .tag(MapTab.friends.rawValue)

                    // Tab 3: 社群（目前行為與社群相同）
                    mapContent(scope: .community)
                        .tabItem { Label("社群", systemImage: "person.3") }
                        .tag(MapTab.everyone.rawValue)
                }
                .sheet(item: $activeSheet) { which in
                    switch which {
                    case .place(let place):
                        PlaceSheetView(
                            place: place,
                            mode: (vm.scope == .mine) ? .onlyMine : .normal,
                            detentSelection: $placeSheetDetent
                        )
                        .environmentObject(vm)
                        .presentationDetents([.medium, .large], selection: $placeSheetDetent)
                    case .addLog:
                        AddLogWizard(vm: vm)
                        .presentationDetents(Set([.large]))
                    case .profile: // 個人頁面
                        ProfileSheetView()
                            .environmentObject(vm)
                            .presentationDetents(Set([.large]))
                    case .friendsList: // 好友列表
                        FriendsListView()
                            .environmentObject(vm)
                            .presentationDetents(Set([.large]))
                    case .friendPlace(let place, let userId):
                        PlaceSheetView(
                            place: place,
                            mode: .onlyUser(userId: userId),
                            detentSelection: $placeSheetDetent
                        )
                            .environmentObject(vm)
                            .presentationDetents([.medium, .large], selection: $placeSheetDetent)
                    case .randomFeed(let start):
                        NavigationStack {
                            RandomLogDetailView(
                                posts: randomPosts,
                                startIndex: randomPosts.firstIndex(where: { $0.serverId == start.serverId }) ?? 0,
                                placeLookup: randomPlaceLookup,
                                onJumpToPlace: { place in
                                    vm.setCamera(to: place.coordinate.cl, animated: true)
                                    activeSheet = .place(place)
                                }
                            )
                        }
                        .environmentObject(vm)
                    }
                }
                .onChange(of: selectedTab) { newValue in
                    vm.scope = (newValue == MapTab.mine.rawValue) ? .mine : .community
                }
                .onChange(of: activeSheet) { which in
                    switch which {
                    case .place, .friendPlace:
                        placeSheetDetent = .medium
                    default:
                        break
                    }
                }
                .onChange(of: auth.isAuthenticated) { authed in
                    if !authed {
                        vm.resetForLogout()
                    } else {
                        vm.loadData(in: nil)
                    }
                }
                .task {
                    vm.scope = (selectedTab == MapTab.mine.rawValue) ? .mine : .community
                    vm.loadData(in: nil)
                    await vm.loadFollowedUsersPosts()
                    if auth.isAuthenticated {
                        Task { await pollPlacesPeriodically() }
                    }
                }
                .onChange(of: auth.isAuthenticated) { authed in
                    if authed {
                        Task { await pollPlacesPeriodically() }
                    }
                }
                .onChange(of: selectedTab) { _ in
                    if selectedTab == MapTab.friends.rawValue {
                        Task { await vm.loadFollowedUsersPosts() }
                    }
                }
                .onChange(of: vm.isLoadingPlaces) { loading in
                    if !loading {
                        didFinishInitialPlacesLoad = true
                    }
                }
                .onChange(of: vm.userCoordinate?.latitude) { _ in
                    if !hasCenteredOnUser, let coord = vm.userCoordinate {
                        vm.setCamera(to: coord, animated: false)
                        hasCenteredOnUser = true
                    }
                }
            } else {
                // 未登入：顯示登入頁面
                LoginOverlayView(auth: auth)
            }
        }
    }

    // MARK: - 地圖內容（兩個 Tab 共用，同一份 UI，只換 scope）
    private func mapContent(scope: MapScope) -> some View {
        ZStack(alignment: .center) {
            Map(position: $vm.cameraPosition, selection: $vm.selectedPlace) {
                if let me = vm.userCoordinate {
                    Annotation("me", coordinate: me) {
                        MyUserPuck(heading: vm.userHeading?.trueHeading)
                            .zIndex(9999)
                            .allowsHitTesting(false)
                    }
                }
                if selectedTab == MapTab.friends.rawValue {
                    // For friend tab: show friend's avatar at places they've posted
                    let pairs: [(place: Place, friend: Friend)] = {
                        var out: [(Place, Friend)] = []
                        let allPlaces = vm.communityPlaces + vm.myPlaces
                        for friend in FollowStore.shared.friends {
                            let posts = vm.userPostsCache[friend.userId] ?? []
                            let placeIds = Set(posts.map { $0.placeServerId })
                            for pid in placeIds {
                                if let place = allPlaces.first(where: { $0.serverId == pid }) {
                                    out.append((place, friend))
                                }
                            }
                        }
                        return out
                    }()

                    let pairsByPlace = Dictionary(grouping: pairs, by: { $0.place.serverId })

                    ForEach(pairsByPlace.keys.sorted(), id: \.self) { pid in
                        if let group = pairsByPlace[pid], let place = group.first?.place {
                            let friends = group.map { $0.friend }
                            Annotation("\(place.name)-\(pid)", coordinate: place.coordinate.cl) {
                                ZStack {
                                    // stacked avatars (up to 3) with offsets
                                    HStack(spacing: -8) {
                                        ForEach(Array(friends.prefix(3)).indices, id: \.self) { i in
                                            let f = friends[i]
                                            Text(FriendAvatarPool.emoji(for: f.avatarId))
                                                .font(.caption)
                                                .frame(width: 34, height: 34)
                                                .background(.ultraThinMaterial, in: Circle())
                                                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                                                .shadow(radius: 2)
                                        }
                                        if friends.count > 3 {
                                            Text("+\(friends.count - 3)")
                                                .font(.caption2)
                                                .frame(width: 34, height: 34)
                                                .background(.thinMaterial, in: Circle())
                                                .shadow(radius: 2)
                                        }
                                    }

                                }
                                .onTapGesture {
                                    if friends.count == 1 {
                                        activeSheet = .friendPlace(place, friends[0].userId)
                                    } else {
                                        friendSelectPlace = place
                                        friendSelectFriends = friends
                                        isShowingFriendSelector = true
                                    }
                                }
                            }
                        }
                    }
                } else {
                    let pins: [Place] = {
                        if selectedTab == MapTab.mine.rawValue {
                            return vm.myPlaces
                        } else {
                            return vm.communityPlaces
                        }
                    }()

                    ForEach(pins, id: \.id) { place in
                        Annotation(place.name, coordinate: place.coordinate.cl) {
                            GlassPin(icon: place.type.iconName, color: place.type.color)
                                .onTapGesture { activeSheet = .place(place) }
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .onMapCameraChange { ctx in
                vm.cameraCenter = ctx.region.center
            }
            
            // 登入與載入狀態指示器（浮動卡片，中心放大）
            let shouldShowPlacesLoading = vm.isLoadingPlaces && !didFinishInitialPlacesLoad
            if auth.isLoading || shouldShowPlacesLoading || isLoadingRandom {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5, anchor: .center)
                    VStack(spacing: 6) {
                        if auth.isLoading {
                            Text("登入中…")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        if shouldShowPlacesLoading {
                            Text("載入地圖資料中…")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        if isLoadingRandom {
                            Text("載入附近貼文…")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(.thickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 280)
            }

            if !vm.isLoadingPlaces && !auth.isLoading {
                // 頂部工具列：左加號、中搜尋、右個人 + 搜尋結果列表
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // 左：根據 tab 顯示不同按鈕（個人=加號、朋友=好友列表、社群=空白占位）
                        if selectedTab == MapTab.mine.rawValue {
                            Button {
                                activeSheet = .addLog
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.25)))
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if selectedTab == MapTab.friends.rawValue {
                            Button {
                                activeSheet = .friendsList
                            } label: {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.25)))
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if selectedTab == MapTab.everyone.rawValue {
                            Button {
                                Task { await loadRandomPosts() }
                            } label: {
                                if isLoadingRandom {
                                    ProgressView()
                                        .frame(width: 40, height: 40)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .overlay(Circle().stroke(.white.opacity(0.25)))
                                } else {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 18, weight: .bold))
                                        .frame(width: 40, height: 40)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .overlay(Circle().stroke(.white.opacity(0.25)))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            // 社群：保留空位，不顯示圈圈
                            Color.clear
                                .frame(width: 40, height: 40)
                        }

                        // 中：搜尋條
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("搜尋地點...", text: $searchText)
                                .font(.system(size: 14))
                                .focused($isSearchFocused)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25)))

                        // 右：個人頁面按鈕
                        Button {
                            activeSheet = .profile
                        } label: {
                            Image(systemName: "person.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.25)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    // 搜尋結果列表
                    if isSearchFocused || !searchText.isEmpty {
                        ScrollView(.vertical) {
                            VStack(spacing: 6) {
                                let resultsToShow = searchText.isEmpty
                                    ? Array(getRecentPlaces().prefix(5))
                                    : getSearchResults()

                                
                                ForEach(resultsToShow, id: \.id) { place in
                                    Button {
                                        isSearchFocused = false
                                        searchText = ""
                                        vm.setCamera(to: place.coordinate.cl, animated: true)
                                        vm.selectedPlace = place
                                        activeSheet = .place(place)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: place.type.iconName)
                                                .foregroundStyle(place.type.color)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(place.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                if !place.tags.isEmpty {
                                                    Text(place.tags.joined(separator: " · "))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .frame(maxHeight: 250)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            // friend selector dialog when multiple friends share the same place
            .confirmationDialog("查看哪位好友的貼文？", isPresented: $isShowingFriendSelector, titleVisibility: .visible) {
                if let place = friendSelectPlace {
                    ForEach(friendSelectFriends, id: \.userId) { f in
                        Button(f.displayName ?? "User #\(f.userId)") {
                            activeSheet = .friendPlace(place, f.userId)
                        }
                    }
                }
                Button("取消", role: .cancel) {
                    friendSelectPlace = nil
                    friendSelectFriends = []
                }
            }

                // 右下角定位按鈕
                VStack(spacing: 10) {
                    Button {
                        if let me = vm.userCoordinate {
                            vm.setCamera(to: me, animated: true)
                        } else {
                            vm.cameraPosition = .userLocation(fallback: .automatic)
                        }
                    } label: { CircleButtonIcon(systemName: "location.fill") }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .navigationTitle(scope == .mine ? "個人地圖" : "社群地圖")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func currentPlacesForSearchAndList() -> [Place] {
        if selectedTab == MapTab.mine.rawValue {
            return vm.myPlaces
        } else if selectedTab == MapTab.friends.rawValue {
            return vm.friendPlaces
        } else {
            return vm.communityPlaces
        }
    }

    private func getRecentPlaces() -> [Place] {
        currentPlacesForSearchAndList()
    }

    private func getSearchResults() -> [Place] {
        let places = currentPlacesForSearchAndList()
        return places.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText) ||
            place.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // MARK: - Background polling

    private func pollPlacesPeriodically() async {
        while auth.isAuthenticated && !Task.isCancelled {
            await vm.loadPlacesFromAPI()
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    // MARK: - Random posts (直接開滑卡)

    @MainActor
    private func loadRandomPosts() async {
        guard !isLoadingRandom else { return }
        isLoadingRandom = true
        randomError = nil
        randomPosts = []
        randomPlaceLookup = [:]
        defer { isLoadingRandom = false }

        let center = vm.cameraCenter ?? vm.userCoordinate ?? CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        let nearbyPlaces = vm.nearestPlaces(
            from: center,
            source: .community,
            limit: 40,
            tagFilter: nil,
            radiusMeters: 1200
        )

        var collected: [LogItem] = []
        var lookup: [Int: Place] = [:]
        for place in nearbyPlaces {
            guard place.serverId > 0 else { continue }
            let posts = await PostsManager.shared.fetchPostsByPlace(placeId: place.serverId)
            if !posts.isEmpty {
                lookup[place.serverId] = place
                collected.append(contentsOf: posts)
            }
            if collected.count >= 30 { break }
        }

        collected.shuffle()
        collected = Array(collected.prefix(30))

        guard let first = collected.first else {
            randomError = "附近沒有可顯示的貼文"
            return
        }

        randomPosts = collected
        randomPlaceLookup = lookup
        activeSheet = .randomFeed(first)
    }
}

// MARK: - Random detail (滑動隨機貼文)

private struct RandomLogDetailView: View {
    let posts: [LogItem]
    let startIndex: Int
    let placeLookup: [Int: Place]
    var onJumpToPlace: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: MapViewModel

    @State private var current: LogItem?
    @State private var queue: [LogItem] = []
    @State private var placeType: PlaceType = .other
    @State private var placeServerId: Int?
    @State private var dragOffset: CGSize = .zero
    private let dragThreshold: CGFloat = 80

    var body: some View {
        let likeProgress = max(0, min(1, dragOffset.width / (dragThreshold * 1.2)))
        let dislikeProgress = max(0, min(1, -dragOffset.width / (dragThreshold * 1.2)))
        let showHints = abs(dragOffset.width) > dragThreshold * 0.6

        return ZStack(alignment: .center) {
            if let next = queue.dropFirst().first {
                cardView(next, place: placeLookup[next.placeServerId])
                    .opacity(0.35)
                    .offset(x: 40, y: 30)
                    .id("bg-\(next.serverId)")
            }

            if let log = current {
                cardView(log, place: placeLookup[log.placeServerId])
                    .id(log.serverId)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
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
                                    Task { await reactAndAdvance("like") }
                                } else if dx < -dragThreshold {
                                    Task { await reactAndAdvance("dislike") }
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )
            } else {
                Text("沒有貼文")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .navigationTitle("隨機貼文")
        .navigationBarTitleDisplayMode(.inline)
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
        .onAppear {
            // 以 startIndex 為起點的循環隊列
            let leading = Array(posts[startIndex...])
            let trailing = Array(posts.prefix(startIndex))
            queue = leading + trailing
            current = queue.first
            placeServerId = queue.first?.placeServerId
            Task { await loadPlaceType(for: placeServerId) }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }

    private func cardView(_ log: LogItem, place: Place?) -> some View {
        let parsed = PostContent.parse(log.content)
        let tags = parsed.tags
        let color = place?.type.color ?? placeType.color
        let screenWidth = UIScreen.main.bounds.width
        let maxWidth: CGFloat = min(screenWidth * 0.9, 520)
        let hasPhoto = !(log.photoURL ?? "").isEmpty
        let photoHeight: CGFloat = max(min(maxWidth * 0.6, 320), 200)
        let contentHeight: CGFloat = max(min(maxWidth * 0.5, 260), 180) + (hasPhoto ? 0 : photoHeight)

        return VStack(alignment: .leading, spacing: 12) {
            Text(log.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            let displayDate = parsed.photoTakenTime ?? log.createdAt
            Text(formatDate(displayDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let urlString = log.photoURL, let url = URL(string: urlString), hasPhoto {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: maxWidth)
                        .frame(maxHeight: photoHeight)
                        .clipped()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(maxWidth: maxWidth)
                        .frame(maxHeight: photoHeight)
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

            if let place {
                Button {
                    dismiss()
                    onJumpToPlace(place)
                } label: {
                    Label("查看「\(place.name)」", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: maxWidth)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    @MainActor
    private func loadPlaceType(for placeId: Int?) async {
        guard let placeId else { return }
        if let place = placeLookup[placeId] {
            placeType = place.type
            return
        }
        if let place = await PlacesManager.shared.fetchPlace(id: placeId) {
            placeType = place.type
        }
    }

    @MainActor
    private func reactAndAdvance(_ reaction: String) async {
        guard let log = current else { return }
        let direction: CGFloat = (reaction == "like") ? 1 : -1

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            dragOffset = CGSize(width: direction * 900, height: 0)
        }

        try? await Task.sleep(nanoseconds: 400_000_000)
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

    @MainActor
    private func updateCaches(with updated: LogItem) {
        if let idx = queue.firstIndex(where: { $0.serverId == updated.serverId }) {
            queue[idx] = updated
        }
        if current?.serverId == updated.serverId {
            current = updated
        }

        var logs = vm.logsByPlace[updated.placeServerId] ?? []
        if let i = logs.firstIndex(where: { $0.serverId == updated.serverId }) {
            logs[i] = updated
            vm.logsByPlace[updated.placeServerId] = logs
        }

        var my = vm.myPosts
        if let j = my.firstIndex(where: { $0.serverId == updated.serverId }) {
            my[j] = updated
        }
        vm.myPosts = my
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let comps = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: now)
        if comps.minute ?? 0 < 1 && comps.hour ?? 0 == 0 && comps.day ?? 0 == 0 {
            return "剛剛"
        }
        if comps.hour ?? 0 < 1 && comps.day ?? 0 == 0 {
            return "\(comps.minute ?? 0) 分鐘前"
        }
        if comps.day ?? 0 < 1 {
            return "\(comps.hour ?? 0) 小時前"
        }
        if comps.day ?? 0 < 7 {
            return "\(comps.day ?? 0) 天前"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.string(from: date)
    }
}

// MARK: - Tag pills

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

// 不再使用 .bordered / .borderedProminent，統一自訂外觀
private struct GlassButtonCompat: ViewModifier {
    var prominent: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(prominent ? Color.accentColor.opacity(0.15) : Color.clear)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
    }
}


// MARK: - 自訂底部 Bar（Deliquified Glass）

private struct DeliquifiedGlassBar: View {
    @Binding var selection: MapScope
    var onAdd: () -> Void

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 10) {
            // 左：雙分頁 capsule
            HStack(spacing: 0) {
                CapsuleTabButton(
                    title: "個人",
                    systemImage: "person.crop.circle",
                    isSelected: selection == .mine,
                    ns: ns
                ) { selection = .mine }

                CapsuleTabButton(
                    title: "朋友",
                    systemImage: "person.2",
                    isSelected: selection == .community,
                    ns: ns
                ) { selection = .community }

                CapsuleTabButton(
                    title: "社群",
                    systemImage: "person.3",
                    isSelected: selection == .community,
                    ns: ns
                ) { selection = .community }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.22)))
                    .background(GlassLiquidLayer(cornerRadius: 24))
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)

            // 右：大圓「＋」
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25)))
                    .background(GlassLiquidLayer(shape: Circle()))
                    .shadow(radius: 10, y: 6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
    }
}

// 一層可重用的液態玻璃動畫：mesh 斑點 + 高光掃描
private struct GlassLiquidLayer: View {
    let shape: AnyShape

    init(cornerRadius: CGFloat) {
        self.shape = AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    init<S: Shape>(shape: S) {
        self.shape = AnyShape(shape)
    }

    var body: some View {
        ZStack {
            LiquidGlowOverlay(intensity: 0.6, speed: 0.22)
                .blur(radius: 12)
                .blendMode(.plusLighter)
            ShimmerSweep(opacity: 0.5, duration: 4.2)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .clipShape(shape)
    }
}

private struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ s: S) { _path = { s.path(in: $0) } }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

// 流動光斑
private struct LiquidGlowOverlay: View {
    var intensity: Double = 0.5
    var speed: Double = 0.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * speed
            Canvas { ctx, size in
                let blobs: [(CGPoint, CGFloat, Color)] = [
                    (p(t, size, 0.0,  0.0, 60), 120, .mint),
                    (p(t, size, 1.3, -0.6, 40), 100, .cyan),
                    (p(t, size, -0.9, 0.8, 20),  90, .blue),
                    (p(t, size, 0.6,  1.2, -30), 80, .teal)
                ]
                for (center, radius, color) in blobs {
                    let shading = GraphicsContext.Shading.radialGradient(
                        .init(colors: [
                            color.opacity(0.50 * intensity),
                            color.opacity(0.18 * intensity),
                            .clear
                        ]),
                        center: center,
                        startRadius: 2,
                        endRadius: radius
                    )
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius,
                                                    y: center.y - radius,
                                                    width: radius * 2,
                                                    height: radius * 2)), with: shading)
                }
            }
        }
    }

    private func p(_ t: TimeInterval, _ size: CGSize, _ ax: Double, _ ay: Double, _ phase: Double) -> CGPoint {
        let w = size.width, h = size.height
        let x = w * 0.5 + CGFloat(sin(t + ax) * (w * 0.32)) + CGFloat(cos(t * 0.7 + ax + phase) * (w * 0.12))
        let y = h * 0.5 + CGFloat(cos(t * 0.9 + ay) * (h * 0.28)) + CGFloat(sin(t * 1.2 + ay + phase) * (h * 0.10))
        return CGPoint(x: x, y: y)
    }
}

// 高光掃過
private struct ShimmerSweep: View {
    var opacity: Double = 0.4
    var duration: Double = 4.0

    @State private var x: CGFloat = -1.0

    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(opacity), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .mask(
            Rectangle()
                .fill(.white)
                .scaleEffect(x: 0.35, y: 1.2, anchor: .center)
                .rotationEffect(.degrees(18))
                .offset(x: x * 220)
        )
        .onAppear {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                x = 1.4
            }
        }
    }
}

private struct CapsuleTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let ns: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title).font(.footnote)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(width: 78, height: 44)
            .background(alignment: .center) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .matchedGeometryEffect(id: "tab-indicator", in: ns)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.28)))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 浮動圓形按鈕樣式 / 我的藍點

private struct CircleButtonIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.25)))
            .shadow(radius: 8, y: 4)
    }
}

private struct MyUserPuck: View {
    let heading: CLLocationDirection?
    var body: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.18)).frame(width: 40, height: 40)
            Circle().fill(Color.blue).frame(width: 12, height: 12)
            if let deg = heading {
                Triangle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 14)
                    .offset(y: -18)
                    .rotationEffect(.degrees(deg))
            }
        }
        .shadow(radius: 4, y: 2)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.minY))
        p.addLine(to: .init(x: r.maxX, y: r.maxY))
        p.addLine(to: .init(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// NearbySheet.swift
struct NearbySheet: View {
    @ObservedObject var vm: MapViewModel
    let baseCoord: CLLocationCoordinate2D?
    let source: MapViewModel.PlaceSource
    @Binding var tagFilter: String
    var onPick: (Place) -> Void
    
    @State private var isLoading = false
    @State private var loadedPlaces: [Place] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("輸入標籤過濾（可留白）", text: $tagFilter)
                        .textFieldStyle(.roundedBorder)
                    Button("清除") { tagFilter = "" }
                        .buttonStyle(.bordered)
                }
                .padding()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("搜尋附近地點中…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let c = baseCoord {
                            let nearby = vm.nearestPlaces(
                                from: c,
                                source: source,                 // ← 依目前分頁（我的/社群）
                                limit: 50,
                                tagFilter: tagFilter,
                                radiusMeters: .greatestFiniteMagnitude
                            )
                            if nearby.isEmpty {
                                Text("找不到附近地點")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(nearby, id: \.id) { place in
                                    Button { onPick(place) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: place.type.iconName)
                                                .foregroundStyle(place.type.color)
                                            VStack(alignment: .leading) {
                                                Text(place.name).font(.headline)
                                                Text(place.tags.joined(separator: " · "))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        } else {
                            Text("尚未取得地圖位置").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("附近的地點")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
