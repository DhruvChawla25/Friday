// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import Observation

/// Collects every tool's usage for the dashboard. Refreshes when the
/// dashboard opens and once a minute while it stays open. File reading
/// happens off the main thread.
@MainActor
@Observable
final class AIUsageMonitor {
    private(set) var tools: [ToolUsage] = []
    private(set) var isLoading = false

    @ObservationIgnored private let providers: [any UsageProvider]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isVisible: () -> Bool = { false }

    init(providers: [any UsageProvider] = AIUsageMonitor.defaultProviders) {
        self.providers = providers
    }

    nonisolated static let defaultProviders: [any UsageProvider] = [
        ClaudeUsageProvider(), AntigravityUsageProvider(), QwenCodeUsageProvider(), QoderUsageProvider(),
        WisprFlowUsageProvider(), OpenCodeUsageProvider(),
    ]

    var installed: [ToolUsage] { tools.filter(\.isInstalled) }
    var notInstalled: [ToolUsage] { tools.filter { !$0.isInstalled } }

    /// `isVisible` tells the minute timer whether the dashboard is open.
    func start(isVisible: @escaping () -> Bool) {
        self.isVisible = isVisible
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                if self.isVisible() { self.refresh() }
            }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let workspace = NSWorkspace.shared
        let running = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
        let installed = Set(
            AITool.allCases.compactMap(\.bundleID).filter {
                workspace.urlForApplication(withBundleIdentifier: $0) != nil
            })
        let providers = providers
        Task {
            let tools = await Task.detached(priority: .utility) {
                let environment = UsageEnvironment(
                    home: Self.realHome, now: .now, runningBundleIDs: running, installedBundleIDs: installed,
                    processes: ProcessList.current())
                return providers.map { $0.usage(in: environment) }
            }.value
            self.tools = tools
            self.isLoading = false
        }
    }

    /// The user's real home folder. Inside the sandbox `NSHomeDirectory()`
    /// points at Friday's container, so ask the user database instead.
    nonisolated static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    }
}
