// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit

/// A running app, reduced to what the reply needs.
struct RunningApp: Sendable, Equatable {
    let name: String
    let isFrontmost: Bool
}

protocol RunningAppListing: Sendable {
    @MainActor func runningApps() -> [RunningApp]
}

/// Answers "what's running" with the open apps, frontmost first.
struct RunningAppsSkill: Skill {
    let name = "Running apps"
    let example = "what's running"

    let lister: any RunningAppListing

    private static let phrases: Set<String> = [
        "what's running", "whats running", "what is running", "what apps are running",
        "what apps are open", "which apps are open", "which apps are running", "running apps",
    ]

    func canHandle(_ command: Command) -> Bool {
        Self.phrases.contains(command.normalized.replacingOccurrences(of: "\u{2019}", with: "'"))
    }

    func handle(_ command: Command) async -> String {
        let apps = await lister.runningApps()
        guard !apps.isEmpty else { return "No apps are open." }
        let ordered = apps.filter(\.isFrontmost) + apps.filter { !$0.isFrontmost }
        let noun = ordered.count == 1 ? "app" : "apps"
        return "\(ordered.count) \(noun) open: " + ordered.map(\.name).joined(separator: ", ") + "."
    }
}

/// Lists regular (Dock) apps from NSWorkspace.
struct WorkspaceRunningAppLister: RunningAppListing {
    @MainActor
    func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                app.localizedName.map { RunningApp(name: $0, isFrontmost: app.isActive) }
            }
    }
}
