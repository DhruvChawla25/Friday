import Foundation
import Observation

/// The app-wide coordinator: holds the conversation log and routes commands.
@MainActor
@Observable
final class Assistant {
    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        let request: String
        let reply: String
    }

    private(set) var exchanges: [Exchange] = []
    private(set) var isWorking = false

    let memory: MemoryStore
    private let registry: SkillRegistry

    init(memory: MemoryStore, registry: SkillRegistry) {
        self.memory = memory
        self.registry = registry
    }

    func submit(_ text: String) async {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let reply = await registry.respond(to: request)
        exchanges.append(Exchange(request: request, reply: reply))
    }

    func clearLog() {
        exchanges.removeAll()
    }

    static func makeDefault() -> Assistant {
        let memory = MemoryStore.standard
        let registry = SkillRegistry(skills: [
            TimeSkill(),
            OpenAppSkill(launcher: WorkspaceAppLauncher()),
            MemorySkill(memory: memory),
        ])
        return Assistant(memory: memory, registry: registry)
    }
}
