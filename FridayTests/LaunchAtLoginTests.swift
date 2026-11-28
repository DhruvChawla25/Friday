// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing
@testable import Friday

private final class FakeLoginItem: LoginItemService {
    var isEnabled = false
    var fails = false
    struct Failure: Error {}
    func register() throws {
        if fails { throw Failure() }
        isEnabled = true
    }
    func unregister() throws {
        if fails { throw Failure() }
        isEnabled = false
    }
}

struct LaunchAtLoginTests {
    @Test func enablesAndDisables() {
        let fake = FakeLoginItem()
        let login = LaunchAtLogin(service: fake)
        #expect(login.set(true))
        #expect(fake.isEnabled)
        #expect(!login.set(false))
        #expect(!fake.isEnabled)
    }

    @Test func failureReportsActualState() {
        let fake = FakeLoginItem()
        fake.fails = true
        #expect(!LaunchAtLogin(service: fake).set(true))
    }
}
