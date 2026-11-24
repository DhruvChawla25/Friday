// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// Remembers where the user dragged the orb, per frontmost app.
struct OrbPositionStore: Sendable {
    static let desktopKey = "desktop"
    private static let defaultsKey = "orbPositions"
    private let suite: String?

    init(suite: String? = nil) { self.suite = suite }

    private var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    func position(for app: String) -> CGPoint? {
        guard let entry = all()[app], entry.count == 2 else { return nil }
        return CGPoint(x: entry[0], y: entry[1])
    }

    func save(_ point: CGPoint, for app: String) {
        var positions = all()
        positions[app] = [point.x, point.y]
        defaults.set(positions, forKey: Self.defaultsKey)
    }

    func reset(_ app: String) {
        var positions = all()
        positions.removeValue(forKey: app)
        defaults.set(positions, forKey: Self.defaultsKey)
    }

    func resetAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func all() -> [String: [Double]] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: [Double]] ?? [:]
    }
}
