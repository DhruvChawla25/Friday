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
        let report = WhatsAppDatabase.Report(
            chats: [
                .init(id: 0, name: "Rahul", count: 3, kind: .person, muted: false, lastMessage: nil),
                .init(id: 1, name: "Project Group", count: 12, kind: .group, muted: true, lastMessage: nil),
                .init(id: 2, name: "Mum", count: 0, kind: .person, muted: false, lastMessage: nil),
            ],
            archivedUnreadChats: 4)
        #expect(
            Connections.describe(report, names: true, limit: 2)
                == "WhatsApp: 3 unread chats, 15 messages. 1 muted. Latest: Rahul (3), Project Group (12), +1 more.")
        #expect(Connections.describe(report, names: false) == "WhatsApp: 3 unread chats, 15 messages. 1 muted.")
        #expect(
            Connections.describe(.init(chats: [], archivedUnreadChats: 0), names: true) == "WhatsApp: no unread chats.")
    }
}
