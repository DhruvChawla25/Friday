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
        let snapshot = ClaudeStatusLine.read(home: env.home)

        return ToolUsage(
            tool: tool,
            isInstalled: true,
            isLive: sessions.open > 0 || desktopOpen,
            liveDetail: Self.liveDetail(sessions: sessions, desktopOpen: desktopOpen),
            meters: Self.meters(snapshot: snapshot, window: window, now: env.now),
            source: Self.source(snapshot: snapshot, now: env.now),
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

    static func meters(snapshot: ClaudeStatusLine.Snapshot?, window: TranscriptUsage.Window?, now: Date)
        -> [UsageMeter]
    {
        let activity = window.map { UsageFormat.activity(messages: $0.messages, tokens: $0.tokens) }
        var session = UsageMeter(window: "5-hour session", detail: activity)
        if let limit = snapshot?.fiveHour.map({ ClaudeStatusLine.current($0, now: now) }) {
            session.usedFraction = limit.usedPercent / 100
            session.resetsAt = limit.resetsAt
        } else if let window {
            session.resetsAt = window.end
            session.resetIsEstimate = true
            session.note = "Limit not available offline"
        } else {
            session.note = "No session in progress"
        }

        var weekly = UsageMeter(window: "Weekly")
        if let limit = snapshot?.sevenDay.map({ ClaudeStatusLine.current($0, now: now) }) {
            weekly.usedFraction = limit.usedPercent / 100
            weekly.resetsAt = limit.resetsAt
        } else {
            weekly.note = "Not available offline · set up the status line"
        }
        return [session, weekly]
    }

    static func source(snapshot: ClaudeStatusLine.Snapshot?, now: Date) -> String {
        guard let snapshot else { return "Local Claude Code transcripts · limits need the status line" }
        let age = snapshot.capturedAt.map { " · " + UsageFormat.ago($0, now: now) } ?? ""
        return "Claude Code status line\(age)"
    }
}
