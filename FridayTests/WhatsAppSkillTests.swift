// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct WhatsAppSkillTests {
    @Test func openKeepsWhatsAppInFront() async {
        let skill = WhatsAppSkill { staysInFront in staysInFront ? "front" : "back" }
        #expect(await skill.handle(Command("Open WhatsApp")) == "front")
        #expect(await skill.handle(Command("who messaged me?")) == "back")
    }

    @Test(arguments: ["check whatsapp", "Who messaged me", "whatsapp", "open whatsapp"])
    func handlesPhrases(_ text: String) {
        #expect(WhatsAppSkill { _ in "" }.canHandle(Command(text)))
    }

    @Test func ignoresOtherApps() {
        #expect(!WhatsAppSkill { _ in "" }.canHandle(Command("open chrome")))
    }

    @MainActor @Test func describesReport() {
        let report = WhatsAppChatListAnalyzer.Report(
            chats: [
                .init(name: "Rahul", count: 3),
                .init(name: "Project Group", count: 12, mentioned: true),
            ],
            railTotal: nil)
        #expect(
            Connections.describe(report, names: true)
                == "WhatsApp: 2 unread chats, 15 messages. Rahul (3), Project Group (12, mentioned you).")
        #expect(Connections.describe(report, names: false) == "WhatsApp: 2 unread chats, 15 messages.")
        #expect(Connections.describe(.init(chats: [], railTotal: nil), names: true) == "WhatsApp: no unread chats.")
    }
}
