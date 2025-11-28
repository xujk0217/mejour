//
//  SegmentedScopeBar.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/10.
//

import SwiftUI

struct ScopeSwitcher: View {
    @ObservedObject var vm: MapViewModel
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if #available(iOS 26.0, *) {
                    // iOS 26：放在玻璃容器，系統自帶 Liquid Glass 的 segmented 外觀
                    GlassContainer {
                        Picker("Scope", selection: $vm.scope) {
                            Text("個人").tag(MapScope.mine)
                            Text("社群").tag(MapScope.community)
                        }
                        .pickerStyle(.segmented)
                        .padding(8)
                    }
                } else {
                    // 低於 26：純原生 segmented
                    Picker("Scope", selection: $vm.scope) {
                        Text("個人").tag(MapScope.mine)
                        Text("社群").tag(MapScope.community)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }
            }

            HStack {
                Spacer()
                Button(action: onAdd) {
                    Label("新增日誌", systemImage: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .platformButtonStyle()
                Spacer()
            }
            .padding(.bottom, 8)
        }
        .background(.bar) // 底部浮在地圖上
    }
}

// 簡單玻璃容器（26↑ 看起來接近系統效果；舊版只是薄材質）
struct GlassContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.25)))
            .padding(.horizontal, 16)
    }
}
