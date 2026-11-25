// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Antigravity keeps its quota on Google's servers only. Offline, Friday can
/// show whether it is open and when a conversation last changed (from file
/// dates in `~/.gemini/antigravity/conversations`; contents are not read).
struct AntigravityUsageProvider: UsageProvider {
    let tool = AITool.antigravity
    static let conversationsPath = ".gemini/antigravity/conversations"

    func usage(in env: UsageEnvironment) -> ToolUsage {
        let hasData = env.exists(Self.conversationsPath)
        guard hasData || env.isAppInstalled(tool) else { return .notInstalled(tool) }
        let running = env.isRunning(tool)
        return ToolUsage(
            tool: tool,
            isInstalled: true,
            isLive: running,
            liveDetail: running ? "App open" : nil,
            meters: [UsageMeter(window: "Quota", note: "Not available offline")],
            source: "Conversation file dates",
            lastActive: FileManager.default.latestModification(in: env.url(Self.conversationsPath), depth: 0)
        )
    }
}

/// Qwen Code (CLI) stores its quota on Qwen's servers. Offline, Friday shows
/// whether a `qwen` process runs and when files under `~/.qwen/tmp` (its
/// per-project logs and checkpoints) last changed. Contents are not read.
struct QwenCodeUsageProvider: UsageProvider {
    let tool = AITool.qwenCode
    static let dataPath = ".qwen/tmp"
    static let processNames: Set<String> = ["qwen", "qwen-code"]

    func usage(in env: UsageEnvironment) -> ToolUsage {
        guard env.exists(Self.dataPath) else { return .notInstalled(tool) }
        let lastActive = FileManager.default.latestModification(in: env.url(Self.dataPath), depth: 2)
        let processRunning = env.processes.map { list in Self.processNames.contains(where: list.contains(name:)) }
        // Qwen Code runs on Node, so its process may just be called "node";
        // recent file activity is the fallback signal.
        let recentlyActive = lastActive.map { env.now.timeIntervalSince($0) < 5 * 60 } ?? false
        let live = processRunning == true || recentlyActive
        return ToolUsage(
            tool: tool,
            isInstalled: true,
            isLive: live,
            liveDetail: live ? "Active" : nil,
            meters: [UsageMeter(window: "Daily requests", note: "Not available offline")],
            source: "File dates in ~/.qwen",
            lastActive: lastActive
        )
    }
}
