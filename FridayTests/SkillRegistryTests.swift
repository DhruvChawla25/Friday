// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

private struct EchoSkill: Skill {
    let name = "Echo"
    let example = "echo <text>"
    func canHandle(_ command: Command) -> Bool { command.normalized.hasPrefix("echo") }
    func handle(_ command: Command) async -> String { command.argument(after: "echo") ?? "" }
}

struct SkillRegistryTests {
    let registry = SkillRegistry(skills: [EchoSkill()])

    @Test func routesToMatchingSkill() async {
        #expect(await registry.respond(to: "echo Hello") == "Hello")
    }

    @Test func unknownCommandListsExamples() async {
        let reply = await registry.respond(to: "make me a sandwich")
        #expect(reply.hasPrefix("Command not recognised."))
        #expect(reply.contains("echo <text>"))
    }

    @Test func helpListsExamples() async {
        #expect(await registry.respond(to: "Help") == Persona.help(examples: ["echo <text>"]))
    }

    @Test func emptyInput() async {
        #expect(await registry.respond(to: "   ") == Persona.emptyCommand)
    }
}
