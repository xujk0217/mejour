//
//  APITestView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//

//
//  APITestView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//

import SwiftUI
import CoreLocation
import PhotosUI
import UIKit

struct APITestView: View {
    // Login
    @State private var username: String = "testadmin"
    @State private var password: String = "adminadmin"

    // Create place
    @State private var name: String = "testone"
    @State private var desc: String = "this a test data"
    @State private var latText: String = "-0.6629"
    @State private var lonText: String = "36.83"
    @State private var isPublic: Bool = true

    // metadata -> type/tags
    @State private var type: PlaceType = .other
    @State private var tagsText: String = "咖啡,插座"

    // Fetch place by id (server Int id)
    @State private var fetchPlaceIdText: String = "1"

    // ===== Post tests =====

    // Create post
    @State private var postPlaceIdText: String = "1"      // server Int place id
    @State private var postTitle: String = "string test"
    @State private var postBody: String = "string test"
    @State private var postVisibility: APIVisibility = .private
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data? = nil
    @State private var photoPreview: UIImage? = nil

    // Fetch post by post id
    @State private var fetchPostIdText: String = "2"

    // By-place / By-user
    @State private var byPlaceIdText: String = "1"
    @State private var byUserIdText: String = "1"

    // Reaction
    @State private var reactionPostIdText: String = "2"
    @State private var reactionType: String = "like" // like / dislike

    // Edit post
    @State private var editPostIdText: String = "3"
    @State private var editPlaceIdText: String = "1"
    @State private var editTitle: String = "stringchange"
    @State private var editBody: String = "string"
    @State private var editVisibility: APIVisibility = .private
    @State private var editPhotoItem: PhotosPickerItem?
    @State private var editPhotoData: Data? = nil
    @State private var editPhotoPreview: UIImage? = nil

    // Output
    @State private var output: String = ""
    @State private var isBusy: Bool = false

    var body: some View {
        Form {
            statusSection
            loginSection
            placesSection
            postsSection
            outputSection
        }
        .navigationTitle("API 測試")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _ in
            Task { await loadPickedPhoto(isEdit: false) }
        }
        .onChange(of: editPhotoItem) { _ in
            Task { await loadPickedPhoto(isEdit: true) }
        }
    }
}

// MARK: - Sections
private extension APITestView {

