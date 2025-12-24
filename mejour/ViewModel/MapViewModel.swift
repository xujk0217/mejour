//
//  MapViewModel.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation
import PhotosUI
import ImageIO
import UIKit

@MainActor
final class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - UI State

    @Published var scope: MapScope = .mine
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    @Published var myPlaces: [Place] = []
    @Published var communityPlaces: [Place] = []
    @Published var selectedPlace: Place?

    @Published var isPresentingAddSheet = false
    @Published var cameraCenter: CLLocationCoordinate2D?
    @Published var isLoadingPlaces = false

    // MARK: - My posts / explored

    @Published var myPosts: [LogItem] = []
    @Published var exploredPlaceServerIds: Set<Int> = []

    // MARK: - Friend/User Posts Cache (for "onlyUser" mode)

    /// key = userId(Int)
    @Published var userPostsCache: [Int: [LogItem]] = [:]

    // MARK: - Posts cache by place (community / normal mode)

    /// key = place.serverId(Int)
    @Published var logsByPlace: [Int: [LogItem]] = [:]

    // MARK: - Location

    private(set) var locationManager = CLLocationManager()
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var userHeading: CLHeading?

    // MARK: - Derived (places)

    /// 全部地點（我的 + 社群）
    var allPlaces: [Place] { myPlaces + communityPlaces }

    /// ✅ 我探索過的 places：只顯示「有發過 post」的地點
    var myExploredPlaces: [Place] {
        // 用 serverId 做 index，但要避免 duplicate key（保留第一個）
        var index: [Int: Place] = [:]
        for p in allPlaces {
            if index[p.serverId] == nil {
                index[p.serverId] = p
            }
        }
        return exploredPlaceServerIds.compactMap { index[$0] }
    }

    /// 追蹤者探索過的 place ids（從 userPostsCache 推導）
    var friendExploredPlaceServerIds: Set<Int> {
        let ids = FollowStore.shared.ids
        if ids.isEmpty { return [] }

        var out = Set<Int>()
        for uid in ids {
            let posts = userPostsCache[uid] ?? []
            for p in posts {
                out.insert(p.placeServerId)
            }
        }
        return out
    }

    /// 追蹤者探索過的 Place（用 communityPlaces 映射回去）
    var friendPlaces: [Place] {
        let ids = friendExploredPlaceServerIds
        if ids.isEmpty { return [] }

        // communityPlaces 也可能有重複 serverId，保留第一個避免 fatal duplicate
        var index: [Int: Place] = [:]
        for p in communityPlaces {
            if index[p.serverId] == nil {
                index[p.serverId] = p
            }
        }
        return ids.compactMap { index[$0] }
    }
    
    // MARK: - Place updates (local cache update)
    func updatePlace(_ updated: Place) {
        // 更新 myPlaces
        if let i = myPlaces.firstIndex(where: { $0.id == updated.id }) {
            myPlaces[i] = updated
        }

        // 更新 communityPlaces
        if let j = communityPlaces.firstIndex(where: { $0.id == updated.id }) {
            communityPlaces[j] = updated
        }

        // 如果你還有其他依 place 相關的快取，也可在這邊同步更新
    }


    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    // MARK: - Location delegate

    func setCamera(
        to coord: CLLocationCoordinate2D,
        span: MKCoordinateSpan = .init(latitudeDelta: 0.004, longitudeDelta: 0.004),
        animated: Bool = true
    ) {
        let region = MKCoordinateRegion(center: coord, span: span)
        if animated {
            withAnimation(.timingCurve(0.22, 0.8, 0.16, 1.0, duration: 0.8)) {
                self.cameraPosition = .region(region)
            }
        } else {
            self.cameraPosition = .region(region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        userHeading = newHeading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - Auth helper

    private func ensureLoginIfNeeded() async -> Bool {
        if AuthManager.shared.accessToken == nil || AuthManager.shared.accessToken?.isEmpty == true {
            await AuthManager.shared.loginDefaultUser()
        }
        return AuthManager.shared.accessToken?.isEmpty == false
    }

    // MARK: - Logout reset

    @MainActor
    func resetForLogout() {
        // places
        myPlaces = []
        communityPlaces = []
        selectedPlace = nil

        // posts cache
        logsByPlace = [:]

        // my
        myPosts = []
        exploredPlaceServerIds = []

        // friends
        userPostsCache = [:]

        // camera etc (optional)
        cameraCenter = nil
    }

    // MARK: - My posts / explored

    func myPostsAtPlace(placeServerId: Int) -> [LogItem] {
        myPosts.filter { $0.placeServerId == placeServerId }
    }

    @MainActor
    func loadMyPostsAndExploredPlaces() async {
        guard let me = AuthManager.shared.currentUser else { return }
        let posts = await PostsManager.shared.fetchPostsByUser(userId: me.id)
        self.myPosts = posts
        self.exploredPlaceServerIds = Set(posts.map(\.placeServerId))
    }

    // MARK: - Friend cache helpers

    func postsOfUserAtPlace(userId: Int, placeServerId: Int) -> [LogItem] {
        let posts = userPostsCache[userId] ?? []
        return posts.filter { $0.placeServerId == placeServerId }
    }

    func setUserPostsCache(userId: Int, posts: [LogItem]) {
        var cache = userPostsCache
        cache[userId] = posts
        userPostsCache = cache
    }


    /// 把所有追蹤的人的 posts 抓回來放 cache（不用新 API：走既有 by-user）
    @MainActor
    func loadFollowedUsersPosts() async {
        let ids = FollowStore.shared.ids
        guard !ids.isEmpty else { return }

        for uid in ids {
            let posts = await PostsManager.shared.fetchPostsByUser(userId: uid)
            var cache = userPostsCache
            cache[uid] = posts
            userPostsCache = cache
        }
    }

    /// 某 place：聚合所有追蹤者在該地點的貼文
    func friendPosts(at placeServerId: Int) -> [LogItem] {
        let ids = FollowStore.shared.ids
        guard !ids.isEmpty else { return [] }

        var out: [LogItem] = []
        for uid in ids {
            let posts = userPostsCache[uid] ?? []
            out.append(contentsOf: posts.filter { $0.placeServerId == placeServerId })
        }
        return out
    }

    // MARK: - API Places

    /// 取回 places，並切成 my/community 兩份
    func loadPlacesFromAPI() async {
        guard await ensureLoginIfNeeded() else { return }

        isLoadingPlaces = true
        defer { isLoadingPlaces = false }

        let all = await PlacesManager.shared.fetchPlaces()

        // 以 currentUser.uuid 切分
        let myUUID = UUID(uuidString: AuthManager.shared.currentUser?.uuid ?? "")

        if let myUUID {
            self.myPlaces = dedupPlaces(all.filter { $0.ownerId == myUUID })
        } else {
            self.myPlaces = []
        }

        // community：所有 public
        self.communityPlaces = dedupPlaces(all.filter { $0.isPublic })

        // 只把「我有發文」的 place 記錄下來（個人地圖用）
        await loadMyPostsAndExploredPlaces()
    }

    /// 給 RootMapView 既有呼叫點用
    func loadData(in rect: MKMapRect?) {
        Task { [weak self] in
            guard let self else { return }
            await self.loadPlacesFromAPI()
        }
    }

    // MARK: - Create place (dedup -> create)

    func getOrCreatePlace(
        name: String,
        description: String,
        coordinate: CLLocationCoordinate2D,
        isPublic: Bool,
        type: PlaceType,
        tags: [String],
        dedupRadiusMeters: CLLocationDistance = 30
    ) async throws -> Place {

        guard await ensureLoginIfNeeded() else {
            throw APIError.missingAccessToken
        }

        if let existing = findExistingPlaceNear(
            name: name,
            coordinate: coordinate,
            within: dedupRadiusMeters,
            includePrivate: true
        ) {
            return existing
        }

        guard let created = await PlacesManager.shared.createPlace(
            name: name,
            description: description,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            isPublic: isPublic,
            type: type,
            tags: tags
        ) else {
            let msg = PlacesManager.shared.errorMessage ?? "createPlace returned nil (mapping failed)"
            throw APIError.mappingFailed("Create place failed: \(msg)")
        }

        upsertPlaceIntoLists(created)
        return created
    }

    private func upsertPlaceIntoLists(_ p: Place) {
        // 檢查當前使用者是否是景點的擁有者
        let isCurrentUserOwner = AuthManager.shared.currentUser?.uuid == p.ownerId.uuidString

        // myPlaces - 只有當前使用者擁有的景點才加入
        var my = myPlaces
        if let i = my.firstIndex(where: { $0.id == p.id }) {
            my[i] = p
        } else if isCurrentUserOwner {
            my.insert(p, at: 0)
        }
        myPlaces = my

        // communityPlaces（public only）
        if p.isPublic {
            var comm = communityPlaces
            if let j = comm.firstIndex(where: { $0.id == p.id }) {
                comm[j] = p
            } else {
                comm.insert(p, at: 0)
            }
            communityPlaces = comm
        }
    }


    private func findExistingPlaceNear(
        name: String,
        coordinate: CLLocationCoordinate2D,
        within meters: CLLocationDistance,
        includePrivate: Bool
    ) -> Place? {

        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let base = includePrivate ? allPlaces : communityPlaces

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let sameName = base.filter { p in
            p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }

        var best: (Place, CLLocationDistance)?
        for p in sameName {
            let d = target.distance(from: CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude))
            if d <= meters {
                if best == nil || d < best!.1 {
                    best = (p, d)
                }
            }
        }
        return best?.0
    }

    // MARK: - Apple POIs

    @MainActor
    func searchApplePOIs(
        near center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 30
    ) async -> [Place] {

        if #available(iOS 17.0, *) {
            let req = MKLocalPointsOfInterestRequest(center: center, radius: radiusMeters)
            let search = MKLocalSearch(request: req)
            do {
                let response = try await search.start()
                return response.mapItems.compactMap { item -> Place? in
                    guard let loc = item.placemark.location else { return nil }

                    var inferred: PlaceType = .other
                    if let cat = item.pointOfInterestCategory {
                        switch cat {
                        case .cafe: inferred = .cafe
                        case .restaurant: inferred = .restaurant
                        case .park: inferred = .scenic
                        default: break
                        }
                    }

                    return Place(
                        id: UUID(),
                        serverId: -1, // Apple POI: not in DB
                        name: item.name ?? "未命名地點",
                        type: inferred,
                        tags: [],
                        coordinate: CLCodable(loc.coordinate),
                        isPublic: true,
                        ownerId: UUID(),
                        origin: .apple,
                        applePlaceId: nil
                    )
                }
            } catch {
                print("POI search error (iOS17+):", error)
                return []
            }
        }

        // iOS 16− fallback
        let metersPerDegreeLat: CLLocationDistance = 111_000
        let latDelta = radiusMeters / metersPerDegreeLat * 2.0
        let lonDelta = latDelta / max(cos(center.latitude * .pi / 180), 0.01)

        var req = MKLocalSearch.Request()
        req.resultTypes = .pointOfInterest
        req.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )

        let search = MKLocalSearch(request: req)
        do {
            let response = try await search.start()
            return response.mapItems.compactMap { item -> Place? in
                guard let loc = item.placemark.location else { return nil }

                var inferred: PlaceType = .other
                if #available(iOS 15.0, *), let cat = item.pointOfInterestCategory {
                    switch cat {
                    case .cafe: inferred = .cafe
                    case .restaurant: inferred = .restaurant
                    case .park: inferred = .scenic
                    default: break
                    }
                }

                return Place(
                    id: UUID(),
                    serverId: -1,
                    name: item.name ?? "未命名地點",
                    type: inferred,
                    tags: [],
                    coordinate: CLCodable(loc.coordinate),
                    isPublic: true,
                    ownerId: UUID(),
                    origin: .apple,
                    applePlaceId: nil
                )
            }
        } catch {
            print("POI search error (iOS16−):", error)
            return []
        }
    }

    // MARK: - Posts / Logs (community / normal mode)

    /// 社群地點頁：用 by-place 拿公開貼文
    @MainActor
    func loadPosts(for place: Place, force: Bool = false) async {
        guard await ensureLoginIfNeeded() else { return }
        guard place.serverId > 0 else { return } // Apple POI 尚未入庫，不能查

        if !force, let cached = logsByPlace[place.serverId], !cached.isEmpty {
            return
        }

        let posts = await PostsManager.shared.fetchPostsByPlace(placeId: place.serverId)
        logsByPlace[place.serverId] = posts
    }

    /// 新增 post：必要時先把 Apple POI 轉成 DB Place，再 createPost
    @MainActor
    func addLog(
        attachTo place: Place,
        title: String,
        content: String,
        isPublic: Bool,
        photoData: Data?
    ) async -> LogItem? {

        guard await ensureLoginIfNeeded() else { return nil }

        // 1) 確保 place 有 serverId（Apple POI 先轉成 API place）
        var targetPlace = place
        if targetPlace.serverId <= 0 {
            do {
                targetPlace = try await getOrCreatePlace(
                    name: place.name,
                    description: "",
                    coordinate: place.coordinate.cl,
                    isPublic: isPublic,
                    type: place.type,
                    tags: place.tags
                )
            } catch {
                print("getOrCreatePlace failed:", error.localizedDescription)
                return nil
            }
        }

        // 2) 建立 post
        let created = await PostsManager.shared.createPost(
            placeId: targetPlace.serverId,
            title: title,
            bodyText: content,
            visibility: isPublic ? .public : .private,
            photoData: photoData
        )

        guard let created else { return nil }

        // 3) 更新 cache（by-place）— 用「重新賦值」確保 @Published 觸發
        var placeLogs = logsByPlace[targetPlace.serverId] ?? []
        placeLogs.insert(created, at: 0)
        logsByPlace[targetPlace.serverId] = placeLogs

        // 4) 更新我的 posts/explored — 用「重新賦值」確保刷新
        myPosts = [created] + myPosts

        var explored = exploredPlaceServerIds
        explored.insert(created.placeServerId)
        exploredPlaceServerIds = explored

        // 5) 確保 place 在列表（myPlaces/communityPlaces 也要用重新賦值比較穩）
        upsertPlaceIntoLists(targetPlace)


        return created
    }

    // MARK: - Nearby & Dedup

    enum PlaceSource { case mine, community, all }

    func nearestPlaces(
        from coord: CLLocationCoordinate2D,
        source: PlaceSource,
        limit: Int = 10,
        tagFilter: String? = nil,
        radiusMeters: CLLocationDistance = 30
    ) -> [Place] {

        let base: [Place] = {
            switch source {
            case .mine: return myPlaces
            case .community: return communityPlaces
            case .all: return allPlaces
            }
        }()

        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let uniq = dedupPlaces(base)

        var filtered: [Place] = []
        filtered.reserveCapacity(uniq.count)

        for p in uniq {
            let passTag: Bool
            if let t = tagFilter, !t.isEmpty {
                passTag = p.tags.contains { $0.localizedCaseInsensitiveContains(t) }
            } else {
                passTag = true
            }

            if !passTag { continue }

            let d = here.distance(from: CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude))
            if d <= radiusMeters {
                filtered.append(p)
            }
        }

        filtered.sort {
            let d0 = here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
            let d1 = here.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
            return d0 < d1
        }

        return Array(filtered.prefix(limit))
    }

    private func dedupPlaces(_ src: [Place]) -> [Place] {
        var seen = Set<String>()
        var out: [Place] = []
        out.reserveCapacity(src.count)

        for p in src {
            let key = "\(p.name.lowercased())-\(round(p.coordinate.latitude * 10_000))/\(round(p.coordinate.longitude * 10_000))"
            if !seen.contains(key) {
                seen.insert(key)
                out.append(p)
            }
        }
        return out
    }
}
