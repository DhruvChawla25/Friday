// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// One capability of Friday. Skills are small, independent, and testable.
protocol Skill: Sendable {
    /// Short identifier shown in help output.
    var name: String { get }
    /// An example command, shown when Friday does not understand something.
    var example: String { get }
    /// Whether this skill should handle the command.
    func canHandle(_ command: Command) -> Bool
    /// Produces Friday's reply.
    func handle(_ command: Command) async -> String
}

/// Routes a command to the first skill that can handle it.
struct SkillRegistry: Sendable {
    let skills: [any Skill]

    func respond(to text: String) async -> String {
        let command = Command(text)
        guard !command.isEmpty else { return Persona.emptyCommand }
        if command.normalized == "help" {
            return Persona.help(examples: skills.map(\.example))
        }
        for skill in skills where skill.canHandle(command) {
            return await skill.handle(command)
        }
        return Persona.unrecognised(examples: skills.map(\.example))
    }
}
