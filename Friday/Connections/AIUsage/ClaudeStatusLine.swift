// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Claude's real plan limits, as Claude Code passes them to its status line
/// command (`rate_limits.fiveHour` / `seven_day`: `used_percentage` 0–100
/// and `resets_at` in Unix seconds). `Scripts/friday-statusline.sh` saves
/// that part to `~/.claude/friday/rate-limits.json`; Friday only reads it.
enum ClaudeStatusLine {
    static let snapshotPath = ".claude/friday/rate-limits.json"

    struct Limit: Equatable, Sendable {
        var usedPercent: Double
        var resetsAt: Date?
    }

    struct Snapshot: Equatable, Sendable {
        var fiveHour: Limit?
        var sevenDay: Limit?
        var capturedAt: Date?
    }

    private struct File: Decodable {
        struct Limits: Decodable {
            struct Window: Decodable {
                var usedPercentage: Double?
                var resetsAt: Double?
            }
            var fiveHour: Window?
            var sevenDay: Window?
        }
        var capturedAt: Double?
        var rateLimits: Limits?
    }

    /// Parses the saved snapshot (or a raw status line JSON input, which has
    /// the same `rate_limits` shape). Nil if corrupt or without limits.
    static func parse(_ data: Data) -> Snapshot? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(File.self, from: data), let limits = file.rateLimits else {
            return nil
        }
        func limit(_ window: File.Limits.Window?) -> Limit? {
            guard let percent = window?.usedPercentage, percent.isFinite else { return nil }
            return Limit(usedPercent: percent, resetsAt: window?.resetsAt.map { Date(timeIntervalSince1970: $0) })
        }
        let snapshot = Snapshot(
            fiveHour: limit(limits.fiveHour), sevenDay: limit(limits.sevenDay),
            capturedAt: file.capturedAt.map { Date(timeIntervalSince1970: $0) })
        return snapshot.fiveHour == nil && snapshot.sevenDay == nil ? nil : snapshot
    }

    /// Reads the snapshot from the user's home folder. Falls back to the
    /// file's modification time when it has no `captured_at`.
    static func read(home: URL) -> Snapshot? {
        let url = home.appending(path: snapshotPath)
        guard let data = try? Data(contentsOf: url), var snapshot = parse(data) else { return nil }
        if snapshot.capturedAt == nil {
            snapshot.capturedAt =
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        return snapshot
    }

    /// The limit as it stands at `now`: once its reset time has passed the
    /// old percentage no longer applies, so it reads as fresh (0 % used).
    static func current(_ limit: Limit, now: Date) -> Limit {
        guard let reset = limit.resetsAt, reset <= now else { return limit }
        return Limit(usedPercent: 0, resetsAt: nil)
    }
}
