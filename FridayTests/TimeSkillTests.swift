// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

struct TimeSkillTests {
    // 25 Nov 2026, 14:05 UTC
    let skill = TimeSkill(
        now: { Date(timeIntervalSince1970: 1_795_615_500) },
        locale: Locale(identifier: "en_GB"),
        timeZone: TimeZone(identifier: "UTC")!
    )

    @Test(arguments: ["what time is it", "Time?", "tell me the date", "what day is it", "today"])
    func handlesTimeQuestions(_ text: String) {
        #expect(skill.canHandle(Command(text)))
    }

    @Test(arguments: ["open chrome", "timer for 5 minutes", "remember this"])
    func ignoresOtherCommands(_ text: String) {
        #expect(!skill.canHandle(Command(text)))
    }

    @Test func repliesWithTime() async {
        #expect(await skill.handle(Command("what time is it")) == "It is 14:05.")
    }

    @Test func repliesWithDate() async {
        #expect(await skill.handle(Command("what's the date")) == "Today is Wednesday, 25 November 2026.")
    }
}
