// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

/// All labels below are synthetic, shaped like WhatsApp for Mac's
/// accessibility labels (including its U+200E / U+2068 / U+202F characters).
@Suite struct WhatsAppAccessibilityParserTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    /// Wednesday 25 November 2026, 18:00 London.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 18))! }

    func components(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    }

    @Test func personWithUnreadMessages() throws {
        let chat = try #require(
            WhatsAppAccessibilityParser.chat(
                description: "Alex Example, \u{200E}3 unread messages",
                value: "\u{200E}message, Secret preview text, 9:41\u{202F}AM, \u{200E}Received from Alex Example",
                readsNames: true, now: now, calendar: calendar))
        #expect(chat.name == "Alex Example")
        #expect(chat.count == 3)
        #expect(chat.kind == .person)
        #expect(!chat.muted)
        #expect(components(chat.lastMessage) == DateComponents(year: 2026, month: 11, day: 25, hour: 9, minute: 41))
    }

    @Test func groupWithDateTimeAndMuted() throws {
        let chat = try #require(
            WhatsAppAccessibilityParser.chat(
                description: "Book Club 2026, \u{200E}12 unread messages",
                value: "\u{200E}Message from Sam, preview, with, commas, 24 November at 10:05\u{202F}PM, "
                    + "\u{200E}Received in Book Club 2026, \u{200E}Muted",
                readsNames: true, now: now, calendar: calendar))
        #expect(chat.name == "Book Club 2026")
        #expect(chat.count == 12)
        #expect(chat.kind == .group)
        #expect(chat.muted)
        #expect(components(chat.lastMessage) == DateComponents(year: 2026, month: 11, day: 24, hour: 22, minute: 5))
    }

    @Test func singularMessage() {
        let chat = WhatsAppAccessibilityParser.chat(
            description: "Pat, \u{200E}1 unread message", value: "", readsNames: true, now: now, calendar: calendar)
        #expect(chat?.count == 1)
        #expect(chat?.kind == .unknown)
        #expect(chat?.lastMessage == nil)
    }

    @Test func readChatsAreSkipped() {
        #expect(
            WhatsAppAccessibilityParser.chat(
                description: "Pat", value: "message, hi, 9:41\u{202F}AM, Received from Pat", readsNames: true) == nil)
        #expect(WhatsAppAccessibilityParser.chat(description: "", value: "", readsNames: true) == nil)
    }

    @Test func communityRowNeverKeepsThePreview() throws {
        let chat = try #require(
            WhatsAppAccessibilityParser.chat(
                description: "\u{200E}Street Team community, 5 unread messages from Announcements, "
                    + "\u{200E}\u{2068}Do not read this preview, it has secrets\u{2069}. \u{200E}Mentioned.",
                value: "", readsNames: true, now: now, calendar: calendar))
        #expect(chat.name == "Announcements · Street Team")
        #expect(chat.count == 5)
        #expect(chat.kind == .community)
        #expect(chat.mentioned)
        #expect(!(chat.name ?? "").contains("secret"))
    }

    @Test func namesOffDropsNames() {
        let chat = WhatsAppAccessibilityParser.chat(
            description: "Alex Example, \u{200E}3 unread messages",
            value: "message, x, 9:41\u{202F}AM, Received from Alex Example", readsNames: false, now: now,
            calendar: calendar)
        #expect(chat?.name == nil)
        #expect(chat?.count == 3)
        #expect(chat?.kind == .person)
    }

    @Test func timeIsOnlyTakenFromTheSlotBeforeReceived() {
        // Only the part right before "Received …" may be a time.
        let chat = WhatsAppAccessibilityParser.chat(
            description: "Pat, 2 unread messages", value: "message, 10:00, Received from Pat", readsNames: true,
            now: now, calendar: calendar)
        #expect(components(chat?.lastMessage)?.hour == 10)
        let noTime = WhatsAppAccessibilityParser.chat(
            description: "Pat, 2 unread messages", value: "message, see you at 10:00 then, Received from Pat",
            readsNames: true, now: now, calendar: calendar)
        #expect(noTime?.lastMessage == nil)
    }

    @Test func unreadChipTotal() {
        #expect(WhatsAppAccessibilityParser.unreadChatTotal(chipDescription: "Unread, \u{200E}86 unread chats") == 86)
        #expect(WhatsAppAccessibilityParser.unreadChatTotal(chipDescription: "Unread, 1 unread chat") == 1)
        #expect(WhatsAppAccessibilityParser.unreadChatTotal(chipDescription: "Unread") == nil)
    }

    @Test func timeFormats() {
        func parse(_ text: String) -> DateComponents? {
            components(WhatsAppTimeParser.date(from: text, now: now, calendar: calendar))
        }
        #expect(parse("21:41") == DateComponents(year: 2026, month: 11, day: 25, hour: 21, minute: 41))
        #expect(parse("12:05\u{202F}AM")?.hour == 0)
        #expect(parse("12:05 pm")?.hour == 12)
        #expect(parse("Yesterday")?.day == 24)
        #expect(
            parse("Yesterday at 8:00\u{202F}PM") == DateComponents(year: 2026, month: 11, day: 24, hour: 20, minute: 0))
        #expect(parse("Monday")?.day == 23)
        #expect(parse("Wednesday")?.day == 18)  // today is Wednesday: a weekday label means last week
        #expect(
            parse("3 October at 9:00\u{202F}AM") == DateComponents(year: 2026, month: 10, day: 3, hour: 9, minute: 0))
        #expect(
            parse("December 30, 2025 at 7:15 PM")
                == DateComponents(year: 2025, month: 12, day: 30, hour: 19, minute: 15))
        // No year and in the future: last year.
        #expect(parse("30 December at 7:15\u{202F}PM")?.year == 2025)
        #expect(parse("24/11/2026")?.day == 24)
        #expect(parse("Hello there") == nil)
        #expect(parse("25:61") == nil)
        #expect(parse("31 February") == nil)
    }
}

