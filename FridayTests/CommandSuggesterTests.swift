// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct CommandSuggesterTests {
    let examples = ["open WhatsApp", "what time is it", "remember <text>"]

    @Test func suggestsForTypos() {
        #expect(CommandSuggester.suggest(for: "opne whatsap", examples: examples) == "open whatsapp")
        #expect(CommandSuggester.suggest(for: "wat time is it", examples: examples) == "what time is it")
    }

    @Test func noSuggestionForUnrelatedInput() {
        #expect(CommandSuggester.suggest(for: "make me a sandwich", examples: examples) == nil)
        #expect(CommandSuggester.suggest(for: "", examples: examples) == nil)
    }

    @Test func editDistance() {
        #expect(CommandSuggester.editDistance("kitten", "sitting") == 3)
    }
}
