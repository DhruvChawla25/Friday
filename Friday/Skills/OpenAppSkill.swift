// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit

enum LaunchResult: Sendable, Equatable {
    case launched(String)
    case notFound
    case failed(String)
}

protocol AppLaunching: Sendable {
    @MainActor func launchApp(named name: String) async -> LaunchResult
}

/// Opens installed Mac apps: "open WhatsApp", "launch Chrome".
struct OpenAppSkill: Skill {
    let name = "Open app"
    let example = "open Calendar"

    /// Apps Friday will never open, by user decision.
    static let blockedApps: Set<String> = ["instagram"]

    let launcher: any AppLaunching

    func canHandle(_ command: Command) -> Bool {
        command.normalized.hasPrefix("open ") || command.normalized.hasPrefix("launch ")
    }

    func handle(_ command: Command) async -> String {
        guard let app = command.argument(after: "open") ?? command.argument(after: "launch") else {
            return "Specify an app to open."
        }
        if Self.blockedApps.contains(where: { app.lowercased().contains($0) }) {
            return Persona.blocked(app)
        }
        switch await launcher.launchApp(named: app) {
        case .launched(let name): return "Opened \(name)."
        case .notFound: return "No app named \"\(app)\" is installed."
        case .failed(let reason): return "Could not open \(app): \(reason)"
        }
    }
}

/// Finds apps by bundle identifier (common aliases) or by name in the
/// standard Applications folders, then opens them with NSWorkspace.
struct WorkspaceAppLauncher: AppLaunching {
    static let aliases: [String: String] = [
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "whatsapp": "net.whatsapp.WhatsApp",
        "claude": "com.anthropic.claudefordesktop",
        "mail": "com.apple.mail",
        "calendar": "com.apple.iCal",
        "safari": "com.apple.Safari",
        "notes": "com.apple.Notes",
        "reminders": "com.apple.reminders",
        "terminal": "com.apple.Terminal",
        "finder": "com.apple.finder",
        "settings": "com.apple.systempreferences",
        "system settings": "com.apple.systempreferences",
        "xcode": "com.apple.dt.Xcode",
    ]

    static let searchDirectories: [URL] = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
    ].map { URL(filePath: $0, directoryHint: .isDirectory) }

    @MainActor
    func launchApp(named name: String) async -> LaunchResult {
        guard let url = locate(name) else { return .notFound }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .launched(url.deletingPathExtension().lastPathComponent)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func locate(_ name: String) -> URL? {
        let query = name.lowercased()
        if let bundleID = Self.aliases[query],
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return url
        }
        return Self.find(query, in: Self.searchDirectories)
    }

    /// Exact name match first, then the shortest name containing the query.
    static func find(_ query: String, in directories: [URL]) -> URL? {
        let apps = directories.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "app" } ?? []
        }
        func appName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent.lowercased() }
        if let exact = apps.first(where: { appName($0) == query }) { return exact }
        return
            apps
            .filter { appName($0).contains(query) }
            .min { appName($0).count < appName($1).count }
    }
}
