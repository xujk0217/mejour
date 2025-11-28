//
//  ProfileSheetView.swift
//  mejour
//
//  Created by 許君愷 on 2025/11/28.
//


import SwiftUI

struct ProfileSheetView: View {
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if let user = auth.currentUser {
                    List {
                        Section("帳號資訊") {
                            HStack {
                                Text("使用者名稱")
                                Spacer()
                                Text(user.username)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("顯示名稱")
                                Spacer()
                                Text(user.displayName)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Email")
                                Spacer()
                                Text(user.email)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("其他") {
                            HStack {
                                Text("UUID")
                                Spacer()
                                Text(user.uuid)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            HStack {
                                Text("可見範圍")
                                Spacer()
                                Text(user.profileVisibility)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在載入個人資料…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("個人資訊")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // 如果還沒登入，可以在這裡觸發預設登入
            if auth.currentUser == nil {
                await auth.loginDefaultUser()
            }
        }
    }
}
