// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

extension AITool {
    /// The matching Friday Online provider.
    var onlineProvider: FridayOnline.Provider {
        switch self {
        case .claude: .claude
        case .antigravity: .antigravity
        case .qwenCode: .qwenCode
        case .qoder: .qoder
        case .wisprFlow: .wisprFlow
        case .openCode: .openCode
        }
    }
}

/// Asks the separate Friday Online app (through `FridayOnlineConnector`) for
/// live limits. Friday itself has no network access; Friday Online is its
/// own app and the only networked part. Each tool is asked at most once a
/// minute (Friday Online caches as well), and only while the dashboard is open.
actor FridayOnlineProvider {
    static let minimumInterval: TimeInterval = 60

    private let makeConnector: @Sendable () -> any FridayOnlineConnecting
    private let timeout: Duration
    private var connector: (any FridayOnlineConnecting)?
    private var cache: [AITool: (date: Date, value: OnlineLimits)] = [:]

    init(
        makeConnector: @escaping @Sendable () -> any FridayOnlineConnecting = { FridayOnlineConnector() },
        timeout: Duration = .seconds(10)
    ) {
        self.makeConnector = makeConnector
        self.timeout = timeout
    }

    /// Limits for `tools`, from cache when asked within the last minute. If
    /// the app is not running, the remaining tools are not asked this time.
    func limits(for tools: [AITool], now: Date = .now) async -> [AITool: OnlineLimits] {
        var result: [AITool: OnlineLimits] = [:]
        var running = true
        for tool in tools {
            if let cached = cache[tool], now.timeIntervalSince(cached.date) < Self.minimumInterval {
                result[tool] = cached.value
                continue
            }
            let value = running ? await fetch(tool.onlineProvider) : .notRunning
            if value == .notRunning {
                running = false
                connector = nil  // reconnect next time, e.g. once the app has started
            }
            cache[tool] = (now, value)
            result[tool] = value
        }
        return result
    }

    private func fetch(_ provider: FridayOnline.Provider) async -> OnlineLimits {
        let connector = connector ?? makeConnector()
        self.connector = connector
        let timeout = timeout
        // An XPC reply can't be cancelled, so race it instead of awaiting it in a task group.
        return await withCheckedContinuation { continuation in
            let once = ResumeOnceLimits(continuation)
            Task { once.resume(await connector.usageLimits(for: provider)) }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(.notRunning)
            }
        }
    }
}

private final class ResumeOnceLimits: @unchecked Sendable {
    // @unchecked: `continuation` is only touched under `lock`.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<OnlineLimits, Never>?

    init(_ continuation: CheckedContinuation<OnlineLimits, Never>) { self.continuation = continuation }

    func resume(_ value: OnlineLimits) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}

/// Picks which limits to show for a tool and how to label them.
enum LimitsMerge {
    /// A status line snapshot younger than this beats Friday Online.
    static let statusLineFreshFor: TimeInterval = 5 * 60

    struct Limits: Equatable {
        enum Origin: Equatable { case statusLine, fridayOnline }
        var origin: Origin
        var fiveHour: ClaudeStatusLine.Limit?
        var weekly: ClaudeStatusLine.Limit?
        var weeklyOpus: ClaudeStatusLine.Limit?
        var weeklySonnet: ClaudeStatusLine.Limit?
        var updatedAt: Date?
    }

    /// Precedence: a fresh status line snapshot, then Friday Online's live
    /// numbers, then an older status line snapshot. Nil if neither has any.
    static func claudeLimits(statusLine: ClaudeStatusLine.Snapshot?, online: OnlineLimits?, now: Date) -> Limits? {
        let fromStatusLine = statusLine.map {
            Limits(origin: .statusLine, fiveHour: $0.fiveHour, weekly: $0.sevenDay, updatedAt: $0.capturedAt)
        }
        if let fromStatusLine, let captured = fromStatusLine.updatedAt,
            now.timeIntervalSince(captured) < statusLineFreshFor
        {
            return fromStatusLine
        }
        if case .report(let report) = online, report.status == .ok, !report.windows.isEmpty {
            return limits(from: report)
        }
        return fromStatusLine
    }

    static func limits(from report: FridayOnline.Report) -> Limits {
        var limits = Limits(origin: .fridayOnline, updatedAt: report.fetchedAt)
        for window in report.windows {
            let limit = ClaudeStatusLine.Limit(usedPercent: window.usedPercent, resetsAt: window.resetsAt)
            switch window.window {
            case .fiveHour: limits.fiveHour = limit
            case .weekly: limits.weekly = limit
            case .weeklyOpus: limits.weeklyOpus = limit
            case .weeklySonnet: limits.weeklySonnet = limit
            }
        }
        return limits
    }

    /// Why Friday Online has no numbers, or nil when it has them (or was not asked).
    static func problem(_ online: OnlineLimits?) -> String? {
        switch online {
        case nil: nil
        case .notRunning: "Friday Online app not running"
        case .invalidReply: "Friday Online app sent an unexpected reply"
        case .report(let report):
            switch report.status {
            case .ok: report.windows.isEmpty ? "Friday Online returned no limits" : nil
            case .unsupported: "Friday Online: unsupported for this tool"
            case .credentialsMissing: "Friday Online: sign in to Claude Code, or allow Keychain access"
            case .credentialsExpired: "Friday Online: credentials expired · open Claude Code to refresh"
            case .upstreamError: "Friday Online: upstream error"
            case .unreachable: "Friday Online: can't reach the provider"
            }
        }
    }

    /// For tools other than Claude: when Friday Online has live limits, put
    /// them first; otherwise leave the local reading untouched.
    static func apply(_ online: OnlineLimits?, to usage: ToolUsage, now: Date) -> ToolUsage {
        guard usage.isInstalled, case .report(let report) = online, report.status == .ok, !report.windows.isEmpty
        else { return usage }
        var merged = usage
        let limits = limits(from: report)
        let meters: [UsageMeter] = [
            limits.fiveHour.map { meter("5-hour session", $0, now: now) },
            limits.weekly.map { meter("Weekly", $0, now: now) },
        ].compactMap(\.self)
        merged.meters = meters + usage.meters
        merged.source = "Friday Online app" + (report.fetchedAt.map { " · " + UsageFormat.ago($0, now: now) } ?? "")
        return merged
    }

    static func meter(_ window: String, _ limit: ClaudeStatusLine.Limit, now: Date, detail: String? = nil)
        -> UsageMeter
    {
        let current = ClaudeStatusLine.current(limit, now: now)
        return UsageMeter(
            window: window, usedFraction: current.usedPercent / 100, detail: detail, resetsAt: current.resetsAt)
    }
}
