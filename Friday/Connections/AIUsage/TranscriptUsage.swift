// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Token usage from the JSONL transcripts Claude Code (`~/.claude/projects`)
/// and Qoder (`~/.qoder/projects`) write. Only each assistant reply's
/// timestamp, IDs and `usage` numbers are decoded; message text is skipped.
enum TranscriptUsage {
    struct Event: Equatable, Sendable {
        var date: Date
        var input = 0
        var output = 0
        var cacheCreation = 0
        var cacheRead = 0
        /// Qoder only: credits charged for this reply.
        var credits: Double?

        /// Tokens that count as real work: input, output and cache writes.
        /// Cache reads are left out because they are re-sent context.
        var tokens: Int { input + output + cacheCreation }
    }

    /// One block of activity, like Claude's 5-hour session.
    struct Window: Equatable, Sendable {
        var start: Date
        var end: Date
        var messages: Int
        var tokens: Int
        var credits: Double
        var lastActivity: Date
    }

    // MARK: Parsing

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var inputTokens: Int?
                var outputTokens: Int?
                var cacheCreationInputTokens: Int?
                var cacheReadInputTokens: Int?
                var credits: Double?
            }
            var id: String?
            var model: String?
            var usage: Usage?
        }
        var type: String?
        var timestamp: String?
        var requestId: String?
        var message: Message?
    }

    private static let usageMarker = Data(#""usage""#.utf8)

    /// Assistant replies in one JSONL file, de-duplicated (Claude Code writes
    /// one line per content block, each repeating the reply's usage). Corrupt
    /// or unrelated lines are skipped.
    static func events(fromJSONL data: Data) -> [Event] {
        var byKey: [String: Event] = [:]
        var unkeyed: [Event] = []
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard line.range(of: usageMarker) != nil,
                let entry = try? decoder.decode(Line.self, from: line),
                entry.type == "assistant",
                let message = entry.message, let usage = message.usage,
                message.model != "<synthetic>",
                let stamp = entry.timestamp, let date = parseDate(stamp)
            else { continue }
            let event = Event(
                date: date,
                input: usage.inputTokens ?? 0,
                output: usage.outputTokens ?? 0,
                cacheCreation: usage.cacheCreationInputTokens ?? 0,
                cacheRead: usage.cacheReadInputTokens ?? 0,
                credits: usage.credits
            )
            if let id = message.id {
                byKey["\(id)|\(entry.requestId ?? "")"] = event
            } else {
                unkeyed.append(event)
            }
        }
        return (Array(byKey.values) + unkeyed).sorted { $0.date < $1.date }
    }

    /// Events from every `.jsonl` file under `directory` changed since `since`.
    static func events(inDirectory directory: URL, modifiedSince since: Date) -> [Event] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        var events: [Event] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                (values.contentModificationDate ?? .distantPast) >= since,
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { continue }
            events += Self.events(fromJSONL: data).filter { $0.date >= since }
        }
        return events.sorted { $0.date < $1.date }
    }

    static func parseDate(_ string: String) -> Date? {
        (try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: .iso8601))
    }

    // MARK: Windows

    /// The rolling window that is open at `now`, if any. A window starts at
    /// the first reply after the previous one ended (rounded down to the
    /// hour, which is how Claude's 5-hour sessions line up) and lasts
    /// `length`. Events must be sorted by date.
    static func activeWindow(
        events: [Event], now: Date, length: TimeInterval = 5 * 3600, calendar: Calendar = .current
    ) -> Window? {
        var current: Window?
        for event in events where event.date <= now {
            if let open = current, event.date < open.end {
                current?.messages += 1
                current?.tokens += event.tokens
                current?.credits += event.credits ?? 0
                current?.lastActivity = event.date
            } else {
                let start = calendar.dateInterval(of: .hour, for: event.date)?.start ?? event.date
                current = Window(
                    start: start, end: start + length, messages: 1, tokens: event.tokens,
                    credits: event.credits ?? 0, lastActivity: event.date)
            }
        }
        guard let current, now < current.end else { return nil }
        return current
    }

    /// Totals for events in `[start, end)`.
    static func totals(events: [Event], from start: Date, to end: Date) -> (messages: Int, tokens: Int, credits: Double)
    {
        let inRange = events.filter { $0.date >= start && $0.date < end }
        return (inRange.count, inRange.reduce(0) { $0 + $1.tokens }, inRange.reduce(0) { $0 + ($1.credits ?? 0) })
    }
}
