////
////  AuthEntryView.swift
////  mejour
////
////  Created by 許君愷 on 2025/12/20.
////
//
//
//import SwiftUI
//
//struct AuthEntryView: View {
//    enum Mode { case login, register }
//
//    @State private var mode: Mode = .login
//
//    @State private var username = ""
//    @State private var email = ""
//    @State private var password = ""
//    @State private var displayName = ""
//
//    @ObservedObject private var auth = AuthManager.shared
//    @Environment(\.dismiss) private var dismiss
//
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 20) {
//
//                Picker("", selection: $mode) {
//                    Text("登入").tag(Mode.login)
//                    Text("註冊").tag(Mode.register)
//                }
//                .pickerStyle(.segmented)
//
//                Group {
//                    TextField("帳號", text: $username)
//                        .textInputAutocapitalization(.never)
//                        .autocorrectionDisabled()
//
//                    if mode == .register {
//                        TextField("Email", text: $email)
//                            .textInputAutocapitalization(.never)
//                        TextField("顯示名稱", text: $displayName)
//                    }
//
//                    SecureField("密碼", text: $password)
//                }
//                .textFieldStyle(.roundedBorder)
//
//                if let err = auth.errorMessage {
//                    Text(err)
//                        .font(.caption)
//                        .foregroundStyle(.red)
//                        .multilineTextAlignment(.center)
//                }
//
//                Button(action: submit) {
//                    if auth.isLoading {
//                        ProgressView()
//                    } else {
//                        Text(mode == .login ? "登入" : "註冊")
//                            .frame(maxWidth: .infinity)
//                    }
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(!canSubmit)
//
//                Spacer()
//            }
//            .padding()
//            .navigationTitle(mode == .login ? "登入" : "註冊")
//            .navigationBarTitleDisplayMode(.inline)
//            .onChange(of: auth.isAuthenticated) { ok in
//                if ok { dismiss() }
//            }
//        }
//    }
//
//    private var canSubmit: Bool {
//        switch mode {
//        case .login:
//            return !username.isEmpty && !password.isEmpty
//        case .register:
//            return !username.isEmpty &&
//                   !email.isEmpty &&
//                   !password.isEmpty &&
//                   !displayName.isEmpty
//        }
//    }
//
//    private func submit() {
//        Task {
//            switch mode {
//            case .login:
//                await auth.login(username: username, password: password)
//            case .register:
//                await auth.register(
//                    username: username,
//                    email: email,
//                    password: password,
//                    displayName: displayName
//                )
//            }
//        }
//    }
//}
