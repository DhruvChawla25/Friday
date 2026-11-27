// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Observation

/// The app-wide coordinator: holds the conversation log and routes commands.
///
/// The log lives in memory only (never on disk). The newest exchange is shown
/// on top; older ones form the history, which expires after 24 hours.
@MainActor
@Observable
final class Assistant {
    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        let request: String
        let reply: String
        let date: Date
    }

    static let historyLifetime: TimeInterval = 24 * 60 * 60

    /// Oldest first.
    private(set) var exchanges: [Exchange] = []
    private(set) var isWorking = false

    let memory: MemoryStore
    private let registry: SkillRegistry
    private let now: @MainActor () -> Date
    private var pruneTimer: Timer?

    init(memory: MemoryStore, registry: SkillRegistry, now: @escaping @MainActor () -> Date = { .now }) {
        self.memory = memory
        self.registry = registry
        self.now = now
    }

    /// The most recent command and reply.
    var latest: Exchange? { exchanges.last }

    /// Everything before the latest exchange, newest first.
    var history: [Exchange] { exchanges.dropLast().reversed() }

    func submit(_ text: String) async {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let reply = await registry.respond(to: request)
        exchanges.append(Exchange(request: request, reply: reply, date: now()))
        pruneExpired()
    }

    /// Deletes exchanges older than 24 hours.
    func pruneExpired() {
        let cutoff = now().addingTimeInterval(-Self.historyLifetime)
        exchanges.removeAll { $0.date < cutoff }
    }

    /// Prunes every few minutes so expired entries vanish even while idle.
    func startPruning() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pruneExpired() }
        }
        pruneTimer?.tolerance = 60
    }

    func clearLog() {
        exchanges.removeAll()
    }

    static func makeDefault(connections: Connections) -> Assistant {
        let memory = MemoryStore.standard
        let registry = SkillRegistry(skills: [
            // First, so "open snipping tool" is a snip, not an app launch. Its phrases are strict.
            CaptureSkill(capturer: ScreenCaptureCoordinator.shared),
            WhatsAppSkill { staysInFront in await connections.checkWhatsApp(staysInFront: staysInFront) },
            TimeSkill(),
            OpenAppSkill(launcher: WorkspaceAppLauncher()),
            MemorySkill(memory: memory),
        ])
        return Assistant(memory: memory, registry: registry)
    }
}
