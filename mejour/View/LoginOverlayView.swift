import SwiftUI
import MapKit

struct LoginOverlayView: View {
    @ObservedObject var auth: AuthManager
    
    @State private var showingRegister = false
    @State private var username: String = "test"
    @State private var password: String = "12345678"
    @State private var email: String = ""
    @State private var displayName: String = ""
    @State private var errorMessage: String = ""
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            // 地圖背景
            Map(position: $cameraPosition)
                .ignoresSafeArea()

            // 半透明遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // 登入/註冊卡片（中心）
            if showingRegister {
                registerCard
            } else {
                loginCard
            }
        }
    }

    private var loginCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("登入 覓徑")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("探索和分享你喜歡的地點")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                // 使用者名稱
                VStack(alignment: .leading, spacing: 6) {
                    Text("使用者名稱")
                        .font(.caption)
                        .fontWeight(.semibold)
                    TextField("輸入使用者名稱", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                // 密碼
                VStack(alignment: .leading, spacing: 6) {
                    Text("密碼")
                        .font(.caption)
                        .fontWeight(.semibold)
                    SecureField("輸入密碼", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 錯誤訊息
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 登入按鈕
            Button {
                Task {
                    await login()
                }
            } label: {
                HStack {
                    if auth.isLoading {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                    }
                    Text(auth.isLoading ? "登入中…" : "登入")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(auth.isLoading || username.isEmpty || password.isEmpty)

            Divider()

            // 註冊連結
            HStack(spacing: 8) {
                Text("還沒有帳號？")
                    .font(.caption)
                Button("立即註冊") {
                    showingRegister = true
                    errorMessage = ""
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            }
        }
        .padding(24)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 340)
    }

    private var registerCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("建立帳號")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("加入 Mejour 社群")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                // 顯示名稱
                VStack(alignment: .leading, spacing: 6) {
                    Text("顯示名稱")
                        .font(.caption)
                        .fontWeight(.semibold)
                    TextField("輸入顯示名稱", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                // 使用者名稱
                VStack(alignment: .leading, spacing: 6) {
                    Text("使用者名稱")
                        .font(.caption)
                        .fontWeight(.semibold)
                    TextField("輸入使用者名稱", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                // 電郵
                VStack(alignment: .leading, spacing: 6) {
                    Text("電郵")
                        .font(.caption)
                        .fontWeight(.semibold)
                    TextField("輸入電郵", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                }

                // 密碼
                VStack(alignment: .leading, spacing: 6) {
                    Text("密碼")
                        .font(.caption)
                        .fontWeight(.semibold)
                    SecureField("輸入密碼", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 錯誤訊息
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 註冊按鈕
            Button {
                Task {
                    await register()
                }
            } label: {
                HStack {
                    if auth.isLoading {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                    }
                    Text(auth.isLoading ? "註冊中…" : "建立帳號")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(auth.isLoading || username.isEmpty || password.isEmpty || email.isEmpty || displayName.isEmpty)

            Divider()

            // 返回登入
            HStack(spacing: 8) {
                Text("已有帳號？")
                    .font(.caption)
                Button("返回登入") {
                    showingRegister = false
                    errorMessage = ""
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            }
        }
        .padding(24)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 340)
    }

    private func login() async {
        errorMessage = ""
        await auth.login(username: username, password: password)
        if let err = auth.errorMessage, !err.isEmpty {
            errorMessage = err
        }
    }

    private func register() async {
        errorMessage = ""
        let success = await auth.register(
            username: username,
            email: email,
            password: password,
            displayName: displayName
        )
        
        if success {
            // 註冊成功，自動登入
            await auth.login(username: username, password: password)
            if let err = auth.errorMessage, !err.isEmpty {
                errorMessage = err
            }
        } else if let err = auth.errorMessage, !err.isEmpty {
            errorMessage = err
        }
    }
}

#Preview {
    LoginOverlayView(auth: AuthManager.shared)
}
