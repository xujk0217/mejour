//
//  PlaceSheetView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//

import SwiftUI

struct PlaceSheetView: View {
    let place: Place
    @EnvironmentObject private var vm: MapViewModel
    @State private var showEdit = false
    
    private var logs: [LogItem] {
        vm.logsByPlace[place.serverId] ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 26.0, *) {
                    ZStack {
                        GlassContainer { EmptyView() }.opacity(0)
                        GlassCard(cornerRadius: 24) {
                            content
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }
                    .background(.clear)
                } else {
                    content
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle("地點資訊")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadPosts(for: place)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider().opacity(0.2)

                if logs.isEmpty {
                    Text("目前沒有公開日誌").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(logs, id: \.id) { log in
                            Group {
                                if #available(iOS 26.0, *) {
                                    GlassCard(cornerRadius: 16) { logRow(log) }
                                } else {
                                    logRow(log).padding(.vertical, 6)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                GlassPin(icon: place.type.iconName, color: place.type.color)
                VStack(alignment: .leading) {
                    Text(place.name).font(.headline)
                    if place.tags.isEmpty {
                        Text("無標籤").foregroundStyle(.tertiary).font(.caption)
                    }
                }
                Spacer()
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
                .platformButtonStyle()
                .sheet(isPresented: $showEdit) {
                    EditPlaceSheet(vm: vm, place: place)
                }
            }

            if !place.tags.isEmpty {
                ChipsGrid(items: place.tags, removable: false, onTap: { _ in })
            }
        }
    }

    private func logRow(_ log: LogItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(log.title).font(.headline)
            Text("by \(log.authorName)").font(.caption).foregroundStyle(.secondary)

            logPhotoPreview(log)

            Text(log.content)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            HStack {
                Button { /* like */ } label: {
                    Label("\(log.likeCount)", systemImage: "hand.thumbsup")
                }
                .platformButtonStyle()

                NavigationLink {
                    LogDetailView(postId: log.serverId)
                } label: {
                    Label("查看全文", systemImage: "chevron.right")
                }
                .platformButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func logPhotoPreview(_ log: LogItem) -> some View {
        // 1) 後端 URL：photo
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(height: 260)
                        .overlay(ProgressView())

                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 300)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                case .failure:
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(height: 260)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 24, weight: .semibold))
                                Text("照片載入失敗")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )

                @unknown default:
                    EmptyView()
                }
            }
        }
        else {
            RoundedRectangle(cornerRadius: 14)
                .fill(.thinMaterial)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("沒有附上照片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }

}

// MARK: - Local ChipsGrid for header

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
                        Text(tag).font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func platformButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(GlassButtonStyle())
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
