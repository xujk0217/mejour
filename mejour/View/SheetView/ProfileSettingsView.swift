//
//  ProfileSettingsView.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/20.
//


import SwiftUI

import SwiftUI

struct ProfileSettingsView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var follow = FollowStore.shared   // ✅ 改這行
    @Environment(\.dismiss) private var dismiss

    @State private var showAuthSheet = false

    var onNeedAuth: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("帳號") {
                    if let me = auth.currentUser, auth.isAuthenticated {
                        row(key: "Username", value: me.username)
                        row(key: "Display Name", value: me.displayName)
                        row(key: "Email", value: me.email)
                    } else {
                        Text("未登入").foregroundStyle(.secondary)
                    }
                }

                Section {
                    if auth.isAuthenticated {
                        Button(role: .destructive) {
                            auth.logout()
                            onNeedAuth()
                            showAuthSheet = true
                        } label: {
                            Text("登出")
                        }
                    } else {
                        Button {
                            showAuthSheet = true
                        } label: {
                            Text("登入或註冊")
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showAuthSheet) {
                AuthSheetView {
                    showAuthSheet = false
                    onNeedAuth()
                }
            }
        }
    }

    private func row(key: String, value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
