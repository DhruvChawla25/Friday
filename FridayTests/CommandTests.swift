// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct CommandTests {
    @Test func normalizesCaseWhitespaceAndPunctuation() {
        let command = Command("  What TIME is it?  ")
        #expect(command.normalized == "what time is it")
        #expect(command.words == ["what", "time", "is", "it"])
        #expect(command.raw == "What TIME is it?")
    }

    @Test func extractsArgumentPreservingCase() {
        let command = Command("Open Google Chrome.")
        #expect(command.argument(after: "open") == "Google Chrome")
        #expect(command.argument(after: "launch") == nil)
    }

    @Test func emptyArgumentIsNil() {
        #expect(Command("open").argument(after: "open") == nil)
    }
}
