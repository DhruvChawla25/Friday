// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

private struct EchoSkill: Skill {
    let name = "Echo"
    let example = "echo <text>"
    func canHandle(_ command: Command) -> Bool { command.normalized.hasPrefix("echo") }
    func handle(_ command: Command) async -> String { command.argument(after: "echo") ?? "" }
}

@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(hours: Double) { date += hours * 3600 }
}

@MainActor
struct AssistantLogTests {
    let clock = TestClock()
    let assistant: Assistant

    init() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let memory = MemoryStore(
            fileURL: dir.appending(path: "memory.txt"), defaultsSuite: "friday.tests.\(UUID().uuidString)")
        let clock = clock
        assistant = Assistant(
            memory: memory, registry: SkillRegistry(skills: [EchoSkill()]), now: { clock.date })
    }

    @Test func latestIsNewestAndHistoryIsTheRestNewestFirst() async {
        await assistant.submit("echo one")
        await assistant.submit("echo two")
        await assistant.submit("echo three")
        #expect(assistant.latest?.reply == "three")
        #expect(assistant.history.map(\.reply) == ["two", "one"])
    }

    @Test func singleExchangeHasNoHistory() async {
        await assistant.submit("echo only")
        #expect(assistant.latest?.reply == "only")
        #expect(assistant.history.isEmpty)
    }

    @Test func entriesOlderThan24HoursAreDeleted() async {
        await assistant.submit("echo old")
        clock.advance(hours: 23)
        await assistant.submit("echo recent")
        assistant.pruneExpired()
        #expect(assistant.exchanges.count == 2)

        clock.advance(hours: 2)  // "old" is now 25 h old, "recent" 2 h.
        assistant.pruneExpired()
        #expect(assistant.exchanges.map(\.reply) == ["recent"])

        clock.advance(hours: 23)
        assistant.pruneExpired()
        #expect(assistant.latest == nil)
    }

    @Test func clearRemovesEverything() async {
        await assistant.submit("echo a")
        await assistant.submit("echo b")
        assistant.clearLog()
        #expect(assistant.exchanges.isEmpty)
    }
}
