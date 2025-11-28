//
//  AuthManager.swift
//  mejour
//
//  Created by 許君愷 on 2025/11/28.
//


import Foundation

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published private(set) var currentUser: MeUser?
    @Published private(set) var accessToken: String?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let baseURL = URL(string: "https://meejing-backend.vercel.app")!
    
    private init() { }
    
    var isAuthenticated: Bool {
        accessToken != nil && currentUser != nil
    }
    
    // MARK: - Public APIs
    
    /// 用預設帳號登入（先這樣寫死，之後再接 UI）
    func loginDefaultUser() async {
        await login(username: "testadmin", password: "adminadmin")
    }
    
    /// 一般登入（之後如果有登入頁面可以直接重用）
    func login(username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let tokens = try await requestToken(username: username, password: password)
            self.accessToken = tokens.access
            
            let user = try await fetchCurrentUser(accessToken: tokens.access)
            self.currentUser = user
        } catch {
            self.errorMessage = error.localizedDescription
            self.accessToken = nil
            self.currentUser = nil
        }
        
        isLoading = false
    }
    
    func logout() {
        accessToken = nil
        currentUser = nil
        errorMessage = nil
        // 之後如果有 refresh token, /logout API，再一起處理
    }
    
    // MARK: - Private
    
    private func requestToken(username: String, password: String) async throws -> AuthResponse {
        let url = baseURL.appendingPathComponent("/api/auth/token/login/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let body: [String: String] = [
            "username": username,
            "password": password
        ]
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        try validate(response: response, data: data)
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    private func fetchCurrentUser(accessToken: String) async throws -> MeUser {
        let url = baseURL.appendingPathComponent("/api/auth/me/")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        try validate(response: response, data: data)
        
        let decoder = JSONDecoder()
        return try decoder.decode(MeUser.self, from: data)
    }
    
    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            // 方便 debug，用後端回傳的錯誤訊息
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "AuthError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