    var statusSection: some View {
        Section("狀態") {
            HStack {
                Text(isBusy ? "忙碌中…" : "就緒")
                Spacer()
                if let me = AuthManager.shared.currentUser {
                    Text("已登入：\(me.username)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("未登入")
                        .foregroundStyle(.secondary)
                }
            }

            if let err = AuthManager.shared.errorMessage, !err.isEmpty {
                Text("AuthError: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = PlacesManager.shared.errorMessage, !err.isEmpty {
                Text("PlaceError: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = PostsManager.shared.errorMessage, !err.isEmpty {
                Text("PostError: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    var loginSection: some View {
        Section("1) 登入") {
            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("password", text: $password)

            HStack {
                Button("登入") { Task { await login() } }
                    .disabled(isBusy)
                Button("登出") { AuthManager.shared.logout() }
                    .disabled(isBusy)
            }

            if let token = AuthManager.shared.accessToken, !token.isEmpty {
                Text("access: \(token.prefix(22))…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var placesSection: some View {
        Section("2) 地點（Places）") {
            Group {
                Text("新增地點（POST /api/map/places/）")
                    .font(.subheadline).foregroundStyle(.secondary)

                TextField("name", text: $name)
                TextField("description", text: $desc)

                HStack {
                    TextField("latitude", text: $latText).keyboardType(.numbersAndPunctuation)
                    TextField("longitude", text: $lonText).keyboardType(.numbersAndPunctuation)
                }

                Toggle("public", isOn: $isPublic)

                Picker("type（寫進 metadata）", selection: $type) {
                    ForEach(PlaceType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }

                TextField("tags（逗號分隔）", text: $tagsText)

                Button("新增地點") { Task { await createPlace() } }
                    .disabled(isBusy)
            }

            Divider()

            Group {
                Text("查詢")
                    .font(.subheadline).foregroundStyle(.secondary)

                Button("取得所有地點（GET /api/map/places/）") {
                    Task { await fetchPlaces() }
                }
                .disabled(isBusy)

                HStack {
                    TextField("place id (Int)", text: $fetchPlaceIdText)
                        .keyboardType(.numberPad)
                    Button("查單筆") { Task { await fetchPlaceById() } }
                        .disabled(isBusy)
                }
            }
        }
    }

    var postsSection: some View {
        Section("3) 貼文（Posts）") {

            Group {
                Text("新增 Post（POST /api/map/posts/，multipart/form-data）")
                    .font(.subheadline).foregroundStyle(.secondary)

                TextField("place id (Int)", text: $postPlaceIdText)
                    .keyboardType(.numberPad)
                TextField("title", text: $postTitle)
                TextField("body", text: $postBody)

                Picker("visibility", selection: $postVisibility) {
                    Text("public").tag(APIVisibility.public)
                    Text("private").tag(APIVisibility.private)
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photoPreview == nil ? "選擇照片（可不選）" : "重新選擇照片", systemImage: "photo")
                }

                if let ui = photoPreview {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("新增 Post") { Task { await createPost() } }
                    .disabled(isBusy)
            }

            Divider()

            Group {
                Text("取得單一 Post（GET /api/map/posts/{postId}/）")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("post id (Int)", text: $fetchPostIdText)
                        .keyboardType(.numberPad)
                    Button("查單筆") { Task { await fetchPostById() } }
                        .disabled(isBusy)
                }
            }

            Divider()

            Group {
                Text("取得 Post（GET /api/map/posts/by-place/{placeId}）")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("place id (Int)", text: $byPlaceIdText)
                        .keyboardType(.numberPad)
                    Button("查 by-place") { Task { await fetchPostsByPlace() } }
                        .disabled(isBusy)
                }
            }

            Divider()

            Group {
                Text("取得 Post（GET /api/map/posts/by-user/{userId}）")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("user id (Int)", text: $byUserIdText)
                        .keyboardType(.numberPad)
                    Button("查 by-user") { Task { await fetchPostsByUser() } }
                        .disabled(isBusy)
                }
            }

            Divider()

            Group {
                Text("Like/Dislike（PATCH /api/map/posts/{id}/reaction/）")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("post id", text: $reactionPostIdText)
                        .keyboardType(.numberPad)
                    Picker("reaction", selection: $reactionType) {
                        Text("like").tag("like")
                        Text("dislike").tag("dislike")
                    }
                    .pickerStyle(.menu)
                }

                Button("送出 Reaction") { Task { await reactToPost() } }
                    .disabled(isBusy)
            }

            Divider()

            Group {
                Text("編輯 Post（PATCH /api/map/posts/{id}/，multipart/form-data）")
                    .font(.subheadline).foregroundStyle(.secondary)

                TextField("post id (Int)", text: $editPostIdText)
                    .keyboardType(.numberPad)
                TextField("place id (Int)", text: $editPlaceIdText)
                    .keyboardType(.numberPad)
                TextField("title", text: $editTitle)
                TextField("body", text: $editBody)

                Picker("visibility", selection: $editVisibility) {
                    Text("public").tag(APIVisibility.public)
                    Text("private").tag(APIVisibility.private)
                }

                PhotosPicker(selection: $editPhotoItem, matching: .images) {
                    Label(editPhotoPreview == nil ? "選擇新照片（可不選）" : "重新選擇新照片", systemImage: "photo.badge.plus")
                }

                if let ui = editPhotoPreview {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("編輯 Post") { Task { await editPost() } }
                    .disabled(isBusy)
            }
        }
    }

    var outputSection: some View {
        Section("輸出") {
            TextEditor(text: $output)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 320)
        }
    }
}

// MARK: - Actions
private extension APITestView {

    @MainActor
    func login() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        await AuthManager.shared.login(username: username, password: password)

        if AuthManager.shared.isAuthenticated {
            output = """
            ✅ Login OK
            user: \(AuthManager.shared.currentUser?.username ?? "-")
            access: \(AuthManager.shared.accessToken ?? "-")
            """
        } else {
            output = """
            ❌ Login Failed
            \(AuthManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    // MARK: - Places

    @MainActor
    func createPlace() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let lat = Double(latText), let lon = Double(lonText) else {
            output = "❌ latitude/longitude 不是數字"
            return
        }

        let tags = normalizeTags(tagsText)
        let metadata = PlaceMetadataCodec.encode(type: type, tags: tags)

        let created = await PlacesManager.shared.createPlaceRawMetadata(
            name: name,
            description: desc,
            latitude: lat,
            longitude: lon,
            isPublic: isPublic,
            metadata: metadata
        )

        if let created {
            let tagString = created.tags.joined(separator: ",")
            output = """
            ✅ Place Created
            serverId: \(created.serverId)
            name: \(created.name)
            type: \(created.type.rawValue)
            tags: \(tagString)
            public: \(created.isPublic)
            ownerId(UUID): \(created.ownerId.uuidString)
            """
        } else {
            output = """
            ❌ Create Place Failed
            \(PlacesManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    @MainActor
    func fetchPlaces() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        let places = await PlacesManager.shared.fetchPlaces()

        let lines = places.map { p -> String in
            let tagString = p.tags.joined(separator: ",")
            // Place.id 在你正式版是 UUID（你貼的 model），但你目前專案有可能改成 Int
            // 所以這裡不再依賴 p.id.uuidString，只用 serverId
            return "- \(p.name) | \(p.isPublic ? "public" : "private") | type=\(p.type.rawValue) | tags=\(tagString) | serverId=\(p.serverId)"
        }.joined(separator: "\n")

        output = """
        ✅ Places count: \(places.count)

        \(lines)
        """
    }

    @MainActor
    func fetchPlaceById() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let id = Int(fetchPlaceIdText) else {
            output = "❌ place id 不是 Int"
            return
        }

        let place = await PlacesManager.shared.fetchPlace(id: id)
        if let place {
            let tagString = place.tags.joined(separator: ",")
            output = """
            ✅ Place #\(id)
            serverId: \(place.serverId)
            name: \(place.name)
            type: \(place.type.rawValue)
            tags: \(tagString)
            public: \(place.isPublic)
            ownerId(UUID): \(place.ownerId.uuidString)
            """
        } else {
            output = """
            ❌ Fetch Place #\(id) Failed
            \(PlacesManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    // MARK: - Posts

    @MainActor
    func createPost() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let placeId = Int(postPlaceIdText) else {
            output = "❌ place id 不是 Int"
            return
        }

        let created = await PostsManager.shared.createPost(
            placeId: placeId,
            title: postTitle,
            bodyText: postBody,
            visibility: postVisibility,
            photoData: photoData,
            photoFilename: "photo.jpg",
            photoMimeType: "image/jpeg"
        )

        if let created {
            output = """
            ✅ Post Created
            serverId: \(created.serverId)
            uuid: \(created.uuid ?? "-")
            placeServerId: \(created.placeServerId)
            title: \(created.title)
            body: \(created.content)
            public: \(created.isPublic)
            photoURL: \(created.photoURL ?? "null")
            like: \(created.likeCount)  dislike: \(created.dislikeCount)
            """
        } else {
            output = """
            ❌ Create Post Failed
            \(PostsManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    @MainActor
    func fetchPostById() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let postId = Int(fetchPostIdText) else {
            output = "❌ post id 不是 Int"
            return
        }

        let post = await PostsManager.shared.fetchPost(postId: postId)
        if let post {
            output = """
            ✅ Post #\(postId)
            serverId: \(post.serverId)
            uuid: \(post.uuid ?? "-")
            placeServerId: \(post.placeServerId)
            authorName: \(post.authorName)
            title: \(post.title)
            body: \(post.content)
            public: \(post.isPublic)
            photoURL: \(post.photoURL ?? "null")
            like: \(post.likeCount)  dislike: \(post.dislikeCount)
            createdAt: \(post.createdAt)
            """
        } else {
            output = """
            ❌ Fetch Post #\(postId) Failed
            \(PostsManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    @MainActor
    func fetchPostsByPlace() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let placeId = Int(byPlaceIdText) else {
            output = "❌ place id 不是 Int"
            return
        }

        let posts = await PostsManager.shared.fetchPostsByPlace(placeId: placeId)

        let lines = posts.map { p -> String in
            // 不用 joined() 的陷阱；也不再用 uuidString
            let uuidShort = (p.uuid?.prefix(8)).map(String.init) ?? "-"
            return "- [#\(p.serverId)] \(p.title) | public=\(p.isPublic) | like=\(p.likeCount) dislike=\(p.dislikeCount) | photo=\(p.photoURL ?? "null") | uuid=\(uuidShort)…"
        }.joined(separator: "\n")

        output = """
        ✅ by-place(\(placeId)) count: \(posts.count)

        \(lines)
        """
    }

    @MainActor
    func fetchPostsByUser() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let userId = Int(byUserIdText) else {
            output = "❌ user id 不是 Int"
            return
        }

        let posts = await PostsManager.shared.fetchPostsByUser(userId: userId)

        let lines = posts.map { p -> String in
            let uuidShort = (p.uuid?.prefix(8)).map(String.init) ?? "-"
            return "- [#\(p.serverId)] \(p.title) | public=\(p.isPublic) | like=\(p.likeCount) dislike=\(p.dislikeCount) | photo=\(p.photoURL ?? "null") | uuid=\(uuidShort)…"
        }.joined(separator: "\n")

        output = """
        ✅ by-user(\(userId)) count: \(posts.count)

        \(lines)
        """
    }

    @MainActor
    func reactToPost() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let postId = Int(reactionPostIdText) else {
            output = "❌ post id 不是 Int"
            return
        }

        let updated = await PostsManager.shared.react(postId: postId, reaction: reactionType)
        if let updated {
            output = """
            ✅ Reaction OK (#\(postId)) -> \(reactionType)
            like: \(updated.likeCount)
            dislike: \(updated.dislikeCount)
            """
        } else {
            output = """
            ❌ Reaction Failed
            \(PostsManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    @MainActor
    func editPost() async {
        isBusy = true
        output = ""
        defer { isBusy = false }

        guard let postId = Int(editPostIdText) else {
            output = "❌ post id 不是 Int"
            return
        }
        guard let placeId = Int(editPlaceIdText) else {
            output = "❌ place id 不是 Int"
            return
        }

        let updated = await PostsManager.shared.editPost(
            postId: postId,
            placeId: placeId,
            title: editTitle,
            bodyText: editBody,
            visibility: editVisibility,
            photoData: editPhotoData,
            photoFilename: "edit.jpg",
            photoMimeType: "image/jpeg"
        )

        if let updated {
            output = """
            ✅ Edit OK (#\(postId))
            serverId: \(updated.serverId)
            uuid: \(updated.uuid ?? "-")
            title: \(updated.title)
            body: \(updated.content)
            public: \(updated.isPublic)
            photoURL: \(updated.photoURL ?? "null")
            like: \(updated.likeCount)  dislike: \(updated.dislikeCount)
            """
        } else {
            output = """
            ❌ Edit Failed
            \(PostsManager.shared.errorMessage ?? "unknown error")
            """
        }
    }

    // MARK: - Photo load

    func loadPickedPhoto(isEdit: Bool) async {
        let item = isEdit ? editPhotoItem : photoItem
        guard let item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                if let ui = UIImage(data: data) {
                    let jpeg = ui.jpegData(compressionQuality: 0.85) ?? data
                    await MainActor.run {
                        if isEdit {
                            self.editPhotoPreview = ui
                            self.editPhotoData = jpeg
                        } else {
                            self.photoPreview = ui
                            self.photoData = jpeg
                        }
                    }
                } else {
                    await MainActor.run {
                        if isEdit {
                            self.editPhotoPreview = nil
                            self.editPhotoData = data
                        } else {
                            self.photoPreview = nil
                            self.photoData = data
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.output = "❌ 讀取照片失敗：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    func normalizeTags(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { acc, t in
                if !acc.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                    acc.append(t)
                }
            }
    }
}
