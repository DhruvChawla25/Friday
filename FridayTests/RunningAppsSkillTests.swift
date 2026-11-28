// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct FakeLister: RunningAppListing {
    var apps: [RunningApp]
    func runningApps() -> [RunningApp] { apps }
}

struct RunningAppsSkillTests {
    @Test(arguments: ["what's running", "What is running?", "which apps are open"])
    func handlesQuestions(_ text: String) {
        let skill = RunningAppsSkill(lister: FakeLister(apps: []))
        #expect(skill.canHandle(Command(text)))
    }

    @Test func ignoresOtherCommands() {
        let skill = RunningAppsSkill(lister: FakeLister(apps: []))
        #expect(!skill.canHandle(Command("open chrome")))
    }

    @Test func listsFrontmostFirstWithCount() async {
        let skill = RunningAppsSkill(
            lister: FakeLister(apps: [
                RunningApp(name: "Finder", isFrontmost: false),
                RunningApp(name: "Safari", isFrontmost: true),
                RunningApp(name: "Notes", isFrontmost: false),
            ]))
        #expect(await skill.handle(Command("what's running")) == "3 apps open: Safari, Finder, Notes.")
    }

    @Test func handlesNone() async {
        let skill = RunningAppsSkill(lister: FakeLister(apps: []))
        #expect(await skill.handle(Command("what's running")) == "No apps are open.")
    }
}
