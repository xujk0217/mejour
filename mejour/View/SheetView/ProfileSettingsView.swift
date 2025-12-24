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
    @State private var followIdText = ""
    @State private var followError: String?

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

                Section("追蹤") {
                    HStack(spacing: 8) {
                        TextField("輸入 userId（Int）", text: $followIdText)
                            .keyboardType(.numberPad)

                        Button("追蹤") { submitFollow() }
                            .buttonStyle(.bordered)
                    }

                    if let followError, !followError.isEmpty {
                        Text(followError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("追蹤名單") {
                    if follow.ids.isEmpty {
                        Text("你目前沒有追蹤任何人")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(follow.ids, id: \.self) { id in
                            NavigationLink {
                                FriendProfileView(userId: id)
                            } label: {
                                Text("User #\(id)")
                            }
                        }
                        .onDelete(perform: deleteFollows) // ✅ 用函數，不要用 $follow.remove
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

    private func submitFollow() {
        followError = nil
        let t = followIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(t), id > 0 else {
            followError = "userId 必須是正整數"
            return
        }
        follow.add(id)         // ✅ 不要 $follow.add
        followIdText = ""
    }

    private func deleteFollows(_ indexSet: IndexSet) {
        let ids = follow.ids
        for i in indexSet {
            follow.remove(ids[i])  // ✅ 不要 $follow.remove
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