@Suite struct WhatsAppUnreadListTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    func chat(_ name: String?, _ count: Int, minutesAgo: Double?) -> WhatsAppUnreadList.Chat {
        .init(name: name, count: count, lastMessage: minutesAgo.map { base.addingTimeInterval(-$0 * 60) })
    }

    @Test func sortsMostRecentFirstAndUntimedLast() {
        let list = WhatsAppUnreadList(
            chats: [
                chat("Old", 1, minutesAgo: 600), chat("NoTime small", 1, minutesAgo: nil),
                chat("New", 2, minutesAgo: 1), chat("NoTime big", 9, minutesAgo: nil),
                chat("Mid", 3, minutesAgo: 30),
            ], source: .accessibilityFull)
        #expect(list.chats.map(\.name) == ["New", "Mid", "Old", "NoTime big", "NoTime small"])
    }

    @Test func headlineAndTotals() {
        let full = WhatsAppUnreadList(
            chats: [chat("A", 300, minutesAgo: 1), chat("B", 12, minutesAgo: 2)], source: .accessibilityFull,
            reportedTotal: 2)
        #expect(full.headline == "2 unread chats · 312 messages")
        #expect(!full.isPartial)

        let partial = WhatsAppUnreadList(
            chats: [chat("A", 3, minutesAgo: 1)], source: .accessibilityVisible, reportedTotal: 70)
        #expect(partial.unreadChats == 70)
        #expect(partial.isPartial)
        #expect(partial.headline == "70 unread chats")  // no message total: it would undercount

        #expect(WhatsAppUnreadList(chats: [], source: .screen, reportedTotal: 0).headline == "No unread chats")
        #expect(
            WhatsAppUnreadList(chats: [chat("A", 1, minutesAgo: 1)], source: .screen).headline
                == "1 unread chat · 1 message")
    }

    @Test func withoutNamesKeepsCountsAndTimes() {
        let list = WhatsAppUnreadList(
            chats: [chat("A", 3, minutesAgo: 1), chat("B", 4, minutesAgo: 2)], source: .accessibilityFull)
        let hidden = list.withoutNames()
        #expect(hidden.chats.allSatisfy { $0.name == nil })
        #expect(hidden.chats.map(\.count) == [3, 4])
        #expect(hidden.headline == list.headline)
    }

    @Test func collectorSkipsDuplicateRowsAcrossPages() {
        var collector = WhatsAppAccessibilityReader.Collector()
        let page1 = [
            ("A, 2 unread messages", "message, x, 9:41\u{202F}AM, Received from A"),
            ("B", "message, read chat, 9:40\u{202F}AM, Received from B"),
        ]
        let page2 = [
            ("A, 2 unread messages", "message, x, 9:41\u{202F}AM, Received from A"),
            ("C, 1 unread message", "message, y, 9:30\u{202F}AM, Received in C"),
        ]
        #expect(collector.add(page1, readsNames: true) == 1)
        #expect(collector.add(page2, readsNames: true) == 1)
        #expect(collector.add(page2, readsNames: true) == 0)
        #expect(collector.chats.map(\.name) == ["A", "C"])
    }

    @Test func collectorWithNamesOffStillDeduplicates() {
        var collector = WhatsAppAccessibilityReader.Collector()
        let page = [("A, 2 unread messages", ""), ("B, 2 unread messages", "")]
        #expect(collector.add(page, readsNames: false) == 2)
        #expect(collector.add(page, readsNames: false) == 0)
        #expect(collector.chats.allSatisfy { $0.name == nil })
    }

    @Test func screenReportConversion() {
        let report = WhatsAppChatListAnalyzer.Report(
            chats: [
                .init(name: "A", count: 2, mentioned: true, timeText: "Yesterday"),
                .init(name: "B", count: 1, timeText: "9:41"),
            ], railTotal: 40)
        let list = WhatsAppUnreadList(screen: report, reportedTotal: nil)
        #expect(list.source == .screen)
        #expect(list.reportedTotal == 40)
        #expect(list.chats.first?.name == "B")  // today beats yesterday
        #expect(list.chats.last?.mentioned == true)
    }
}

@Suite struct WhatsAppUnreadTrackerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func scan() -> WhatsAppUnreadList {
        WhatsAppUnreadList(
            chats: [
                .init(name: "A", count: 2, kind: .person, lastMessage: start.addingTimeInterval(-60)),
                .init(name: "B", count: 5, kind: .group, lastMessage: start.addingTimeInterval(-120)),
            ], source: .accessibilityFull, reportedTotal: 2)
    }

    @Test func notificationBumpsExistingChatToTheTop() {
        var tracker = WhatsAppUnreadTracker()
        tracker.apply(scan: scan(), at: start)
        tracker.noteNotification(chat: "B", at: start.addingTimeInterval(10))
        #expect(tracker.list?.chats.map(\.name) == ["B", "A"])
        #expect(tracker.list?.chats.first?.count == 6)
        #expect(tracker.list?.chats.first?.lastMessage == start.addingTimeInterval(10))
        #expect(tracker.list?.unreadChats == 2)
        #expect(!tracker.isStale)
    }

    @Test func notificationAddsNewChat() {
        var tracker = WhatsAppUnreadTracker()
        tracker.apply(scan: scan(), at: start)
        tracker.noteNotification(chat: "New", kind: .group, at: start.addingTimeInterval(5))
        #expect(tracker.list?.chats.first?.name == "New")
        #expect(tracker.list?.chats.first?.count == 1)
        #expect(tracker.list?.chats.first?.kind == .group)
        #expect(tracker.list?.unreadChats == 3)
        tracker.reconcile(total: 3)
        #expect(!tracker.isStale)
    }

    @Test func notificationWithoutNameOnlyMarksStale() {
        var tracker = WhatsAppUnreadTracker()
        tracker.apply(scan: scan(), at: start)
        tracker.noteNotification(chat: nil, at: start)
        #expect(tracker.isStale)
        #expect(tracker.list?.unreadMessages == 7)
    }

    @Test func notificationsBeforeAScanAreIgnored() {
        var tracker = WhatsAppUnreadTracker()
        tracker.noteNotification(chat: "A", at: start)
        #expect(tracker.list == nil)
    }

    @Test func totalDropMarksStale() {
        var tracker = WhatsAppUnreadTracker()
        tracker.apply(scan: scan(), at: start)
        tracker.reconcile(total: 2)
        #expect(!tracker.isStale)
        tracker.reconcile(total: 1)  // a chat was read somewhere
        #expect(tracker.isStale)
        #expect(tracker.list?.chats.count == 2)  // not guessed away
    }

    @Test func zeroTotalClearsTheList() {
        var tracker = WhatsAppUnreadTracker()
        tracker.apply(scan: scan(), at: start)
        tracker.reconcile(total: 0)
        #expect(tracker.list?.chats.isEmpty == true)
        #expect(!tracker.isStale)
    }

    @Test func partialScanStartsStale() {
        var tracker = WhatsAppUnreadTracker()
        tracker.apply(
            scan: WhatsAppUnreadList(chats: scan().chats, source: .accessibilityVisible, reportedTotal: 9), at: start)
        #expect(tracker.isStale)
    }
}

@Suite struct WhatsAppNotificationParserTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func separateLabels() {
        let event = WhatsAppNotificationParser.event(
            appName: "WhatsApp", title: "Alex Example", description: nil, at: date)
        #expect(event == .init(chat: "Alex Example", kind: .unknown, date: date))
    }

    @Test func groupTitle() {
        let event = WhatsAppNotificationParser.event(
            appName: "WhatsApp", title: "Sam @ Book Club", description: nil, at: date)
        #expect(event == .init(chat: "Book Club", kind: .group, date: date))
    }

    @Test func descriptionFallbackIgnoresTheBody() {
        let event = WhatsAppNotificationParser.event(
            appName: nil, title: nil, description: "\u{200E}WhatsApp, Alex Example, secret message body, more", at: date
        )
        #expect(event?.chat == "Alex Example")
    }

    @Test func otherAppsAreIgnored() {
        #expect(WhatsAppNotificationParser.event(appName: "Messages", title: "Alex", description: nil, at: date) == nil)
        #expect(WhatsAppNotificationParser.event(appName: nil, title: nil, description: "Mail, Hi", at: date) == nil)
        #expect(WhatsAppNotificationParser.event(appName: "WhatsApp", title: "  ", description: nil, at: date) == nil)
    }
}
