// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Answers "what time is it", "what's the date", "what day is it".
struct TimeSkill: Skill {
    let name = "Time"
    let example = "what time is it"

    var now: @Sendable () -> Date = { .now }
    var locale: Locale = .autoupdatingCurrent
    var timeZone: TimeZone = .autoupdatingCurrent

    func canHandle(_ command: Command) -> Bool {
        asksTime(command) || asksDate(command)
    }

    func handle(_ command: Command) async -> String {
        let date = now()
        var lines: [String] = []
        if asksTime(command) {
            let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
            lines.append("It is \(date.formatted(style)).")
        }
        if asksDate(command) {
            let style = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: timeZone)
            lines.append("Today is \(date.formatted(style)).")
        }
        return lines.joined(separator: " ")
    }

    private func asksTime(_ command: Command) -> Bool {
        command.contains(word: "time")
    }

    private func asksDate(_ command: Command) -> Bool {
        command.contains(word: "date") || command.contains(word: "today")
            || command.normalized.contains("what day")
    }
}
