//
//  RootMapView.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//

import SwiftUI
import MapKit

// MARK: - ActiveSheet

enum ActiveSheet: Identifiable, Equatable {
    case place(Place)
    case addLog
    case nearby
    case profile // 個人頁面
    
    var id: String {
        switch self {
        case .place(let p): return "place-\(p.id)"
        case .addLog:       return "addLog"
        case .nearby:       return "nearby"
        case .profile:      return "profile" // 個人頁面
        }
    }
}

// MARK: - RootMapView
private enum MapTab: Int { case mine = 0, community = 1 }

struct RootMapView: View {
    @StateObject private var vm = MapViewModel()

    @State private var activeSheet: ActiveSheet?
    @State private var tagFilter: String = ""

    @SceneStorage("selectedMapTab") private var selectedTab: Int = MapTab.mine.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 我的
            mapContent(scope: .mine)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(MapTab.mine.rawValue)

            // Tab 2: 社群
            mapContent(scope: .community)
                .tabItem { Label("社群", systemImage: "person.3") }
                .tag(MapTab.community.rawValue)
        }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .place(let place):
                PlaceSheetView(place: place)
                    .environmentObject(vm)
                    .presentationDetents(Set([.medium, .large]))
            case .addLog:
                AddLogWizard(vm: vm)
                    .presentationDetents(Set([.large]))
            case .nearby:
                NearbySheet(
                    vm: vm,
                    baseCoord: vm.cameraCenter ?? vm.userCoordinate,   // 以地圖中心為準，退而求其次用我的定位
                    source: vm.scope == .mine ? .mine : .community,
                    tagFilter: $tagFilter
                ) { picked in
                    vm.setCamera(to: picked.coordinate.cl, animated: true)   // 滑動動畫
                    activeSheet = .place(picked)
                }
                .presentationDetents(Set([.medium, .large]))
            case .profile: // 個人頁面
                    ProfileSheetView()
                        .presentationDetents(Set([.medium, .large]))
            }
        }
        .onChange(of: selectedTab) { newValue in
            vm.scope = (newValue == MapTab.mine.rawValue) ? .mine : .community
        }
        .task {
            vm.scope = (selectedTab == MapTab.mine.rawValue) ? .mine : .community
            vm.loadData(in: nil)
        }
    }

    // MARK: - 地圖內容（兩個 Tab 共用，同一份 UI，只換 scope）
    private func mapContent(scope: MapScope) -> some View {
        ZStack(alignment: .bottom) {
            Map(position: $vm.cameraPosition, selection: $vm.selectedPlace) {
                if let me = vm.userCoordinate {
                    Annotation("me", coordinate: me) {
                        MyUserPuck(heading: vm.userHeading?.trueHeading)
                            .zIndex(9999)
                            .allowsHitTesting(false)
                    }
                }
                ForEach(scope == .mine ? vm.myPlaces : vm.communityPlaces, id: \.id) { place in
                    Annotation(place.name, coordinate: place.coordinate.cl) {
                        GlassPin(icon: place.type.iconName, color: place.type.color)
                            .onTapGesture { activeSheet = .place(place) }
                    }
                }
            }
            .ignoresSafeArea()
            .onMapCameraChange { ctx in
                vm.cameraCenter = ctx.region.center
            }

            // 右上角圓形浮動鈕（回定位／附近列表）
            VStack(spacing: 10) {
                // 個人資訊
                Button {
                    activeSheet = .profile
                } label: {
                    CircleButtonIcon(systemName: "person.circle")
                }
                Button {
                    if let me = vm.userCoordinate {
                        vm.setCamera(to: me, animated: true)   // 會滑動回去
                    } else {
                        vm.cameraPosition = .userLocation(fallback: .automatic) // 初次定位 fallback
                    }
                } label: { CircleButtonIcon(systemName: "location.fill") }

                Button { activeSheet = .nearby } label: {
                    CircleButtonIcon(systemName: "list.bullet")
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // 右下角「＋」浮動鈕
            Button {
                activeSheet = .addLog
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25)))
                    .shadow(radius: 10, y: 6)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .navigationTitle(scope == .mine ? "我的地圖" : "社群地圖")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 不再使用 .bordered / .borderedProminent，統一自訂外觀
private struct GlassButtonCompat: ViewModifier {
    var prominent: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(prominent ? Color.accentColor.opacity(0.15) : Color.clear)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
    }
}


// MARK: - 自訂底部 Bar（Deliquified Glass）

private struct DeliquifiedGlassBar: View {
    @Binding var selection: MapScope
    var onAdd: () -> Void

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 10) {
            // 左：雙分頁 capsule
            HStack(spacing: 0) {
                CapsuleTabButton(
                    title: "我的",
                    systemImage: "person.crop.circle",
                    isSelected: selection == .mine,
                    ns: ns
                ) { selection = .mine }

                CapsuleTabButton(
                    title: "社群",
                    systemImage: "person.3",
                    isSelected: selection == .community,
                    ns: ns
                ) { selection = .community }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.22)))
                    .background(GlassLiquidLayer(cornerRadius: 24))
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)

            // 右：大圓「＋」
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25)))
                    .background(GlassLiquidLayer(shape: Circle()))
                    .shadow(radius: 10, y: 6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
    }
}

