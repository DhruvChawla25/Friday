// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit

/// A running app, reduced to what matching needs.
struct RunningAppInfo: Sendable, Equatable {
    let name: String
    let bundleID: String?
    let pid: pid_t
}

protocol AppQuitting: Sendable {
    @MainActor func runningApps() -> [RunningAppInfo]
    /// Politely asks the app to quit. Returns false if the request was not delivered.
    @MainActor func terminate(_ app: RunningAppInfo) -> Bool
}

/// Quits running Mac apps gracefully: "close Spotify", "quit Notes".
struct QuitAppSkill: Skill {
    let name = "Quit app"
    let example = "close Spotify"

    /// Apps Friday will never quit.
    static let protectedBundleIDs: Set<String> = ["com.apple.finder"]
    static let protectedNames: Set<String> = ["finder", "friday"]

    let quitter: any AppQuitting
    var ownBundleID: String? = Bundle.main.bundleIdentifier

    func canHandle(_ command: Command) -> Bool {
        command.normalized.hasPrefix("close ") || command.normalized.hasPrefix("quit ")
    }

    func isProtected(_ app: RunningAppInfo) -> Bool {
        if let id = app.bundleID, Self.protectedBundleIDs.contains(id) || id == ownBundleID { return true }
        return Self.protectedNames.contains(app.name.lowercased())
    }

    /// Exact name match first, otherwise every app whose name contains the query.
    static func match(_ query: String, in apps: [RunningAppInfo]) -> [RunningAppInfo] {
        let query = query.lowercased()
        let exact = apps.filter { $0.name.lowercased() == query }
        return exact.isEmpty ? apps.filter { $0.name.lowercased().contains(query) } : exact
    }

    @MainActor
    func handle(_ command: Command) async -> String {
        guard let app = command.argument(after: "close") ?? command.argument(after: "quit") else {
            return "Specify an app to close."
        }
        if Self.protectedNames.contains(app.lowercased()) { return "I won't close \(app)." }
        let matches = Self.match(app, in: quitter.runningApps())
        if matches.count == 1, isProtected(matches[0]) { return "I won't close \(matches[0].name)." }
        let candidates = matches.filter { !isProtected($0) }
        guard let target = candidates.first else { return "\(app) is not running." }
        if candidates.count > 1 {
            let names = candidates.map(\.name).joined(separator: ", ")
            return "That matches several apps (\(names)). Which one should I close?"
        }
        return quitter.terminate(target) ? "Closed \(target.name)." : "Could not close \(target.name)."
    }
}

struct WorkspaceAppQuitter: AppQuitting {
    @MainActor func runningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                app.localizedName.map {
                    RunningAppInfo(name: $0, bundleID: app.bundleIdentifier, pid: app.processIdentifier)
                }
            }
    }

    @MainActor func terminate(_ app: RunningAppInfo) -> Bool {
        NSRunningApplication(processIdentifier: app.pid)?.terminate() ?? false
    }
}
