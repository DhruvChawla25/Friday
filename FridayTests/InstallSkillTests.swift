// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

struct InstallSkillTests {
    @Test(arguments: ["what can I install", "What can I install?", "list dmgs"])
    func handlesPhrases(_ text: String) {
        #expect(InstallSkill().canHandle(Command(text)))
    }

    @Test(arguments: ["open chrome", "what time is it"])
    func ignoresOthers(_ text: String) {
        #expect(!InstallSkill().canHandle(Command(text)))
    }

    @Test func listsDMGsNewestFirst() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let old = dir.appendingPathComponent("Old.dmg")
        let new = dir.appendingPathComponent("New.DMG")
        try Data(count: 10).write(to: old)
        try Data(count: 2000).write(to: new)
        try Data(count: 5).write(to: dir.appendingPathComponent("notes.txt"))
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: new.path)

        let entries = InstallSkill.listDMGs(in: dir)
        #expect(entries.map(\.name) == ["New.DMG", "Old.dmg"])
        let reply = InstallSkill.reply(for: entries)
        #expect(reply.contains("2 DMGs"))
        #expect(reply.contains("New.DMG (\(InstallSkill.formatted(size: 2000)))"))
        #expect(reply.range(of: "New.DMG")!.lowerBound < reply.range(of: "Old.dmg")!.lowerBound)
    }

    @Test func emptyFolder() {
        #expect(InstallSkill.reply(for: []) == "There are no DMG files in your Downloads folder.")
    }
}
