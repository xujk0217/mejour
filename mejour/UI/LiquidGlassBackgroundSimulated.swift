//
//  LiquidGlassBackgroundSimulated.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI

@available(iOS 17.0, *)
struct LiquidGlassBackgroundSimulated: View {
    @State private var anim = false
    var body: some View {
        MeshGradient(
            width: 4, height: 4,
            points: [
                .init(x: 0.1, y: 0.2), .init(x: 0.5, y: 0.1), .init(x: 0.9, y: 0.2), .init(x: 0.2, y: 0.8),
                .init(x: 0.4, y: 0.6), .init(x: 0.6, y: 0.9), .init(x: 0.8, y: 0.7), .init(x: 0.5, y: 0.5),
                .init(x: 0.15, y: 0.6), .init(x: 0.75, y: 0.35), .init(x: 0.35, y: 0.3), .init(x: 0.9, y: 0.85),
                .init(x: 0.1, y: 0.95), .init(x: 0.95, y: 0.1), .init(x: 0.65, y: 0.2), .init(x: 0.4, y: 0.85),
            ],
            colors: [
                .white.opacity(0.35), .white.opacity(0.18), .white.opacity(0.12), .clear,
                .white.opacity(0.28), .white.opacity(0.15), .white.opacity(0.09), .clear,
                .white.opacity(0.3),  .white.opacity(0.2),  .white.opacity(0.1),  .clear,
                .white.opacity(0.22), .white.opacity(0.16), .white.opacity(0.08), .clear
            ]
        )
        .blur(radius: 16)
        .blendMode(.plusLighter)
        .opacity(0.9)
        .scaleEffect(anim ? 1.02 : 0.98)
        .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: anim)
        .onAppear { anim = true }
        .allowsHitTesting(false)
    }
}

struct ConditionalTransparentBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }
}
