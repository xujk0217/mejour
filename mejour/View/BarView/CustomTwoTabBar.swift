//
//  TwoTabItem.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/10.
//


import SwiftUI

struct TwoTabItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let systemImage: String
    let scope: MapScope
}

struct CustomTwoTabBar: View {
    @Binding var selection: MapScope
    private let items: [TwoTabItem] = [
        .init(title: "個人", systemImage: "person.crop.circle", scope: .mine),
        .init(title: "朋友", systemImage: "person.2", scope: .community),
        .init(title: "社群", systemImage: "person.3", scope: .community)
    ]

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        selection = item.scope
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.title).font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selection == item.scope ? .primary : .secondary)
                    .background(
                        ZStack {
                            if selection == item.scope {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .matchedGeometryEffect(id: "indicator", in: ns)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25)))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.25)))
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
        .padding(.horizontal, 16)
    }
}
