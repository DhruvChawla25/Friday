// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Claude: Claude Code (CLI) plus the Claude desktop app. Both share one
/// plan, so they share one set of limits.
///
/// - Limits: from the status line snapshot (see `ClaudeStatusLine`), the
///   only offline source of Claude's real percentages.
/// - Local usage: token counts in `~/.claude/projects/**/*.jsonl`, grouped
///   into 5-hour windows. Used alone this is an estimate with no limit.
/// - Live: `~/.claude/sessions/<pid>.json` (one per open Claude Code
///   session) checked against running PIDs, and the desktop app's process.
struct ClaudeUsageProvider: UsageProvider {
    let tool = AITool.claude
    static let projectsPath = ".claude/projects"
    static let sessionsPath = ".claude/sessions"
    static let sessionLength: TimeInterval = 5 * 3600

    struct CodeSessions: Equatable {
        var open = 0
        var working = 0
    }

    private struct SessionFile: Decodable {
        var pid: Int32?
        var status: String?
        var updatedAt: Double?
    }

    /// Open Claude Code sessions. A session counts if its PID is running, or
    /// (when processes cannot be listed) if it updated in the last 10 minutes.
    static func codeSessions(home: URL, processes: ProcessList.Snapshot?, now: Date) -> CodeSessions {
        let directory = home.appending(path: sessionsPath)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var sessions = CodeSessions()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let session = try? JSONDecoder().decode(SessionFile.self, from: data),
                let pid = session.pid
            else { continue }
            let alive: Bool
            if let processes {
                alive = processes.isAlive(pid)
            } else {
                let updated = Date(timeIntervalSince1970: (session.updatedAt ?? 0) / 1000)
                alive = now.timeIntervalSince(updated) < 600
            }
            guard alive else { continue }
            sessions.open += 1
            if session.status == "busy" { sessions.working += 1 }
        }
        return sessions
    }

    func usage(in env: UsageEnvironment) -> ToolUsage {
        let hasCode = env.exists(Self.projectsPath) || env.exists(Self.sessionsPath)
        let hasDesktop = env.isAppInstalled(tool)
        guard hasCode || hasDesktop else { return .notInstalled(tool) }

        let sessions = Self.codeSessions(home: env.home, processes: env.processes, now: env.now)
        let desktopOpen = env.isRunning(tool)
        let events = TranscriptUsage.events(
            inDirectory: env.url(Self.projectsPath), modifiedSince: env.now - 24 * 3600)
        let window = TranscriptUsage.activeWindow(
            events: events, now: env.now, length: Self.sessionLength, calendar: env.calendar)
        let online = env.online[tool]
        let limits = LimitsMerge.claudeLimits(
            statusLine: ClaudeStatusLine.read(home: env.home), online: online, now: env.now)

        return ToolUsage(
            tool: tool,
            isInstalled: true,
            isLive: sessions.open > 0 || desktopOpen,
            liveDetail: Self.liveDetail(sessions: sessions, desktopOpen: desktopOpen),
            meters: Self.meters(limits: limits, window: window, now: env.now),
            source: Self.source(limits: limits, online: online, now: env.now),
            lastActive: events.last?.date
        )
    }

    static func liveDetail(sessions: CodeSessions, desktopOpen: Bool) -> String? {
        var parts: [String] = []
        if sessions.open > 0 {
            var text = "Code: \(sessions.open) \(sessions.open == 1 ? "session" : "sessions")"
            if sessions.working > 0 { text += " (\(sessions.working) working)" }
            parts.append(text)
        }
        if desktopOpen { parts.append("Desktop app open") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Limit % and reset come from `limits` (status line or Friday Online);
    /// the local usage line always comes from this window's transcripts.
    static func meters(limits: LimitsMerge.Limits?, window: TranscriptUsage.Window?, now: Date) -> [UsageMeter] {
        let activity = window.map { UsageFormat.activity(messages: $0.messages, tokens: $0.tokens) }
        var session = UsageMeter(window: "5-hour session", detail: activity)
        if let limit = limits?.fiveHour {
            session = LimitsMerge.meter("5-hour session", limit, now: now, detail: activity)
        } else if let window {
            session.resetsAt = window.end
            session.resetIsEstimate = true
            session.note = "Limit not available offline"
        } else {
            session.note = "No session in progress"
        }

        var weekly = UsageMeter(window: "Weekly")
        if let limit = limits?.weekly {
            weekly = LimitsMerge.meter("Weekly", limit, now: now)
        } else {
            weekly.note = "Not available offline · set up the status line or Friday Online"
        }
        var meters = [session, weekly]
        if let opus = limits?.weeklyOpus { meters.append(LimitsMerge.meter("Weekly · Opus", opus, now: now)) }
        if let sonnet = limits?.weeklySonnet {
            meters.append(LimitsMerge.meter("Weekly · Sonnet", sonnet, now: now))
        }
        return meters
    }

    /// e.g. "Friday Online app · 1 min ago", or the local fallback plus why
    /// Friday Online had nothing ("… · Friday Online app not running").
    static func source(limits: LimitsMerge.Limits?, online: OnlineLimits?, now: Date) -> String {
        let age = limits?.updatedAt.map { " · " + UsageFormat.ago($0, now: now) } ?? ""
        switch limits?.origin {
        case .fridayOnline:
            return "Friday Online app\(age)"
        case .statusLine:
            let problem = LimitsMerge.problem(online).map { " · " + $0 } ?? ""
            return "Claude Code status line\(age)\(problem)"
        case nil:
            let problem = LimitsMerge.problem(online) ?? "limits need the status line or Friday Online"
            return "Local Claude Code transcripts · \(problem)"
        }
    }
}
