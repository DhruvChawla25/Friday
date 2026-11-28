// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import FoundationModels
import Testing

@testable import Friday

struct AIStatusTests {
    @Test func mapsEveryAvailabilityCase() {
        #expect(AIStatus.map(.available) == .ready)
        #expect(AIStatus.map(.unavailable(.appleIntelligenceNotEnabled)) == .notEnabled)
        #expect(AIStatus.map(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AIStatus.map(.unavailable(.modelNotReady)) == .modelNotReady)
    }

    @Test func labelsArePlainLanguage() {
        #expect(AIStatus.ready.label == "AI: READY")
        #expect(AIStatus.ready.isReady)
        #expect(!AIStatus.notEnabled.isReady)
        #expect(AIStatus.modelNotReady.label.contains("DOWNLOADING"))
    }
}
