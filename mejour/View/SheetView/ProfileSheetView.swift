////
////  ProfileSheetView.swift
////  mejour
////
////  Created by 許君愷 on 2025/11/28.
////
//
//
//import SwiftUI
//
//enum ProfileTab: Int {
//    case myPosts = 0
//    case liked = 1
//    case saved = 2
//    
//    var title: String {
//        switch self {
//        case .myPosts: return "我的發文"
//        case .liked: return "按愛心"
//        case .saved: return "收藏"
//        }
//    }
//}
//
//struct ProfileSheetView: View {
//    @ObservedObject private var auth = AuthManager.shared
//    @State private var selectedTab: ProfileTab = .myPosts
//
//    var body: some View {
//        NavigationStack {
//            Group {
//                if let user = auth.currentUser {
//                    VStack(spacing: 0) {
//                        // MARK: - 個人資料頭部
//                        VStack(spacing: 12) {
//                            HStack(spacing: 16) {
//                                // 頭像
//                                if let avatarUrl = user.avatar, let url = URL(string: avatarUrl) {
//                                    AsyncImage(url: url) { phase in
//                                        switch phase {
//                                        case .empty:
//                                            Circle()
//                                                .fill(.thinMaterial)
//                                                .frame(width: 60, height: 60)
//                                                .overlay(ProgressView())
//                                        case .success(let image):
//                                            image
//                                                .resizable()
//                                                .scaledToFill()
//                                                .frame(width: 60, height: 60)
//                                                .clipShape(Circle())
//                                        case .failure:
//                                            Circle()
//                                                .fill(.thinMaterial)
//                                                .frame(width: 60, height: 60)
//                                                .overlay(
//                                                    Image(systemName: "person.crop.circle")
//                                                        .font(.system(size: 30))
//                                                        .foregroundStyle(.secondary)
//                                                )
//                                        @unknown default:
//                                            EmptyView()
//                                        }
//                                    }
//                                } else {
//                                    Circle()
//                                        .fill(.thinMaterial)
//                                        .frame(width: 60, height: 60)
//                                        .overlay(
//                                            Image(systemName: "person.crop.circle")
//                                                .font(.system(size: 30))
//                                                .foregroundStyle(.secondary)
//                                        )
//                                }
//                                
//                                // 個人資訊
//                                VStack(alignment: .leading, spacing: 4) {
//                                    Text(user.displayName)
//                                        .font(.headline)
//                                    Text("@\(user.username)")
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                }
//                                
//                                Spacer()
//                            }
//                            
//                            // 統計數據
//                            HStack(spacing: 0) {
//                                StatItem(number: "12", label: "探索地點")
//                                Divider()
//                                    .frame(height: 30)
//                                StatItem(number: "8", label: "發post 數")
//                            }
//                            .padding(.vertical, 12)
//                        }
//                        .padding(16)
//                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
//                        .padding(12)
//                        
//                        // MARK: - 分頁切換按鈕
//                        HStack(spacing: 0) {
//                            ForEach([ProfileTab.myPosts, .liked, .saved], id: \.rawValue) { tab in
//                                Button {
//                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
//                                        selectedTab = tab
//                                    }
//                                } label: {
//                                    VStack(spacing: 4) {
//                                        Text(tab.title)
//                                            .font(.subheadline)
//                                            .fontWeight(.semibold)
//                                    }
//                                    .frame(maxWidth: .infinity)
//                                    .padding(.vertical, 12)
//                                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
//                                    .background(
//                                        selectedTab == tab ?
//                                        AnyView(
//                                            RoundedRectangle(cornerRadius: 12)
//                                                .fill(.ultraThinMaterial)
//                                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25)))
//                                        ) : AnyView(EmptyView())
//                                    )
//                                }
//                            }
//                        }
//                        .padding(8)
//                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
//                        .padding(.horizontal, 12)
//                        .padding(.vertical, 8)
//                        
//                        // MARK: - 分頁內容
//                        TabView(selection: $selectedTab) {
//                            ProfilePostsTab()
//                                .tag(ProfileTab.myPosts)
//                            
//                            ProfileLikedTab()
//                                .tag(ProfileTab.liked)
//                            
//                            ProfileSavedTab()
//                                .tag(ProfileTab.saved)
//                        }
//                        .tabViewStyle(.page(indexDisplayMode: .never))
//                        
//                        Spacer()
//                    }
//                    .navigationTitle("個人資訊")
//                    .navigationBarTitleDisplayMode(.inline)
//                } else {
//                    VStack(spacing: 12) {
//                        ProgressView()
//                        Text("正在載入個人資料…")
//                            .foregroundStyle(.secondary)
//                    }
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .navigationTitle("個人資訊")
//                    .navigationBarTitleDisplayMode(.inline)
//                }
//            }
//        }
//        .task {
//            if auth.currentUser == nil {
//                await auth.loginDefaultUser()
//            }
//        }
//    }
//}
//
//// MARK: - 統計數據項目
//private struct StatItem: View {
//    let number: String
//    let label: String
//    
//    var body: some View {
//        VStack(spacing: 4) {
//            Text(number)
//                .font(.headline)
//                .fontWeight(.bold)
//            Text(label)
//                .font(.caption2)
//                .foregroundStyle(.secondary)
//        }
//        .frame(maxWidth: .infinity)
//    }
//}
//
//// MARK: - 我的發文頁面
//private struct ProfilePostsTab: View {
//    var body: some View {
//        VStack(spacing: 12) {
//            ScrollView {
//                VStack(spacing: 10) {
//                    ForEach(0..<5, id: \.self) { index in
//                        PostCardPlaceholder(title: "我的發文 \(index + 1)")
//                    }
//                }
//                .padding(12)
//            }
//        }
//    }
//}
//
//// MARK: - 按愛心頁面
//private struct ProfileLikedTab: View {
//    var body: some View {
//        VStack(spacing: 12) {
//            ScrollView {
//                VStack(spacing: 10) {
//                    ForEach(0..<3, id: \.self) { index in
//                        PostCardPlaceholder(title: "按愛心的發文 \(index + 1)")
//                    }
//                }
//                .padding(12)
//            }
//        }
//    }
//}
//
//// MARK: - 收藏頁面
//private struct ProfileSavedTab: View {
//    var body: some View {
//        VStack(spacing: 12) {
//            ScrollView {
//                VStack(spacing: 10) {
//                    ForEach(0..<4, id: \.self) { index in
//                        PostCardPlaceholder(title: "收藏的發文 \(index + 1)")
//                    }
//                }
//                .padding(12)
//            }
//        }
//    }
//}
//
//// MARK: - 發文卡片佔位符
//private struct PostCardPlaceholder: View {
//    let title: String
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            HStack(spacing: 10) {
//                Circle()
//                    .fill(.thinMaterial)
//                    .frame(width: 40, height: 40)
//                
//                VStack(alignment: .leading, spacing: 2) {
//                    Text("作者名稱")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                    Text(title)
//                        .font(.subheadline)
//                        .fontWeight(.semibold)
//                }
//                
//                Spacer()
//                
//                Image(systemName: "heart")
//                    .foregroundStyle(.secondary)
//            }
//            
//            RoundedRectangle(cornerRadius: 8)
//                .fill(.thinMaterial)
//                .frame(height: 120)
//            
//            HStack(spacing: 12) {
//                Label("10", systemImage: "hand.thumbsup")
//                    .font(.caption2)
//                    .foregroundStyle(.secondary)
//                Spacer()
//                Button("查看全文") {}
//                    .font(.caption2)
//                    .foregroundStyle(.blue)
//            }
//        }
//        .padding(12)
//        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
//        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2)))
//    }
//}
