// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Text for the usage bars. Pure functions so they are easy to test.
enum UsageFormat {
    /// How full a bar is, for colour: calm, getting close, or nearly out.
    enum Level: Equatable { case normal, warning, critical }

    static func level(_ fraction: Double) -> Level {
        switch fraction {
        case ..<0.75: .normal
        case ..<0.9: .warning
        default: .critical
        }
    }

    /// Clamped to 0…1; nil and non-finite values stay nil.
    static func clamp(_ fraction: Double?) -> Double? {
        guard let fraction, fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1)
    }

    /// "15% used". Rounds down so a nearly-full bar never reads "100%"
    /// before it is; anything above 0 shows as at least 1%.
    static func percentUsed(_ fraction: Double) -> String {
        "\(wholePercent(fraction))% used"
    }

    /// "85% left".
    static func percentLeft(_ fraction: Double) -> String {
        "\(100 - wholePercent(fraction))% left"
    }

    private static func wholePercent(_ fraction: Double) -> Int {
        let clamped = clamp(fraction) ?? 0
        let percent = Int((clamped * 100).rounded(.down))
        return clamped > 0 && percent == 0 ? 1 : percent
    }

    /// "resets in 2 h 14 m" within a day, otherwise "resets Fri 9:00".
    static func resets(at date: Date, now: Date, estimate: Bool = false, calendar: Calendar = .current)
        -> String
    {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "reset" }
        let prefix = estimate ? "resets in about" : "resets in"
        if seconds < 24 * 3600 {
            let totalMinutes = Int((seconds / 60).rounded(.up))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours == 0 { return "\(prefix) \(minutes) m" }
            return minutes == 0 ? "\(prefix) \(hours) h" : "\(prefix) \(hours) h \(minutes) m"
        }
        var style = Date.FormatStyle(date: .omitted, time: .shortened).weekday(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return "resets \(date.formatted(style))"
    }

    /// "1.2M", "48K", "812".
    static func compact(_ value: Int) -> String {
        guard abs(value) >= 1000 else { return String(value) }
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(1...2)))
    }

    /// "84 messages · 1.2M tokens".
    static func activity(messages: Int, tokens: Int) -> String {
        let noun = messages == 1 ? "message" : "messages"
        return "\(messages) \(noun) · \(compact(tokens)) tokens"
    }

    /// "updated 3 min ago" / "updated just now".
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(48 * 60): return "\(minutes / 60) h ago"
        default: return "\(minutes / (24 * 60)) days ago"
        }
    }
}
