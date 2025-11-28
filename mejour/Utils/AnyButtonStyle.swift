//
//  AnyButtonStyle.swift
//  mejour
//
//  Created by 許君愷 on 2025/10/9.
//


import SwiftUI

/// 讓我們能在 #available 分支裡用同一種語法設定不同 ButtonStyle。
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        self.make = { AnyView(style.makeBody(configuration: $0)) }
    }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

