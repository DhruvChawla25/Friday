import Foundation

/// "remember …", "what do you remember", "forget everything".
struct MemorySkill: Skill {
    let name = "Memory"
    let example = "remember <fact>  ·  what do you remember  ·  forget everything"

    let memory: MemoryStore

    private static let listPhrases: Set<String> = [
        "what do you remember", "show memory", "list memory", "memory",
    ]
    private static let wipePhrases: Set<String> = [
        "forget everything", "wipe memory", "clear memory",
    ]

    func canHandle(_ command: Command) -> Bool {
        command.normalized.hasPrefix("remember")
            || Self.listPhrases.contains(command.normalized)
            || Self.wipePhrases.contains(command.normalized)
    }

    func handle(_ command: Command) async -> String {
        guard memory.isEnabled else { return Persona.memoryDisabled }

        if Self.wipePhrases.contains(command.normalized) {
            do { try memory.wipe() } catch { return Persona.memoryWriteFailed }
            return Persona.memoryWiped
        }
        if Self.listPhrases.contains(command.normalized) {
            let facts = memory.facts()
            guard !facts.isEmpty else { return Persona.memoryEmpty }
            return facts.map { "• \($0)" }.joined(separator: "\n")
        }
        guard let fact = command.argument(after: "remember that") ?? command.argument(after: "remember") else {
            return Persona.rememberWhat
        }
        do { try memory.append(fact) } catch { return Persona.memoryWriteFailed }
        return Persona.memorySaved
    }
}
