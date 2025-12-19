//
//  AddLogSheet.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI
import PhotosUI
import MapKit
import ImageIO
import CoreLocation

struct AddLogWizard: View {
    @ObservedObject var vm: MapViewModel

    enum Step { case photos, choosePlace, compose }
    @State private var step: Step = .photos

    // Step 1 (正式版：只用 1 張)
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var detectedCoord: CLLocationCoordinate2D?

    // Step 2
    @State private var candidates: [Place] = []
    @State private var selectedPlace: Place?
    @State private var creatingNew = false
    @State private var newPlaceName = ""
    @State private var newPlaceTags: [String] = []
    @State private var newPlaceType: PlaceType = .other

    // Step 3
    @State private var isPublic = true
    @State private var title = ""
    @State private var content = ""

    @State private var isPublishing = false
    @State private var publishError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .photos: photosStep
                case .choosePlace: choosePlaceStep
                case .compose: composeStep
                }
            }
            .navigationTitle("新增日誌")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step != .photos {
                        Button("上一步") { goPrev() }
                            .disabled(isPublishing)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if step == .compose {
                        Button(isPublishing ? "發佈中…" : "發佈") {
                            Task { await publish() }
                        }
                        .disabled(!canPublish || isPublishing)
                    } else {
                        Button("下一步") { goNext() }
                            .disabled(!canNext || isPublishing)
                    }
                }
            }
        }
        .task { await reloadPhotoLocally() }
        .onChange(of: photoItem) { _ in
            Task { await reloadPhotoLocally() }
        }
    }

    // MARK: - Steps

    private var photosStep: some View {
        Form {
            Section("照片（正式版：單張）") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photoData == nil ? "選擇照片" : "重新選擇", systemImage: "photo")
                }

                if let data = photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.vertical, 6)
                } else {
                    Text("尚未選擇照片（可不選，photo 可為空）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let c = detectedCoord {
                    Text("定位來源：\(photoData == nil ? "GPS" : "EXIF")  (\(String(format: "%.5f", c.latitude)), \(String(format: "%.5f", c.longitude)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("尚未取得定位（稍候或開啟定位權限）")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("下一步：選擇地點") { goNext() }
                    .platformButtonStyle()
            }
        }
    }

    private var choosePlaceStep: some View {
        List {
            if let err = publishError, !err.isEmpty {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }

            if !creatingNew {
                Section {
                    Button { creatingNew = true } label: {
                        Label("建立新地點", systemImage: "mappin.and.ellipse")
                    }
                }
            }

            if creatingNew {
                Section("新地點資訊") {
                    TextField("地點名稱", text: $newPlaceName)

                    Picker("類型", selection: $newPlaceType) {
                        ForEach(PlaceType.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }

                    TagEditor(
                        title: "標籤",
                        tags: $newPlaceTags,
                        presetTags: defaultPresetTags(for: newPlaceType)
                    )
                }
            }

            Section("附近的地點") {
                if candidates.isEmpty {
                    Text("找不到附近地點，可建立新地點")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates, id: \.id) { p in
                        Button {
                            selectedPlace = p
                            creatingNew = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: p.type.iconName)
                                VStack(alignment: .leading) {
                                    Text(p.name).bold()
                                    if !p.tags.isEmpty {
                                        Text(p.tags.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("無標籤").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if selectedPlace?.id == p.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: populateCandidates)
        .onChange(of: detectedCoord?.latitude ?? .infinity) { _ in populateCandidates() }
        .onChange(of: detectedCoord?.longitude ?? .infinity) { _ in populateCandidates() }
    }

    private var composeStep: some View {
        Form {
            if let err = publishError, !err.isEmpty {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }

            Section {
                Toggle("公開到社群", isOn: $isPublic)
            }

            Section {
                TextField("標題", text: $title)
                TextEditor(text: $content).frame(minHeight: 160)
            }

            if let data = photoData, let ui = UIImage(data: data) {
                Section("預覽照片") {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Navigation logic

    private var canNext: Bool {
        switch step {
        case .photos:
            return true
        case .choosePlace:
            return (selectedPlace != nil) || creatingNew
        case .compose:
            return false
        }
    }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (selectedPlace != nil || creatingNew)
    }

    private func goNext() {
        switch step {
        case .photos:
            step = .choosePlace
        case .choosePlace:
            step = .compose
        case .compose:
            break
        }
    }

    private func goPrev() {
        switch step {
        case .photos: break
        case .choosePlace: step = .photos
        case .compose: step = .choosePlace
        }
    }

    // MARK: - Candidates

    private func populateCandidates() {
        let coord = detectedCoord ?? vm.locationManager.location?.coordinate
        guard let coord else { candidates = []; return }

        Task { @MainActor in
            var mine = vm.nearestPlaces(from: coord, source: .all, limit: 50, tagFilter: nil, radiusMeters: 30)
            let apple = await vm.searchApplePOIs(near: coord, radiusMeters: 30)

            func key(_ p: Place) -> String {
                "\(p.name.lowercased())-\(round(p.coordinate.latitude*10_000))/\(round(p.coordinate.longitude*10_000))"
            }
            var seen = Set(mine.map { key($0) })
            var merged = mine
            for p in apple {
                if !seen.contains(key(p)) {
                    merged.append(p)
                    seen.insert(key(p))
                }
            }
            candidates = merged
        }
    }

    // MARK: - Publish (正式版：place -> POST place (必要時) -> POST post)

    @MainActor
    private func publish() async {
        publishError = nil
        isPublishing = true
        defer { isPublishing = false }

        do {
            let coord = detectedCoord ?? vm.locationManager.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

            // 1) 決定 place（必要時建立到後端）
            let place: Place
            if creatingNew {
                place = try await vm.getOrCreatePlace(
                    name: newPlaceName.isEmpty ? "未命名地點" : newPlaceName,
                    description: "", // 你目前 UI 沒有輸入 description，就先空字串
                    coordinate: coord,
                    isPublic: isPublic,
                    type: newPlaceType,
                    tags: normalized(newPlaceTags),
                    dedupRadiusMeters: 30
                )
            } else if let picked = selectedPlace {
                // ⚠️ Apple POI 如果沒 serverId，不能拿去發文
                if picked.origin == .apple {
                    // 你可以選擇：1) 強制建立一個同名 place 到後端；2) 直接擋掉
                    // 我這裡採「自動建立」：用 picked 的 name/coord/type/tags 建到後端
                    place = try await vm.getOrCreatePlace(
                        name: picked.name,
                        description: "",
                        coordinate: picked.coordinate.cl,
                        isPublic: isPublic,
                        type: picked.type,
                        tags: picked.tags,
                        dedupRadiusMeters: 30
                    )
                } else {
                    place = picked
                }
            } else {
                return
            }

            // 2) 建立 post（multipart）
            guard let created = await PostsManager.shared.createPost(
                placeId: place.serverId,
                title: title,
                bodyText: content,
                visibility: isPublic ? .public : .private,
                photoData: photoData
            ) else {
                throw NSError(
                    domain: "PostError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: PostsManager.shared.errorMessage ?? "Create post failed"]
                )
            }

            // 3) 更新 vm 快取（正式版：用 place.serverId 當 key）
            if vm.logsByPlace[place.serverId] == nil {
                vm.logsByPlace[place.serverId] = []
            }
            vm.logsByPlace[place.serverId]?.insert(created, at: 0)

            // 4) 確保 place 在列表（如果你 vm.getOrCreatePlace 已經 upsert 就不用，但保險）
            if !vm.myPlaces.contains(where: { $0.id == place.id }) {
                vm.myPlaces.insert(place, at: 0)
            }
            if isPublic && !vm.communityPlaces.contains(where: { $0.id == place.id }) {
                vm.communityPlaces.insert(place, at: 0)
            }

            dismiss()
        } catch {
            publishError = error.localizedDescription
        }
    }

    // MARK: - Photo loading (single)

    private func reloadPhotoLocally() async {
        var exifCoord: CLLocationCoordinate2D? = nil
        var dataOut: Data? = nil

        if let item = photoItem, let data = try? await item.loadTransferable(type: Data.self) {
            dataOut = data
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                exifCoord = .init(latitude: lat, longitude: lon)
            }
        }

        await MainActor.run {
            self.photoData = dataOut
            self.detectedCoord = exifCoord ?? vm.locationManager.location?.coordinate
        }
    }

    // MARK: - Helpers

    private func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                out.append(t)
            }
        }
        return out
    }

    private func defaultPresetTags(for type: PlaceType) -> [String] {
        switch type {
        case .cafe:
            return ["咖啡","甜點","插座","安靜","閱讀","不限時","手沖","拿鐵"]
        case .restaurant:
            return ["聚餐","小吃","宵夜","排隊","平價","家庭式","米粉湯","湯頭"]
        case .scenic:
            return ["散步","綠地","景點","拍照","親子","夕陽","步道","河濱"]
        case .shop:
            return ["文具","雜貨","手作","逛街","選物","優惠"]
        case .other:
            return ["推薦","常去","乾淨","友善"]
        }
    }
}



// MARK: - Tag Editor + Chips

private struct TagEditor: View {
    let title: String
    @Binding var tags: [String]
    var presetTags: [String] = []

    @State private var input: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)

            HStack(spacing: 8) {
                TextField("輸入後按加入或換行", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { addFromInput() }
                Button {
                    addFromInput()
                } label: {
                    Label("加入", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .disabled(trimmed(input).isEmpty)
            }

            if !tags.isEmpty {
                ChipsGrid(items: tags, removable: true, onTap: { remove($0) })
                    .padding(.top, 2)
            } else {
                Text("尚未新增標籤").foregroundStyle(.secondary)
            }

            let filtered = filteredPresets()
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("建議").font(.subheadline).foregroundStyle(.secondary)
                    ChipsGrid(
                        items: filtered,
                        removable: false,
                        onTap: { toggle($0) },
                        isSelected: { containsCaseInsensitive($0) }
                    )
                }
                .padding(.top, 4)
            }
        }
    }

    private func addFromInput() {
        let t = trimmed(input)
        guard !t.isEmpty else { return }
        add(t)
        input = ""
        focused = true
    }

    private func add(_ t: String) {
        let v = trimmed(t)
        guard !v.isEmpty else { return }
        if !containsCaseInsensitive(v) {
            tags.append(v)
        }
    }
    private func remove(_ t: String) {
        tags.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
    }
    private func toggle(_ t: String) {
        if containsCaseInsensitive(t) { remove(t) } else { add(t) }
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func containsCaseInsensitive(_ t: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(t) == .orderedSame }
    }
    private func filteredPresets() -> [String] {
        let q = trimmed(input)
        guard !q.isEmpty else { return presetTags }
        return presetTags.filter { $0.localizedCaseInsensitiveContains(q) }
    }
}

private struct ChipsGrid: View {
    let items: [String]
    var removable: Bool
    var onTap: (String) -> Void
    var isSelected: ((String) -> Bool)? = nil

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                    HStack(spacing: 6) {
                        if removable {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                        } else if let isSelected {
                            Image(systemName: isSelected(tag) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(tag).font(.subheadline)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
