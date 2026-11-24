// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

struct MemoryTests {
    let store: MemoryStore
    let skill: MemorySkill

    init() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        store = MemoryStore(
            fileURL: dir.appending(path: "memory.txt"),
            defaultsSuite: "friday.tests.\(UUID().uuidString)"
        )
        skill = MemorySkill(memory: store)
    }

    @Test func disabledByDefaultAndWritesNothing() async {
        #expect(!store.isEnabled)
        #expect(await skill.handle(Command("remember the wifi is upstairs")) == Persona.memoryDisabled)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func remembersListsAndWipes() async {
        store.isEnabled = true
        #expect(await skill.handle(Command("Remember that my Work ID ends in .co")) == Persona.memorySaved)
        #expect(await skill.handle(Command("remember gaming account is separate")) == Persona.memorySaved)
        #expect(store.facts() == ["my Work ID ends in .co", "gaming account is separate"])

        let listed = await skill.handle(Command("What do you remember?"))
        #expect(listed == "• my Work ID ends in .co\n• gaming account is separate")

        #expect(await skill.handle(Command("forget everything")) == Persona.memoryWiped)
        #expect(store.facts().isEmpty)
        #expect(await skill.handle(Command("show memory")) == Persona.memoryEmpty)
    }

    @Test func fileIsHumanReadablePlainText() throws {
        try store.append("line one", at: Date(timeIntervalSince1970: 0))
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.hasPrefix("# Friday memory file"))
        #expect(text.contains("| line one\n"))
    }

    @Test func handEditedLinesAreRead() throws {
        try store.ensureFile()
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("a fact typed by hand\n# a comment\n".utf8))
        try handle.close()
        #expect(store.facts() == ["a fact typed by hand"])
    }

    @Test func askingWithoutFactPrompts() async {
        store.isEnabled = true
        #expect(await skill.handle(Command("remember")) == Persona.rememberWhat)
    }
}
