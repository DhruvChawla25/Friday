// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct WhatsAppWebFallbackTests {
    @Test func unreadNumberFromTitle() {
        #expect(TabTitleParser.whatsappUnread(in: ["(74) WhatsApp", "YouTube"]) == 74)
        #expect(TabTitleParser.whatsappUnread(in: ["(1,204) WhatsApp Business"]) == 1204)
    }

    @Test func whatsappTabWithoutUnreadIsZero() {
        #expect(TabTitleParser.whatsappUnread(in: ["WhatsApp"]) == 0)
    }

    @Test func otherTabsAreIgnored() {
        #expect(TabTitleParser.whatsappUnread(in: ["GitHub", "Stitch - Projects", "WhatsAppFan blog"]) == nil)
    }

    @Test func stateFollowsChromeAndPermission() {
        typealias F = WhatsAppWebFallback
        #expect(F.state(chromeInstalled: false, access: .granted, titles: ["(3) WhatsApp"]) == .noChrome)
        #expect(F.state(chromeInstalled: true, access: .chromeNotRunning, titles: nil) == .chromeClosed)
        #expect(F.state(chromeInstalled: true, access: .notDetermined, titles: nil) == .needsPermission)
        #expect(F.state(chromeInstalled: true, access: .denied, titles: nil) == .denied)
        #expect(F.state(chromeInstalled: true, access: .granted, titles: ["Gmail"]) == .noTab)
        #expect(F.state(chromeInstalled: true, access: .granted, titles: ["(3) WhatsApp"]) == .unread(3))
    }

    @Test func replies() {
        #expect(WhatsAppWebFallback.reply(for: .unread(1)) == "WhatsApp Web: 1 unread chat.")
        #expect(WhatsAppWebFallback.reply(for: .unread(70)) == "WhatsApp Web: 70 unread chats.")
        #expect(WhatsAppWebFallback.reply(for: .unread(0)) == "WhatsApp Web: no unread chats.")
    }

    /// The real case: Dock badge off, 3 chats visible on screen, 70 in the Web title.
    @Test func webTitleWinsElseLargest() {
        #expect(Connections.combinedUnread(screenChats: 3, web: 70, badge: 0) == 70)
        // Chats were read: the live Web title drops even if a screen reading is stale.
        #expect(Connections.combinedUnread(screenChats: 9, web: 0, badge: nil) == 0)
        #expect(Connections.combinedUnread(screenChats: 5, web: nil, badge: 2) == 5)
        #expect(Connections.combinedUnread(screenChats: nil, web: nil, badge: nil) == nil)
    }

    /// Badge reads 0 but another source sees unread chats: the badge is off.
    @Test func detectsBadgeTurnedOff() {
        #expect(Connections.badgeLooksOff(badge: 0, screenChats: 3, web: nil))
        #expect(Connections.badgeLooksOff(badge: 0, screenChats: nil, web: 86))
        // Nothing unread anywhere: a 0 badge is believable.
        #expect(!Connections.badgeLooksOff(badge: 0, screenChats: 0, web: 0))
        #expect(!Connections.badgeLooksOff(badge: 0, screenChats: nil, web: nil))
        // A badge with a number, or no badge reading at all, is not "off".
        #expect(!Connections.badgeLooksOff(badge: 5, screenChats: 9, web: 70))
        #expect(!Connections.badgeLooksOff(badge: nil, screenChats: 3, web: 70))
    }
}
