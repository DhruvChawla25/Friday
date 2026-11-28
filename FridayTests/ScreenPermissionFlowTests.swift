// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct ScreenPermissionFlowTests {
    @Test func grantedWheneverPreflightSaysSo() {
        for captureWorks in [nil, true, false] as [Bool?] {
            for asked in [true, false] {
                #expect(
                    ScreenPermissionFlow.stage(preflight: true, captureWorks: captureWorks, asked: asked) == .granted)
            }
        }
    }

    @Test func idleBeforeTheUserAsks() {
        #expect(ScreenPermissionFlow.stage(preflight: false, captureWorks: nil, asked: false) == .idle)
        #expect(ScreenPermissionFlow.stage(preflight: false, captureWorks: false, asked: false) == .idle)
    }

    @Test func waitsForSettingsWhenStillOffAfterAsking() {
        #expect(ScreenPermissionFlow.stage(preflight: false, captureWorks: false, asked: true) == .waitingForSettings)
        #expect(ScreenPermissionFlow.stage(preflight: false, captureWorks: nil, asked: true) == .waitingForSettings)
    }

    /// Turned on in System Settings, but this run's preflight is cached.
    @Test func needsRelaunchWhenCaptureWorksButPreflightIsStale() {
        #expect(ScreenPermissionFlow.stage(preflight: false, captureWorks: true, asked: true) == .needsRelaunch)
    }

    @Test func captions() {
        #expect(ScreenPermissionFlow.caption(for: .idle) == nil)
        #expect(ScreenPermissionFlow.caption(for: .granted) == nil)
        #expect(
            ScreenPermissionFlow.caption(for: .waitingForSettings)
                == "Turn on Friday in Screen Recording, then reopen Friday")
        #expect(ScreenPermissionFlow.caption(for: .needsRelaunch)?.contains("reopen Friday") == true)
    }
}
