// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Qoder: its agent writes Claude-Code-style transcripts to
/// `~/.qoder/projects/**/*.jsonl`, and each reply's `usage` includes the
/// `credits` it cost. The plan's credit allowance is only on Qoder's servers.
struct QoderUsageProvider: UsageProvider {
    let tool = AITool.qoder
    static let projectsPath = ".qoder/projects"

    func usage(in env: UsageEnvironment) -> ToolUsage {
        let hasData = env.exists(Self.projectsPath)
        guard hasData || env.isAppInstalled(tool) else { return .notInstalled(tool) }

        let monthStart = env.calendar.dateInterval(of: .month, for: env.now)?.start ?? env.now
        let dayStart = env.calendar.startOfDay(for: env.now)
        let events = TranscriptUsage.events(inDirectory: env.url(Self.projectsPath), modifiedSince: monthStart)
        return ToolUsage(
            tool: tool,
            isInstalled: true,
            isLive: env.isRunning(tool),
            liveDetail: env.isRunning(tool) ? "App open" : nil,
            meters: Self.meters(events: events, dayStart: dayStart, monthStart: monthStart, now: env.now),
            source: "Local Qoder transcripts",
            lastActive: events.last?.date
        )
    }

    static func meters(events: [TranscriptUsage.Event], dayStart: Date, monthStart: Date, now: Date)
        -> [UsageMeter]
    {
        let today = TranscriptUsage.totals(events: events, from: dayStart, to: now + 1)
        let month = TranscriptUsage.totals(events: events, from: monthStart, to: now + 1)
        return [
            UsageMeter(
                window: "Today", detail: "\(credits(today.credits)) credits · \(today.messages) replies",
                note: "Credit limit not available offline"),
            UsageMeter(
                window: "This month", detail: "\(credits(month.credits)) credits · \(month.messages) replies",
                note: "Credit limit not available offline"),
        ]
    }

    static func credits(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
