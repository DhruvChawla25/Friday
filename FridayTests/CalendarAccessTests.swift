// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import EventKit
import Testing

@testable import Friday

@Suite struct CalendarAccessTests {
    @Test func grantedStatesLoadWithoutPrompting() {
        #expect(CalendarSource.Access(.fullAccess) == .granted)
        #expect(CalendarSource.Access(.authorized) == .granted)
    }

    @Test func deniedStates() {
        #expect(CalendarSource.Access(.denied) == .denied)
        #expect(CalendarSource.Access(.restricted) == .denied)
    }

    @Test func undeterminedAndWriteOnlyNeedPrompt() {
        #expect(CalendarSource.Access(.notDetermined) == .needsPrompt)
        #expect(CalendarSource.Access(.writeOnly) == .needsPrompt)
    }
}
