// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

private final class FakeQuitter: AppQuitting, @unchecked Sendable {
    let apps: [RunningAppInfo]
    private(set) var terminated: [String] = []

    init(_ apps: [RunningAppInfo]) { self.apps = apps }

    @MainActor func runningApps() -> [RunningAppInfo] { apps }
    @MainActor func terminate(_ app: RunningAppInfo) -> Bool {
        terminated.append(app.name)
        return true
    }
}

private let spotify = RunningAppInfo(name: "Spotify", bundleID: "com.spotify.client", pid: 1)
private let finder = RunningAppInfo(name: "Finder", bundleID: "com.apple.finder", pid: 2)
private let notes = RunningAppInfo(name: "Notes", bundleID: "com.apple.Notes", pid: 3)
private let notesHelper = RunningAppInfo(name: "Notes Helper", bundleID: nil, pid: 4)

@MainActor
struct QuitAppSkillTests {
    @Test func handlesCloseAndQuit() {
        let skill = QuitAppSkill(quitter: FakeQuitter([]))
        #expect(skill.canHandle(Command("close Spotify")))
        #expect(skill.canHandle(Command("quit spotify")))
        #expect(!skill.canHandle(Command("open Spotify")))
    }

    @Test func closesRunningApp() async {
        let quitter = FakeQuitter([spotify, finder])
        let reply = await QuitAppSkill(quitter: quitter).handle(Command("close spotify"))
        #expect(reply == "Closed Spotify.")
        #expect(quitter.terminated == ["Spotify"])
    }

    @Test func reportsNotRunning() async {
        let reply = await QuitAppSkill(quitter: FakeQuitter([finder])).handle(Command("quit Spotify"))
        #expect(reply == "Spotify is not running.")
    }

    @Test func refusesFinderAndFriday() async {
        let quitter = FakeQuitter([finder])
        let skill = QuitAppSkill(quitter: quitter)
        #expect(await skill.handle(Command("close finder")) == "I won't close finder.")
        #expect(await skill.handle(Command("close Friday")) == "I won't close Friday.")
        #expect(quitter.terminated.isEmpty)
    }

    @Test func prefersExactMatch() {
        #expect(QuitAppSkill.match("notes", in: [notes, notesHelper]) == [notes])
        #expect(QuitAppSkill.match("help", in: [notes, notesHelper]) == [notesHelper])
    }

    @Test func asksWhenAmbiguous() async {
        let quitter = FakeQuitter([spotify, notes, notesHelper])
        let reply = await QuitAppSkill(quitter: quitter).handle(Command("close no"))
        #expect(reply.hasPrefix("That matches several apps"))
        #expect(quitter.terminated.isEmpty)
    }
}
