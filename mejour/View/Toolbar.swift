//
//  Toolbar.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI

/// iOS 26+：使用（可替換）Liquid Glass 背景與玻璃按鈕
struct Toolbar_iOS26: View {
    @ObservedObject var vm: MapViewModel
    var body: some View {
        ZStack {
            // TODO: 若有 iOS26 官方 Liquid Glass API，替換為官方背景
            if #available(iOS 17.0, *) {
                LiquidGlassBackgroundSimulated()
                    .frame(height: 96)
                    .blur(radius: 10)
                    .padding(.horizontal, 12)
            }

            GlassCard(cornerRadius: 26) {
                HStack(spacing: 16) {
                    Button {
                        vm.scope = .mine; vm.loadData(in: nil)
                    } label: { Label("我的地圖", systemImage: "person.crop.circle") }
                        .buttonStyle(GlassButtonStyle())
                        .tint(vm.scope == .mine ? .primary : .secondary)

                    Spacer(minLength: 8)

                    Button { vm.isPresentingAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                    }
                    .buttonStyle(GlassButtonStyle())

                    Spacer(minLength: 8)

                    Button {
                        vm.scope = .community; vm.loadData(in: nil)
                    } label: { Label("社群地圖", systemImage: "person.3") }
                        .buttonStyle(GlassButtonStyle())
                        .tint(vm.scope == .community ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(.clear)
    }
}

/// iOS 26 以下：簡單原生底部工具列（不使用 Liquid Glass）
struct Toolbar_Simple: View {
    @ObservedObject var vm: MapViewModel
    var body: some View {
        HStack(spacing: 16) {
            Button {
                vm.scope = .mine; vm.loadData(in: nil)
            } label: {
                Label("我的地圖", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button { vm.isPresentingAddSheet = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
            }

            Spacer()

            Button {
                vm.scope = .community; vm.loadData(in: nil)
            } label: {
                Label("社群地圖", systemImage: "person.3")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