// 一層可重用的液態玻璃動畫：mesh 斑點 + 高光掃描
private struct GlassLiquidLayer: View {
    let shape: AnyShape

    init(cornerRadius: CGFloat) {
        self.shape = AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    init<S: Shape>(shape: S) {
        self.shape = AnyShape(shape)
    }

    var body: some View {
        ZStack {
            LiquidGlowOverlay(intensity: 0.6, speed: 0.22)
                .blur(radius: 12)
                .blendMode(.plusLighter)
            ShimmerSweep(opacity: 0.5, duration: 4.2)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .clipShape(shape)
    }
}

private struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ s: S) { _path = { s.path(in: $0) } }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

// 流動光斑
private struct LiquidGlowOverlay: View {
    var intensity: Double = 0.5
    var speed: Double = 0.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * speed
            Canvas { ctx, size in
                let blobs: [(CGPoint, CGFloat, Color)] = [
                    (p(t, size, 0.0,  0.0, 60), 120, .mint),
                    (p(t, size, 1.3, -0.6, 40), 100, .cyan),
                    (p(t, size, -0.9, 0.8, 20),  90, .blue),
                    (p(t, size, 0.6,  1.2, -30), 80, .teal)
                ]
                for (center, radius, color) in blobs {
                    let shading = GraphicsContext.Shading.radialGradient(
                        .init(colors: [
                            color.opacity(0.50 * intensity),
                            color.opacity(0.18 * intensity),
                            .clear
                        ]),
                        center: center,
                        startRadius: 2,
                        endRadius: radius
                    )
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius,
                                                    y: center.y - radius,
                                                    width: radius * 2,
                                                    height: radius * 2)), with: shading)
                }
            }
        }
    }

    private func p(_ t: TimeInterval, _ size: CGSize, _ ax: Double, _ ay: Double, _ phase: Double) -> CGPoint {
        let w = size.width, h = size.height
        let x = w * 0.5 + CGFloat(sin(t + ax) * (w * 0.32)) + CGFloat(cos(t * 0.7 + ax + phase) * (w * 0.12))
        let y = h * 0.5 + CGFloat(cos(t * 0.9 + ay) * (h * 0.28)) + CGFloat(sin(t * 1.2 + ay + phase) * (h * 0.10))
        return CGPoint(x: x, y: y)
    }
}

// 高光掃過
private struct ShimmerSweep: View {
    var opacity: Double = 0.4
    var duration: Double = 4.0

    @State private var x: CGFloat = -1.0

    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(opacity), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .mask(
            Rectangle()
                .fill(.white)
                .scaleEffect(x: 0.35, y: 1.2, anchor: .center)
                .rotationEffect(.degrees(18))
                .offset(x: x * 220)
        )
        .onAppear {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                x = 1.4
            }
        }
    }
}

private struct CapsuleTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let ns: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title).font(.footnote)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(width: 96, height: 44)
            .background(alignment: .center) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .matchedGeometryEffect(id: "tab-indicator", in: ns)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.28)))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 浮動圓形按鈕樣式 / 我的藍點

private struct CircleButtonIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.25)))
            .shadow(radius: 8, y: 4)
    }
}

private struct MyUserPuck: View {
    let heading: CLLocationDirection?
    var body: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.18)).frame(width: 40, height: 40)
            Circle().fill(Color.blue).frame(width: 12, height: 12)
            if let deg = heading {
                Triangle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 14)
                    .offset(y: -18)
                    .rotationEffect(.degrees(deg))
            }
        }
        .shadow(radius: 4, y: 2)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.minY))
        p.addLine(to: .init(x: r.maxX, y: r.maxY))
        p.addLine(to: .init(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// NearbySheet.swift
struct NearbySheet: View {
    @ObservedObject var vm: MapViewModel
    let baseCoord: CLLocationCoordinate2D?
    let source: MapViewModel.PlaceSource
    @Binding var tagFilter: String
    var onPick: (Place) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("輸入標籤過濾（可留白）", text: $tagFilter)
                        .textFieldStyle(.roundedBorder)
                    Button("清除") { tagFilter = "" }
                        .buttonStyle(.bordered)
                }
                .padding()

                List {
                    if let c = baseCoord {
                        let nearby = vm.nearestPlaces(
                            from: c,
                            source: source,                 // ← 依目前分頁（我的/社群）
                            limit: 50,
                            tagFilter: tagFilter,
                            radiusMeters: .greatestFiniteMagnitude
                        )
                        ForEach(nearby, id: \.id) { place in
                            Button { onPick(place) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: place.type.iconName)
                                        .foregroundStyle(place.type.color)
                                    VStack(alignment: .leading) {
                                        Text(place.name).font(.headline)
                                        Text(place.tags.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else {
                        Text("尚未取得地圖位置").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("附近的地點")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

