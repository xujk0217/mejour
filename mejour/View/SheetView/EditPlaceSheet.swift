//
//  EditPlaceSheet.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/11.
//

import SwiftUI

struct EditPlaceSheet: View {
    @ObservedObject var vm: MapViewModel
    @State var place: Place
    @Environment(\.dismiss) private var dismiss

    // 可自行調整的預設標籤
    private let presetTags: [String] = [
        "咖啡","甜點","早午餐","宵夜","小吃","聚餐","安靜","插座","閱讀","散步","綠地","寵物友善","景點","拍照","親子","素食","不限時","排隊","平價","湯頭"
    ]

    @State private var newTagText: String = ""
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("名稱", text: $place.name)
                    Picker("類型", selection: $place.type) {
                        ForEach(PlaceType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("公開到社群", isOn: $place.isPublic)
                }

                Section("標籤") {
                    // 輸入列
                    HStack(spacing: 8) {
                        TextField("輸入標籤後按加入或換行", text: $newTagText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($tagFieldFocused)
                            .onSubmit { addTagFromInput() }

                        Button {
                            addTagFromInput()
                        } label: {
                            Label("加入", systemImage: "plus.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .disabled(trimmed(newTagText).isEmpty)
                    }

                    // 已選標籤（可點移除）
                    if !place.tags.isEmpty {
                        ChipsGrid(items: place.tags, removable: true, onTap: { removeTag($0) })
                            .padding(.top, 4)
                    } else {
                        Text("尚未新增標籤").foregroundStyle(.secondary)
                    }

                    // 建議標籤（可點加入/移除）
                    let filteredPresets = filteredPresetTags()
                    if !filteredPresets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("建議")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ChipsGrid(
                                items: filteredPresets,
                                removable: false,
                                onTap: { toggleTag($0) },
                                isSelected: { tag in
                                    place.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                }
                            )
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .navigationTitle("編輯地點")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        place.tags = normalized(place.tags)
                        vm.updatePlace(place)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    // MARK: - Tag logic

    private func addTagFromInput() {
        let t = trimmed(newTagText)
        guard !t.isEmpty else { return }
        addTag(t)
        newTagText = ""
        tagFieldFocused = true
    }

    private func addTag(_ tag: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !place.tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            place.tags.append(t)
        }
    }

    private func removeTag(_ tag: String) {
        place.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    private func toggleTag(_ tag: String) {
        if place.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            removeTag(tag)
        } else {
            addTag(tag)
        }
    }

    private func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags.map({ trimmed($0) }).filter({ !$0.isEmpty }) {
            let key = t.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                out.append(t)
            }
        }
        return out
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredPresetTags() -> [String] {
        let q = trimmed(newTagText)
        guard !q.isEmpty else { return presetTags }
        return presetTags.filter { $0.localizedCaseInsensitiveContains(q) }
    }
}

// MARK: - Shared ChipsGrid (LazyVGrid Adaptive)

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

