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

    private(set) var locationManager = CLLocationManager()
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var userHeading: CLHeading?

    // ✅ 正式版：用 place.serverId 當 key（跟後端一致）
    @Published var logsByPlace: [Int: [LogItem]] = [:]

    // 全部地點（我的 + 社群）
    var allPlaces: [Place] { myPlaces + communityPlaces }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    // MARK: - Location

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
    }

    /// 給 RootMapView 既有呼叫點用
    func loadData(in rect: MKMapRect?) {
        Task { [weak self] in
            guard let self else { return }
            await self.loadPlacesFromAPI()
        }
    }

    /// ✅ 新增地點流程（同名 + 距離近似查重 → create）
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

    /// 把 place 插入/更新到 myPlaces & communityPlaces
    private func upsertPlaceIntoLists(_ p: Place) {
        if let i = myPlaces.firstIndex(where: { $0.id == p.id }) {
            myPlaces[i] = p
        } else {
            if let myUUID = UUID(uuidString: AuthManager.shared.currentUser?.uuid ?? ""),
               p.ownerId == myUUID {
                myPlaces.insert(p, at: 0)
            }
        }

        if p.isPublic {
            if let j = communityPlaces.firstIndex(where: { $0.id == p.id }) {
                communityPlaces[j] = p
            } else {
                communityPlaces.insert(p, at: 0)
            }
        }
    }

    /// 同名 + 距離近似查重
    private func findExistingPlaceNear(
        name: String,
        coordinate: CLLocationCoordinate2D,
        within meters: CLLocationDistance,
        includePrivate: Bool
    ) -> Place? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let base = includePrivate ? allPlaces : communityPlaces

        return base
            .filter {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }
            .map {
                ($0, target.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)))
            }
            .filter { $0.1 <= meters }
            .sorted(by: { $0.1 < $1.1 })
            .first?.0
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
                        serverId: -1, // ✅ Apple POI: not in DB
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

    // MARK: - Photos / EXIF

//    func makePhotos(from items: [PhotosPickerItem]) async -> (photos: [LogPhoto], exifCoord: CLLocationCoordinate2D?) {
//        var arr: [LogPhoto] = []
//        var exifCoord: CLLocationCoordinate2D? = nil
//
//        for item in items {
//            if let data = try? await item.loadTransferable(type: Data.self) {
//                arr.append(LogPhoto(data: data))
//                if exifCoord == nil,
//                   let src = CGImageSourceCreateWithData(data as CFData, nil),
//                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
//                   let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
//                   let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
//                   let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
//                    exifCoord = .init(latitude: lat, longitude: lon)
//                }
//            }
//        }
//        return (arr, exifCoord)
//    }

    func extractCoordinate(from item: PhotosPickerItem?) async -> CLLocationCoordinate2D? {
        if let item,
           let data = try? await item.loadTransferable(type: Data.self),
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            return .init(latitude: lat, longitude: lon)
        }
        return locationManager.location?.coordinate
    }

    // MARK: - Posts / Logs (正式版)

    /// ✅ 取得某地點的 posts（從後端），寫進 cache：logsByPlace[place.serverId]
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

    /// ✅ 新增 post：必要時先把 Apple POI 轉成 DB Place，再 createPost
    @MainActor
    func addLog(
        attachTo place: Place,
        title: String,
        content: String,
        isPublic: Bool,
        photoData: Data?,
        authorName: String = "我"
    ) async -> LogItem? {

        guard await ensureLoginIfNeeded() else { return nil }

        // 1) 確保 place 有 serverId（Apple POI 先轉成 API place）
        var targetPlace = place
        if targetPlace.serverId <= 0 {
            do {
                targetPlace = try await getOrCreatePlace(
                    name: place.name,
                    description: "", // ✅ 不要硬塞 place.name 當 description（可改成 UI 欄位）
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

        // 2) 打後端建立 post
        let created = await PostsManager.shared.createPost(
            placeId: targetPlace.serverId,
            title: title,
            bodyText: content,
            visibility: isPublic ? .public : .private,
            photoData: photoData
        )

        guard let created else { return nil }

        // 3) 更新 cache（key 用 place.serverId）
        logsByPlace[targetPlace.serverId, default: []].insert(created, at: 0)

        // 4) 確保 place 在列表
        upsertPlaceIntoLists(targetPlace)

        return created
    }

    // MARK: - Place updates

    func updatePlace(_ updated: Place) {
        if let i = myPlaces.firstIndex(where: { $0.id == updated.id }) {
            myPlaces[i] = updated
        }
        if let j = communityPlaces.firstIndex(where: { $0.id == updated.id }) {
            communityPlaces[j] = updated
        }
    }

    // MARK: - Nearby & Dedup

    func nearbyCommunityPlace(to coord: CLLocationCoordinate2D, within meters: CLLocationDistance = 120) -> Place? {
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return communityPlaces
            .map { ($0, here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))) }
            .filter { $0.1 <= meters }
            .sorted(by: { $0.1 < $1.1 })
            .first?.0
    }

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

        let filtered = uniq.filter { p in
            let passTag: Bool = {
                guard let t = tagFilter, !t.isEmpty else { return true }
                return p.tags.contains { $0.localizedCaseInsensitiveContains(t) }
            }()
            let d = here.distance(from: CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude))
            return passTag && d <= radiusMeters
        }

        return filtered.sorted {
            let d0 = here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
            let d1 = here.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
            return d0 < d1
        }.prefix(limit).map { $0 }
    }

    private func dedupPlaces(_ src: [Place]) -> [Place] {
        var seen = Set<String>()
        var out: [Place] = []
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
