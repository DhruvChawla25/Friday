// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// "open whatsapp" opens WhatsApp *and* reads it; "check whatsapp" and
/// "who messaged me" read it and return you to what you were doing.
struct WhatsAppSkill: Skill {
    let name = "WhatsApp"
    let example = "check whatsapp  ·  who messaged me"

    /// Reads WhatsApp; `true` keeps WhatsApp in front afterwards.
    let check: @Sendable (_ staysInFront: Bool) async -> String

    static let openPhrases: Set<String> = ["open whatsapp", "launch whatsapp", "show whatsapp"]
    static let checkPhrases: Set<String> = [
        "check whatsapp", "read whatsapp", "read my whatsapp", "check my whatsapp", "whatsapp",
        "who messaged me", "who texted me", "any messages", "unread messages", "whatsapp unread",
    ]

    func canHandle(_ command: Command) -> Bool {
        Self.openPhrases.contains(command.normalized) || Self.checkPhrases.contains(command.normalized)
    }

    func handle(_ command: Command) async -> String {
        await check(Self.openPhrases.contains(command.normalized))
    }
}
