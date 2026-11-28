// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct LogTests {
    @Test func subsystemMatchesBundleIdentifier() {
        #expect(Log.subsystem == "com.dhruvchawla.friday")
    }

    @Test func loggersCanEmit() {
        Log.app.info("test event count=\(1)")
        Log.skills.debug("test")
        Log.connections.debug("test")
        Log.memory.debug("test")
        Log.capture.debug("test")
    }
}
