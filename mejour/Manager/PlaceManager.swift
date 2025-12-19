//
//  APIError.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//


import Foundation


enum APIError: Error, LocalizedError {
    case missingAccessToken
    case httpStatus(Int, String)
    case decodeFailed
    case invalidURL
    case mappingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken: return "Missing access token. Please login first."
        case .httpStatus(let code, let body): return "HTTP \(code): \(body)"
        case .decodeFailed: return "Failed to decode server response."
        case .invalidURL: return "Invalid URL."
        case .mappingFailed(let msg): return "Mapping failed: \(msg)"
        }
    }
}

@MainActor
final class PlacesManager: ObservableObject {
    static let shared = PlacesManager()

    @Published private(set) var places: [Place] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let baseURL = URL(string: "https://meejing-backend.vercel.app")!

    private init() {}

    // 1) 查詢所有地點（後端會依 token + visibility 決定回傳範圍）
    func fetchPlaces() async -> [Place] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page: APIPaginated<APIPlace> = try await authedRequest(
                path: "/api/map/places/",
                method: "GET",
                body: nil
            )

            let mapped: [Place] = page.results.compactMap { Place(api: $0) }

            // 如果有 mapping 掉資料，至少讓你知道（避免默默少點）
            if mapped.count != page.results.count {
                let dropped = page.results.count - mapped.count
                throw APIError.mappingFailed("Dropped \(dropped) place(s) due to UUID/lat/lon parsing.")
            }

            self.places = mapped
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // 3) 透過地點 id（後端 Int id）查地點
    func fetchPlace(id: Int) async -> Place? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let api: APIPlace = try await authedRequest(
                path: "/api/map/places/\(id)/",
                method: "GET",
                body: nil
            )
            guard let place = Place(api: api) else {
                throw APIError.mappingFailed("UUID/lat/lon parsing failed for place id=\(id)")
            }
            return place
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // 2) 新增地點（你說資料庫沒有才呼叫）
    func createPlace(
        name: String,
        description: String,
        latitude: Double,
        longitude: Double,
        isPublic: Bool,
        type: PlaceType,
        tags: [String]
    ) async -> Place? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let metadataString = PlaceMetadataCodec.encode(type: type, tags: tags)

            let req = APICreatePlaceRequest(
                name: name,
                description: description,
                latitude: decimal6(latitude),
                longitude: decimal6(longitude),
                visibility: isPublic ? .public : .private,
                metadata: metadataString
            )
            let body = try JSONEncoder().encode(req)

            let api: APIPlace = try await authedRequest(
                path: "/api/map/places/",
                method: "POST",
                body: body
            )

            guard let created = Place(api: api) else {
                throw APIError.mappingFailed("UUID/lat/lon parsing failed for created place.")
            }

            self.places.insert(created, at: 0)
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }


    // MARK: - Core Request

    private func authedRequest<T: Decodable>(
        path: String,
        method: String,
        body: Data?
    ) async throws -> T {
        guard let access = AuthManager.shared.accessToken, !access.isEmpty else {
            throw APIError.missingAccessToken
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(access)", forHTTPHeaderField: "Authorization")

        if let body {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpStatus(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(http.statusCode, bodyText)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodeFailed
        }
    }
    
    /// 測試用：直接傳 metadata(JSON字串)
    func createPlaceRawMetadata(
        name: String,
        description: String,
        latitude: Double,
        longitude: Double,
        isPublic: Bool,
        metadata: String
    ) async -> Place? {

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let req = APICreatePlaceRequest(
                name: name,
                description: description,
                latitude: decimal6(latitude),
                longitude: decimal6(longitude),
                visibility: isPublic ? .public : .private,
                metadata: metadata
            )
            let body = try JSONEncoder().encode(req)

            let api: APIPlace = try await authedRequest(
                path: "/api/map/places/",
                method: "POST",
                body: body
            )

            guard let created = Place(api: api) else {
                throw APIError.mappingFailed("UUID/lat/lon parsing failed for created place.")
            }

            self.places.insert(created, at: 0)
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

}

private func decimal6(_ v: Double) -> String {
    String(format: "%.6f", v)
}
