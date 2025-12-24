//
//  FollowStore.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/20.
//

import Foundation

@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()

    @Published private(set) var ids: [Int] = []

    private let key = "follow.userIds"

    private init() {
        if let arr = UserDefaults.standard.array(forKey: key) as? [Int] {
            self.ids = arr
        }
    }

    func add(_ id: Int) {
        guard id > 0 else { return }
        if !ids.contains(id) {
            ids.append(id)
            persist()
        }
    }

    func remove(_ id: Int) {
        ids.removeAll { $0 == id }
        persist()
    }

    func contains(_ id: Int) -> Bool {
        ids.contains(id)
    }

    private func persist() {
        UserDefaults.standard.set(ids, forKey: key)
    }
}
