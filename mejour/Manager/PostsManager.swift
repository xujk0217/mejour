//
//  PostsManager.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//


import Foundation

@MainActor
final class PostsManager: ObservableObject {
    static let shared = PostsManager()

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let baseURL = URL(string: "https://meejing-backend.vercel.app")!

    private init() {}
    
    // Simple in-memory cache for posts by user
    private let postsCacheTTL: TimeInterval = 60 * 5 // 5 minutes
    private var cachedPostsByUser: [Int: (posts: [LogItem], fetchedAt: Date)] = [:]

    // MARK: - 4) 新增 Post（multipart/form-data）
    func createPost(
        placeId: Int,
        title: String,
        bodyText: String,
        visibility: APIVisibility,
        photoData: Data?,
        photoFilename: String = "photo.jpg",
        photoMimeType: String = "image/jpeg",
        tags: [String]? = nil,
        takenAt: Date? = nil
    ) async -> LogItem? {

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // 將拍攝時間/標籤編碼進 body 內容
            let finalBody = PostContent.encode(photoTakenTime: takenAt, tags: tags, text: bodyText)
            
            var form = MultipartFormData()
            form.addText(name: "place_id", value: "\(placeId)")
            form.addText(name: "title", value: title)
            form.addText(name: "body", value: finalBody)
            form.addText(name: "visibility", value: visibility.rawValue)

            if let photoData {
                form.addFile(name: "photo", filename: photoFilename, mimeType: photoMimeType, fileData: photoData)
            }

            let (data, contentType) = form.finalize()

            let api: APIPost = try await authedRequest(
                path: "/api/map/posts/",
                method: "POST",
                contentType: contentType,
                body: data
            )

            guard let mapped = LogItem(api: api) else {
                throw APIError.mappingFailed("APIPost -> LogItem mapping failed (uuid/date).")
            }
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 5) 取得單一 Post（用 post id）
    func fetchPost(postId: Int) async -> LogItem? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let api: APIPost = try await authedRequest(
                path: "/api/map/posts/\(postId)/",
                method: "GET",
                contentType: nil,
                body: nil
            )
            guard let mapped = LogItem(api: api) else {
                throw APIError.mappingFailed("APIPost -> LogItem mapping failed.")
            }
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 7) 取得 Post 透過地點 id
    // 你提供的回傳看起來是「單一物件」，但一般設計應該是「陣列」。
    // 所以我做「同時支援 object 或 array」：永遠回 [LogItem]
    func fetchPostsByPlace(placeId: Int) async -> [LogItem] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data: Data = try await authedRequestRaw(
                path: "/api/map/posts/by-place/\(placeId)/",
                method: "GET",
                contentType: nil,
                body: nil
            )
            let apis = try decodeObjectOrArray(APIPost.self, from: data)
            let mapped = apis.compactMap(LogItem.init(api:))
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - 8) 取得 post 透過 user id（回傳 array）
    func fetchPostsByUser(userId: Int, forceRefresh: Bool = false) async -> [LogItem] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // return cached if fresh
        if !forceRefresh, let entry = cachedPostsByUser[userId] {
            if Date().timeIntervalSince(entry.fetchedAt) < postsCacheTTL {
                return entry.posts
            }
        }

        do {
            let apis: [APIPost] = try await authedRequest(
                path: "/api/map/posts/by-user/\(userId)/",
                method: "GET",
                contentType: nil,
                body: nil
            )
            let mapped = apis.compactMap(LogItem.init(api:))
            cachedPostsByUser[userId] = (posts: mapped, fetchedAt: Date())
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - 9) 喜歡 / 不喜歡
    func react(postId: Int, reaction: String) async -> LogItem? {
        // reaction: "like" or "dislike"
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload = try JSONEncoder().encode(["reaction": reaction])
            let api: APIPost = try await authedRequest(
                path: "/api/map/posts/\(postId)/reaction/",
                method: "PATCH",
                contentType: "application/json",
                body: payload
            )
            guard let mapped = LogItem(api: api) else {
                throw APIError.mappingFailed("Reaction mapping failed.")
            }
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 10) 編輯 Post（multipart/form-data）
    func editPost(
        postId: Int,
        placeId: Int,
        title: String,
        bodyText: String,
        visibility: APIVisibility,
        photoData: Data?,                 // nil = 不更新照片（取決於後端怎麼處理）
        photoFilename: String = "photo.jpg",
        photoMimeType: String = "image/jpeg"
    ) async -> LogItem? {

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var form = MultipartFormData()
            form.addText(name: "place_id", value: "\(placeId)")
            form.addText(name: "title", value: title)
            form.addText(name: "body", value: bodyText)
            form.addText(name: "visibility", value: visibility.rawValue)
            if let photoData {
                form.addFile(name: "photo", filename: photoFilename, mimeType: photoMimeType, fileData: photoData)
            }

            let (data, contentType) = form.finalize()

            let api: APIPost = try await authedRequest(
                path: "/api/map/posts/\(postId)/",
                method: "PATCH",
                contentType: contentType,
                body: data
            )

            guard let mapped = LogItem(api: api) else {
                throw APIError.mappingFailed("Edit mapping failed.")
            }
            return mapped
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Core request helpers

    private func authedRequest<T: Decodable>(
        path: String,
        method: String,
        contentType: String?,
        body: Data?
    ) async throws -> T {
        let data = try await authedRequestRaw(path: path, method: method, contentType: contentType, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodeFailed
        }
    }

    private func authedRequestRaw(
        path: String,
        method: String,
        contentType: String?,
        body: Data?
    ) async throws -> Data {
        guard let access = AuthManager.shared.accessToken, !access.isEmpty else {
            throw APIError.missingAccessToken
        }

        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.addValue("Bearer \(access)", forHTTPHeaderField: "Authorization")

        if let contentType { req.addValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body { req.httpBody = body }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.httpStatus(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(http.statusCode, text)
        }
        return data
    }

    // 支援「object or array」的 decode（你 by-place 回傳看起來怪怪的）
    private func decodeObjectOrArray<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        if let arr = try? JSONDecoder().decode([T].self, from: data) {
            return arr
        }
        let obj = try JSONDecoder().decode(T.self, from: data)
        return [obj]
    }
}
