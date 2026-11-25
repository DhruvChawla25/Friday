// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

private final class FakeLauncher: AppLaunching, @unchecked Sendable {
    var installed: Set<String>
    private(set) var requests: [String] = []

    init(installed: Set<String>) { self.installed = installed }

    @MainActor func launchApp(named name: String) async -> LaunchResult {
        requests.append(name)
        return installed.contains(name.lowercased()) ? .launched(name) : .notFound
    }
}

@MainActor
struct OpenAppSkillTests {
    @Test func opensInstalledApp() async {
        let launcher = FakeLauncher(installed: ["whatsapp"])
        let reply = await OpenAppSkill(launcher: launcher).handle(Command("Open WhatsApp"))
        #expect(reply == "Opened WhatsApp.")
        #expect(launcher.requests == ["WhatsApp"])
    }

    @Test func reportsMissingApp() async {
        let reply = await OpenAppSkill(launcher: FakeLauncher(installed: [])).handle(Command("launch Foo"))
        #expect(reply == "No app named \"Foo\" is installed.")
    }

    @Test func refusesBlockedApps() async {
        let launcher = FakeLauncher(installed: ["instagram"])
        let reply = await OpenAppSkill(launcher: launcher).handle(Command("open Instagram"))
        #expect(reply == Persona.blocked("Instagram"))
        #expect(launcher.requests.isEmpty)
    }

    @Test func findsAppsByNameInDirectories() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for name in ["Google Chrome.app", "Chrome Remote Desktop.app", "Notes.app"] {
            try FileManager.default.createDirectory(at: dir.appending(path: name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(WorkspaceAppLauncher.find("notes", in: [dir])?.lastPathComponent == "Notes.app")
        #expect(WorkspaceAppLauncher.find("chrome", in: [dir])?.lastPathComponent == "Google Chrome.app")
        #expect(WorkspaceAppLauncher.find("zoom", in: [dir]) == nil)
    }

    @Test func findsAppInUserApplicationsFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir.appending(path: "Demo.app"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(WorkspaceAppLauncher.find("demo", in: [dir])?.lastPathComponent == "Demo.app")
        let userApps = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        #expect(!userApps.isEmpty)
        #expect(userApps.allSatisfy { WorkspaceAppLauncher.searchDirectories.contains($0) })
    }
}
