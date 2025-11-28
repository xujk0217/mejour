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
    @Published var scope: MapScope = .mine
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var myPlaces: [Place] = []
    @Published var communityPlaces: [Place] = []
    @Published var selectedPlace: Place?
    @Published var isPresentingAddSheet = false
    @Published var cameraCenter: CLLocationCoordinate2D?

    private(set) var locationManager = CLLocationManager()
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var userHeading: CLHeading?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func setCamera(to coord: CLLocationCoordinate2D, span: MKCoordinateSpan = .init(latitudeDelta: 0.004, longitudeDelta: 0.004), animated: Bool = true) {
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
    
    @MainActor
    func searchApplePOIs(near center: CLLocationCoordinate2D,
                         radiusMeters: CLLocationDistance = 30) async -> [Place] {

        if #available(iOS 17.0, *) {
            let req = MKLocalPointsOfInterestRequest(center: center, radius: radiusMeters)
            let search = MKLocalSearch(request: req)
            do {
                let response = try await search.start()
                return response.mapItems.compactMap { (item) -> Place? in
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

        // iOS 16−
        let metersPerDegreeLat: CLLocationDistance = 111_000
        let latDelta = radiusMeters / metersPerDegreeLat * 2.0
        let lonDelta = latDelta / max(cos(center.latitude * .pi / 180), 0.01)

        var req = MKLocalSearch.Request()
        req.resultTypes = .pointOfInterest
        req.region = MKCoordinateRegion(center: center,
                                        span: MKCoordinateSpan(latitudeDelta: latDelta,
                                                               longitudeDelta: lonDelta))

        let search = MKLocalSearch(request: req)
        do {
            let response = try await search.start()
            return response.mapItems.compactMap { (item) -> Place? in
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

    // 讀取選取的照片（含 EXIF GPS）
    func makePhotos(from items: [PhotosPickerItem]) async -> (photos: [LogPhoto], exifCoord: CLLocationCoordinate2D?) {
        var arr: [LogPhoto] = []
        var exifCoord: CLLocationCoordinate2D? = nil
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                arr.append(LogPhoto(data: data))
                if exifCoord == nil,
                   let src = CGImageSourceCreateWithData(data as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
                   let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
                   let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                    exifCoord = .init(latitude: lat, longitude: lon)
                }
            }
        }
        return (arr, exifCoord)
    }

    // 舊 API（demo 用）
    func addLog(at coord: CLLocationCoordinate2D,
                attachTo place: Place,
                title: String, content: String,
                type: PlaceType, isPublic: Bool,
                photos: [LogPhoto],
                authorName: String = "我") {

        let log = LogItem(id: UUID(), placeId: place.id, authorId: UUID(),
                          authorName: authorName, title: title, content: content,
                          photos: photos, isPublic: isPublic, createdAt: .now)

        if !((scope == .mine ? myPlaces : communityPlaces).contains(where: { $0.id == place.id })) {
            myPlaces.append(place)
            if isPublic { communityPlaces.append(place) }
        }
    }
    
    func updatePlace(_ updated: Place) {
        if let i = myPlaces.firstIndex(where: { $0.id == updated.id }) {
            myPlaces[i] = updated
        }
        if let j = communityPlaces.firstIndex(where: { $0.id == updated.id }) {
            communityPlaces[j] = updated
        }
    }

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

    // 「每個地點有哪些日誌」的快取（demo）
    @Published var logsByPlace: [UUID: [LogItem]] = [:]

    // 全部地點（我的 + 社群）
    var allPlaces: [Place] { myPlaces + communityPlaces }

    // DEMO 假資料：加入你指定的位置附近幾個點
    func loadData(in rect: MKMapRect?) {
        if myPlaces.isEmpty {
            let my1 = Place(id: UUID(), name: "我的咖啡點", type: .cafe,
                            tags: ["咖啡","閱讀","插座"], coordinate: CLCodable(latitude: 25.033, longitude: 121.5654),
                            isPublic: false, ownerId: UUID())
            let my2 = Place(id: UUID(), name: "家附近早餐", type: .restaurant,
                            tags: ["早午餐","平價"], coordinate: CLCodable(latitude: 25.034, longitude: 121.5662),
                            isPublic: false, ownerId: UUID())
            myPlaces = [my1, my2]

            // 為「我的」地點補上日誌（含圖片）
            if logsByPlace[my1.id] == nil {
                logsByPlace[my1.id] = [
                    LogItem(id: UUID(), placeId: my1.id, authorId: UUID(), authorName: "我",
                            title: "咖啡順口、環境安靜", content: "平日下午人不多，適合用電腦工作。",
                            photos: demoPhotos(colors: [.brown, .systemBlue], symbols: ["cup.and.saucer", "bolt.fill"]),
                            isPublic: false, createdAt: .now, likeCount: 1, commentCount: 0)
                ]
            }
            if logsByPlace[my2.id] == nil {
                logsByPlace[my2.id] = [
                    LogItem(id: UUID(), placeId: my2.id, authorId: UUID(), authorName: "我",
                            title: "蛋餅酥、豆漿香", content: "六點半開始，排隊很快。",
                            photos: [], isPublic: false, createdAt: .now, likeCount: 0, commentCount: 0)
                ]
            }
        }
        if communityPlaces.isEmpty {
            let c1 = Place(id: UUID(), name: "社群餐廳", type: .restaurant,
                           tags: ["餐廳","聚餐"], coordinate: CLCodable(latitude: 25.036, longitude: 121.563),
                           isPublic: true, ownerId: UUID())
            let c2 = Place(id: UUID(), name: "河濱景點", type: .scenic,
                           tags: ["散步","景點"], coordinate: CLCodable(latitude: 25.04, longitude: 121.57),
                           isPublic: true, ownerId: UUID())
            communityPlaces = [c1, c2]

            logsByPlace[c1.id] = [
                .init(id: UUID(), placeId: c1.id, authorId: UUID(), authorName: "Ken",
                      title: "湯頭清甜、油蔥香", content: "米粉湯 35，乾意麵 45，超值。",
                      photos: demoPhotos(colors: [.systemOrange], symbols: ["fork.knife"]), isPublic: true, createdAt: .now, likeCount: 5, commentCount: 3)
            ]
            logsByPlace[c2.id] = [
                .init(id: UUID(), placeId: c2.id, authorId: UUID(), authorName: "Ivy",
                      title: "黃昏散步超療癒", content: "日落時分風很舒服，路面平坦適合長輩。",
                      photos: demoPhotos(colors: [.systemGreen, .systemTeal], symbols: ["leaf.fill","sunset.fill"]), isPublic: true, createdAt: .now, likeCount: 2, commentCount: 1)
            ]
        }

        // 既有的三峽種子
        let baseLat = 24.944216964550566
        let baseLon = 121.37095483558234
        seedPlacesNear(lat: baseLat, lon: baseLon)

        // 新增：在三峽附近大量塞資料（我的 10 筆、社群 20 筆）
        seedBulkAroundSanzhi(baseLat: baseLat, baseLon: baseLon, myCount: 10, communityCount: 20)
    }

    private func seedPlacesNear(lat: Double, lon: Double) {
        // 避免重複塞
        guard !communityPlaces.contains(where: { abs($0.coordinate.latitude - lat) < 0.0005 && abs($0.coordinate.longitude - lon) < 0.0005 }) else { return }
        let base = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        func offset(_ dLat: Double, _ dLon: Double) -> CLCodable {
            .init(latitude: base.latitude + dLat, longitude: base.longitude + dLon)
        }

        let p1 = Place(id: UUID(), name: "壢城公園步道", type: .scenic, tags: ["散步","綠地","親子"], coordinate: offset(0.0012, 0.0009), isPublic: true, ownerId: UUID())
        let p2 = Place(id: UUID(), name: "巷口米粉湯", type: .restaurant, tags: ["小吃","宵夜","米粉湯"], coordinate: offset(-0.0008, 0.0015), isPublic: true, ownerId: UUID())
        let p3 = Place(id: UUID(), name: "Daily Drip 咖啡", type: .cafe, tags: ["咖啡","插座","安靜"], coordinate: offset(0.0010, -0.0012), isPublic: true, ownerId: UUID())
        communityPlaces.append(contentsOf: [p1,p2,p3])

        logsByPlace[p1.id] = [
            .init(id: UUID(), placeId: p1.id, authorId: UUID(), authorName: "Ivy",
                  title: "黃昏散步超療癒", content: "日落時分風很舒服，路面平坦適合長輩。",
                  photos: demoPhotos(colors: [.systemGreen, .systemTeal], symbols: ["leaf.fill","figure.walk"]), isPublic: true, createdAt: .now, likeCount: 2, commentCount: 1)
        ]
        logsByPlace[p2.id] = [
            .init(id: UUID(), placeId: p2.id, authorId: UUID(), authorName: "Ken",
                  title: "湯頭清甜、油蔥香", content: "米粉湯 35，乾意麵 45，超值。",
                  photos: demoPhotos(colors: [.systemOrange, .systemRed], symbols: ["fork.knife","flame.fill"]), isPublic: true, createdAt: .now, likeCount: 5, commentCount: 3)
        ]
        logsByPlace[p3.id] = [
            .init(id: UUID(), placeId: p3.id, authorId: UUID(), authorName: "Lena",
                  title: "好坐、有插座", content: "平日下午不擠，單品中焙偏酸。",
                  photos: demoPhotos(colors: [.brown, .systemBlue], symbols: ["cup.and.saucer","bolt.fill"]), isPublic: true, createdAt: .now, likeCount: 1, commentCount: 0)
        ]
    }

    // 新增：在三峽附近大量塞資料
    private func seedBulkAroundSanzhi(baseLat: Double, baseLon: Double, myCount: Int, communityCount: Int) {
        // 以 base 為中心，±0.0015 度內隨機散佈
        func randomOffset() -> (Double, Double) {
            let rLat = Double.random(in: -0.0015...0.0015)
            let rLon = Double.random(in: -0.0015...0.0015)
            return (rLat, rLon)
        }
        func coord(_ d: (Double, Double)) -> CLCodable {
            .init(latitude: baseLat + d.0, longitude: baseLon + d.1)
        }

        // 名稱與標籤模板
        let cafeNames = ["角落咖啡", "樹影咖啡", "河畔咖啡", "晨光手沖", "慢步咖啡", "巷弄拿鐵"]
        let restNames = ["夜市小吃", "三峽米粉", "家常麵館", "巷口便當", "古早味湯品", "三五好友聚"]
        let scenicNames = ["河濱步道", "紅磚老街", "觀景平台", "小橋流水", "綠蔭小徑", "親子草坪"]
        let shopNames = ["選物小店", "手作雜貨", "文具良品", "小巷選物", "巷尾書店", "木作工坊"]

        func randomType() -> PlaceType {
            [.cafe, .restaurant, .scenic, .shop].randomElement() ?? .other
        }
        func defaultTags(for t: PlaceType) -> [String] {
            switch t {
            case .cafe: return ["咖啡","插座","不限時"].shuffled().prefix(2).map { $0 }
            case .restaurant: return ["小吃","平價","米粉湯","聚餐","宵夜"].shuffled().prefix(2).map { $0 }
            case .scenic: return ["散步","景點","拍照","步道"].shuffled().prefix(2).map { $0 }
            case .shop: return ["選物","手作","逛街"].shuffled().prefix(2).map { $0 }
            case .other: return ["推薦","常去"]
            }
        }
        func randomName(for t: PlaceType) -> String {
            switch t {
            case .cafe: return cafeNames.randomElement()!
            case .restaurant: return restNames.randomElement()!
            case .scenic: return scenicNames.randomElement()!
            case .shop: return shopNames.randomElement()!
            case .other: return "附近地點"
            }
        }

        // 生成我的 10 筆
        var newMy: [Place] = []
        for _ in 0..<myCount {
            let t = randomType()
            let c = coord(randomOffset())
            let p = Place(id: UUID(), name: randomName(for: t), type: t, tags: defaultTags(for: t),
                          coordinate: c, isPublic: false, ownerId: UUID())
            newMy.append(p)
        }
        // 生成社群 20 筆
        var newCommunity: [Place] = []
        for _ in 0..<communityCount {
            let t = randomType()
            let c = coord(randomOffset())
            let p = Place(id: UUID(), name: randomName(for: t), type: t, tags: defaultTags(for: t),
                          coordinate: c, isPublic: true, ownerId: UUID())
            newCommunity.append(p)
        }

        // 加入並去重（避免重覆呼叫 loadData 時爆量）
        myPlaces.append(contentsOf: newMy)
        communityPlaces.append(contentsOf: newCommunity)

        myPlaces = dedupPlaces(myPlaces)
        communityPlaces = dedupPlaces(communityPlaces)

        // 為部分地點補上日誌（隨機 0~2 筆，部分含圖片）
        func seedLogs(for place: Place, isPublic: Bool) {
            let count = Int.random(in: 0...2)
            guard count > 0 else { return }
            var arr: [LogItem] = logsByPlace[place.id] ?? []
            for i in 0..<count {
                let withPhoto = Bool.random()
                let photos: [LogPhoto] = withPhoto ? demoPhotos(colors: [.systemTeal, .systemPink, .systemYellow].shuffled().prefix(1).map { $0 }, symbols: ["photo","leaf.fill","fork.knife"].shuffled().prefix(1).map { $0 }) : []
                let author = isPublic ? ["Ken","Ivy","Lena","Ray","Mia","Neo"].randomElement()! : "我"
                let title = isPublic ? (["好吃", "好喝", "好走", "好拍"].randomElement()! + "！") : "隨手記 \(i+1)"
                let content = isPublic ? "路過覺得不錯，已收藏。" : "備忘：下次帶朋友來。"
                arr.insert(.init(id: UUID(), placeId: place.id, authorId: UUID(), authorName: author, title: title, content: content, photos: photos, isPublic: isPublic, createdAt: .now, likeCount: Int.random(in: 0...6), commentCount: Int.random(in: 0...3)), at: 0)
            }
            logsByPlace[place.id] = arr
        }

        for p in newMy { seedLogs(for: p, isPublic: false) }
        for p in newCommunity { seedLogs(for: p, isPublic: true) }
    }

    // 附近是否已有社群點（半徑預設 120m）
    func nearbyCommunityPlace(to coord: CLLocationCoordinate2D, within meters: CLLocationDistance = 120) -> Place? {
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return communityPlaces
            .map { ($0, here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))) }
            .filter { $0.1 <= meters }
            .sorted(by: { $0.1 < $1.1 })
            .first?.0
    }

    enum PlaceSource { case mine, community, all }
    func nearestPlaces(from coord: CLLocationCoordinate2D,
                       source: PlaceSource,
                       limit: Int = 10,
                       tagFilter: String? = nil,
                       radiusMeters: CLLocationDistance = 30) -> [Place] {
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

    func ensureTags(for placeId: UUID, tags: [String]) {
        if let idx = myPlaces.firstIndex(where: { $0.id == placeId }) {
            if myPlaces[idx].tags.isEmpty { myPlaces[idx].tags = tags }
        }
        if let idx = communityPlaces.firstIndex(where: { $0.id == placeId }) {
            if communityPlaces[idx].tags.isEmpty { communityPlaces[idx].tags = tags }
        }
    }

    func addLog(attachTo place: Place, title: String, content: String, isPublic: Bool, photos: [LogPhoto], authorName: String = "我") {
        let log = LogItem(id: UUID(), placeId: place.id, authorId: UUID(), authorName: authorName,
                          title: title, content: content, photos: photos, isPublic: isPublic, createdAt: .now)
        logsByPlace[place.id, default: []].insert(log, at: 0)

        if !myPlaces.contains(where: { $0.id == place.id }) && place.ownerId == place.ownerId {
            myPlaces.append(place)
        }
        if isPublic && !communityPlaces.contains(where: { $0.id == place.id }) {
            communityPlaces.append(place)
        }
    }
    
    private func dedupPlaces(_ src: [Place]) -> [Place] {
        var seen = Set<String>()
        var out: [Place] = []
        for p in src {
            let key = "\(p.name.lowercased())-\(round(p.coordinate.latitude*10_000))/\(round(p.coordinate.longitude*10_000))"
            if !seen.contains(key) {
                seen.insert(key)
                out.append(p)
            }
        }
        return out
    }

    // MARK: - Demo image helpers

    private func demoPhotos(colors: [UIColor], symbols: [String]) -> [LogPhoto] {
        var out: [LogPhoto] = []
        let count = min(colors.count, symbols.count)
        for i in 0..<count {
            if let data = demoImageData(color: colors[i], symbol: symbols[i]) {
                out.append(LogPhoto(data: data))
            }
        }
        return out
    }

    private func demoImageData(color: UIColor, size: CGSize = .init(width: 800, height: 500), symbol: String? = nil) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if let symbol {
                let cfg = UIImage.SymbolConfiguration(pointSize: min(size.width, size.height) * 0.25, weight: .bold)
                if let sf = UIImage(systemName: symbol, withConfiguration: cfg) {
                    let tint = UIColor.white.withAlphaComponent(0.9)
                    let tinted = sf.withTintColor(tint, renderingMode: .alwaysOriginal)
                    let rect = CGRect(x: (size.width - tinted.size.width)/2,
                                      y: (size.height - tinted.size.height)/2,
                                      width: tinted.size.width, height: tinted.size.height)
                    tinted.draw(in: rect)
                }
            }
        }
        return img.pngData()
    }
}

