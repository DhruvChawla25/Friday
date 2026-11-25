// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import Testing

@testable import Friday

struct OrbPositionStoreTests {
    private func withStore(_ body: (OrbPositionStore, UserDefaults) -> Void) {
        let suite = "friday.tests.orb.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(OrbPositionStore(suite: suite), defaults)
    }

    @Test func savesAndReadsBack() {
        withStore { store, _ in
            #expect(store.position(for: "Safari") == nil)
            store.save(CGPoint(x: 10, y: 20.5), for: "Safari")
            #expect(store.position(for: "Safari") == CGPoint(x: 10, y: 20.5))
        }
    }

    @Test func resetRemovesOnlyThatApp() {
        withStore { store, _ in
            store.save(CGPoint(x: 1, y: 2), for: "Safari")
            store.save(CGPoint(x: 3, y: 4), for: "Notes")
            store.reset("Safari")
            #expect(store.position(for: "Safari") == nil)
            #expect(store.position(for: "Notes") == CGPoint(x: 3, y: 4))
        }
    }

    @Test func resetAllClearsEverything() {
        withStore { store, _ in
            store.save(CGPoint(x: 1, y: 2), for: "Safari")
            store.save(CGPoint(x: 3, y: 4), for: OrbPositionStore.desktopKey)
            store.resetAll()
            #expect(store.position(for: "Safari") == nil)
            #expect(store.position(for: OrbPositionStore.desktopKey) == nil)
        }
    }

    @Test func malformedDataReturnsNil() {
        withStore { store, defaults in
            defaults.set(["Safari": [1.0]], forKey: "orbPositions")
            #expect(store.position(for: "Safari") == nil)
            defaults.set(["Safari": "oops"], forKey: "orbPositions")
            #expect(store.position(for: "Safari") == nil)
            defaults.set("not a dictionary", forKey: "orbPositions")
            #expect(store.position(for: "Safari") == nil)
        }
    }

    @Test func savingOverCorruptDataRecovers() {
        withStore { store, defaults in
            defaults.set("garbage", forKey: "orbPositions")
            store.save(CGPoint(x: 5, y: 6), for: "Mail")
            #expect(store.position(for: "Mail") == CGPoint(x: 5, y: 6))
        }
    }
}
