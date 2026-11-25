// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// The AI tools Friday shows usage for, in display order.
enum AITool: String, CaseIterable, Sendable, Identifiable {
    case claude, antigravity, qwenCode, qoder, wisprFlow, openCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .antigravity: "Antigravity"
        case .qwenCode: "Qwen Code"
        case .qoder: "Qoder"
        case .wisprFlow: "Wispr Flow"
        case .openCode: "OpenCode"
        }
    }

    /// The Mac app whose icon and running state Friday uses, if the tool has one.
    var bundleID: String? {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .antigravity: "com.google.antigravity"
        case .qoder: "com.qoder.app"
        case .wisprFlow: "com.electron.wispr-flow"
        case .qwenCode, .openCode: nil
        }
    }
}

/// One loading-bar meter, e.g. Claude's 5-hour session or Wispr Flow's week.
struct UsageMeter: Equatable, Sendable {
    /// e.g. "5-hour session", "Weekly".
    var window: String
    /// 0…1 of the limit used, or nil when the limit is not known offline.
    var usedFraction: Double?
    /// Local usage figures, e.g. "84 messages · 1.2M tokens".
    var detail: String?
    var resetsAt: Date?
    /// True when `resetsAt` is worked out locally rather than reported by the tool.
    var resetIsEstimate = false
    /// Shown instead of a percentage when `usedFraction` is nil.
    var note: String?
}

/// Everything the dashboard shows for one tool.
struct ToolUsage: Equatable, Sendable, Identifiable {
    let tool: AITool
    var isInstalled: Bool
    var isLive = false
    /// e.g. "2 sessions · 1 working".
    var liveDetail: String?
    var meters: [UsageMeter] = []
    /// Where the numbers come from, e.g. "Claude Code status line · 3 min ago".
    var source: String
    var lastActive: Date?

    var id: AITool { tool }

    static func notInstalled(_ tool: AITool) -> ToolUsage {
        ToolUsage(tool: tool, isInstalled: false, source: "Not installed")
    }
}

/// What providers can see: the user's real home folder (not the sandbox
/// container) and what is running right now. Injected so tests use temp dirs.
struct UsageEnvironment: Sendable {
    var home: URL
    var now: Date
    var runningBundleIDs: Set<String>
    /// Apps (by bundle ID) that are installed on this Mac.
    var installedBundleIDs: Set<String> = []
    /// Running processes, or nil if macOS would not list them.
    var processes: ProcessList.Snapshot?
    /// What the separate Friday Online app reported, if it was asked.
    var online: [AITool: OnlineLimits] = [:]
    var calendar: Calendar = .current

    func url(_ relativePath: String) -> URL {
        home.appending(path: relativePath)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relativePath).path)
    }

    func isRunning(_ tool: AITool) -> Bool {
        tool.bundleID.map(runningBundleIDs.contains) ?? false
    }

    func isAppInstalled(_ tool: AITool) -> Bool {
        tool.bundleID.map(installedBundleIDs.contains) ?? false
    }
}

/// Reads one tool's local files and returns what to show. Must never use the
/// network: everything comes from files the tool writes on this Mac.
protocol UsageProvider: Sendable {
    var tool: AITool { get }
    func usage(in environment: UsageEnvironment) -> ToolUsage
}

extension FileManager {
    /// Latest modification date of the files directly inside `directory`
    /// (and one level below), or nil if it is missing or empty.
    func latestModification(in directory: URL, depth: Int = 1) -> Date? {
        guard
            let items = try? contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])
        else { return nil }
        var latest: Date?
        for item in items {
            let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if let date = values?.contentModificationDate, date > (latest ?? .distantPast) { latest = date }
            if depth > 0, values?.isDirectory == true,
                let inner = latestModification(in: item, depth: depth - 1), inner > (latest ?? .distantPast)
            {
                latest = inner
            }
        }
        return latest
    }
}
