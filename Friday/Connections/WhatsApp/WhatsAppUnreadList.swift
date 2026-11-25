// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// The list behind the WhatsApp pop-up: every unread chat with its name,
/// unread count and the time of the last message. Never message text.
struct WhatsAppUnreadList: Equatable, Sendable {
    struct Chat: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case person
            case group
            case community
            case unknown
        }

        /// Nil when "show names" is off or the name could not be read.
        var name: String?
        var count: Int
        var kind: Kind = .unknown
        /// When the last message arrived, if WhatsApp shows it.
        var lastMessage: Date?
        var muted = false
        var mentioned = false
        /// Stable within one reading; used only to drive the list UI.
        var id = UUID()

        static func == (a: Chat, b: Chat) -> Bool {
            a.name == b.name && a.count == b.count && a.kind == b.kind && a.lastMessage == b.lastMessage
                && a.muted == b.muted && a.mentioned == b.mentioned
        }
    }

    enum Source: Equatable, Sendable {
        /// Every unread chat, read through the Accessibility API.
        case accessibilityFull
        /// Only the rows WhatsApp currently shows, read through Accessibility.
        case accessibilityVisible
        /// Only the rows on screen, read from a capture of WhatsApp's window.
        case screen
    }

    var chats: [Chat]
    var source: Source
    /// WhatsApp's own unread-chat total, when known (e.g. its "Unread" filter
    /// says "86 unread chats"). May be larger than `chats.count` for partial reads.
    var reportedTotal: Int?

    var unreadChats: Int { max(chats.count, reportedTotal ?? 0) }
    var unreadMessages: Int { chats.reduce(0) { $0 + $1.count } }
    /// True when some unread chats are not in `chats`.
    var isPartial: Bool { chats.count < unreadChats }

    init(chats: [Chat], source: Source, reportedTotal: Int? = nil) {
        self.chats = Self.sorted(chats)
        self.source = source
        self.reportedTotal = reportedTotal
    }

    /// Most recent first; chats without a time go last, then by unread count.
    static func sorted(_ chats: [Chat]) -> [Chat] {
        chats.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            switch (a.lastMessage, b.lastMessage) {
            case (let x?, let y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if a.count != b.count { return a.count > b.count }
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// The same list with every name removed ("show names" off).
    func withoutNames() -> WhatsAppUnreadList {
        var copy = self
        copy.chats = chats.map { chat in
            var chat = chat
            chat.name = nil
            return chat
        }
        return copy
    }

    /// "70 unread chats · 312 messages". The message total is only given when
    /// every unread chat was read (otherwise it would undercount).
    var headline: String {
        let total = unreadChats
        guard total > 0 else { return "No unread chats" }
        let chatsText = total == 1 ? "1 unread chat" : "\(total) unread chats"
        let messages = unreadMessages
        let messagesText = messages == 1 ? "1 message" : "\(messages) messages"
        return isPartial ? chatsText : "\(chatsText) · \(messagesText)"
    }

    /// Converts a screen reading (visible rows only).
    init(screen report: WhatsAppChatListAnalyzer.Report, reportedTotal: Int?, now: Date = .now) {
        let chats = report.chats.map { chat in
            Chat(
                name: chat.name, count: chat.count,
                lastMessage: chat.timeText.flatMap { WhatsAppTimeParser.date(from: $0, now: now) },
                mentioned: chat.mentioned)
        }
        self.init(chats: chats, source: .screen, reportedTotal: reportedTotal ?? report.railTotal)
    }
}

/// Turns WhatsApp's accessibility labels into `WhatsAppUnreadList.Chat`.
///
/// What WhatsApp for Mac exposes for a chat row (an AXButton in
/// `ChatListView_TableView`):
/// - description: `"<name>, 5 unread messages"` (or just `"<name>"` when read);
///   community rows: `"<community> community, 3 unread messages from <group>, ⁨<preview>⁩. Mentioned."`
/// - value: comma-separated parts, e.g.
///   `"message, <preview>, 9:41 PM, Received from <name>, Muted"`;
///   groups say `"Message from <sender>, …, Received in <group>"`.
///
/// Privacy: the preview is never extracted. Only the name (from the
/// description), the count, the time part directly before the
/// "Received …"/"Sent …" part, and the words "Received in/from", "Muted" and
/// "Mentioned" are looked at. The raw strings are dropped by the caller.
enum WhatsAppAccessibilityParser {
    /// Removes the bidi marks WhatsApp sprinkles into its labels.
    static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            !(0x200B...0x200F).contains(scalar.value) && !(0x202A...0x202E).contains(scalar.value)
                && !(0x2066...0x2069).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// "Unread, 86 unread chats" → 86.
    static func unreadChatTotal(chipDescription: String) -> Int? {
        let text = clean(chipDescription)
        guard let match = text.firstMatch(of: #/(\d[\d,.]*) unread chats?/#) else { return nil }
        return Int(match.1.filter(\.isNumber))
    }

    /// Parses one chat row. Returns nil for rows without unread messages.
    static func chat(
        description rawDescription: String, value rawValue: String, readsNames: Bool, now: Date = .now,
        calendar: Calendar = .current
    ) -> WhatsAppUnreadList.Chat? {
        // Community rows carry a preview inside ⁨…⁩ (U+2068/U+2069); cut it off
        // before anything else touches the text.
        let beforePreview = rawDescription.split(separator: "\u{2068}", maxSplits: 1).first.map(String.init) ?? ""
        let mentioned = clean(rawDescription).hasSuffix("Mentioned.")
        let description = clean(beforePreview)

        if let match = description.firstMatch(of: #/^(.+?) community, (\d+) unread messages? from (.+?),?\s*$/#),
            let count = Int(match.2), count > 0
        {
            let name = "\(match.3) · \(match.1)"
            return .init(
                name: readsNames ? trimmed(name) : nil, count: count, kind: .community, mentioned: mentioned)
        }
        guard let match = description.firstMatch(of: #/^(.+), (\d+) unread messages?$/#),
            let count = Int(match.2), count > 0
        else { return nil }

        let parts = clean(rawValue).components(separatedBy: ", ")
        var kind = WhatsAppUnreadList.Chat.Kind.unknown
        var lastMessage: Date?
        if let index = parts.lastIndex(where: { $0.hasPrefix("Received") || $0.hasPrefix("Sent") }) {
            let part = parts[index]
            if part.hasPrefix("Received in ") || part.hasPrefix("Sent in ") {
                kind = .group
            } else if part.hasPrefix("Received from ") || part.hasPrefix("Sent to ") {
                kind = .person
            }
            if index > 0 { lastMessage = WhatsAppTimeParser.date(from: parts[index - 1], now: now, calendar: calendar) }
        }
        if parts.first?.hasPrefix("Message from ") == true { kind = .group }
        return .init(
            name: readsNames ? trimmed(String(match.1)) : nil, count: count, kind: kind, lastMessage: lastMessage,
            muted: parts.contains("Muted"), mentioned: mentioned || parts.contains("Mentioned"))
    }

    private static func trimmed(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// Reads the times WhatsApp shows in its chat list.
enum WhatsAppTimeParser {
    private static let months = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december",
    ]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// Accepts "9:41 PM", "21:41", "Yesterday", "Yesterday at 9:41 PM",
    /// "Monday", "24 November at 9:41 PM", "November 24, 2025 at 9:41 PM",
    /// "24/11/2026". Anything else returns nil.
    static func date(from rawText: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let text = WhatsAppAccessibilityParser.clean(rawText)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 40 else { return nil }

        var dayPart = text
        var clock: DateComponents?
        if let match = text.firstMatch(of: #/^(?:(.+?)(?: at |, | ))?(\d{1,2})[:.](\d{2})(?:\s?([AaPp])\.?[Mm]\.?)?$/#)
        {
            guard var hour = Int(match.2), let minute = Int(match.3), minute < 60 else { return nil }
            if let meridiem = match.4 {
                guard (1...12).contains(hour) else { return nil }
                hour = hour % 12 + (meridiem.lowercased() == "p" ? 12 : 0)
            }
            guard hour < 24 else { return nil }
            clock = DateComponents(hour: hour, minute: minute)
            dayPart = match.1.map(String.init) ?? ""
        }
        guard let day = self.day(dayPart, now: now, calendar: calendar) else { return nil }
        let time = clock ?? DateComponents(hour: 12, minute: 0)
        return calendar.date(
            bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day)
    }

    /// The day a label refers to (start of that day), never in the future.
    private static func day(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.isEmpty || lower == "today" { return today }
        if lower == "yesterday" { return calendar.date(byAdding: .day, value: -1, to: today) }
        if let weekday = weekdays.firstIndex(of: lower) {
            let current = calendar.component(.weekday, from: today) - 1
            var back = (current - weekday + 7) % 7
            if back == 0 { back = 7 }
            return calendar.date(byAdding: .day, value: -back, to: today)
        }
        // "24 November", "24 Nov 2025", "November 24", "November 24, 2025"
        if let match = lower.firstMatch(of: #/^(\d{1,2}) ([a-z]+)\.?,?(?: (\d{4}))?$/#) {
            return dated(
                day: Int(match.1), month: month(String(match.2)), year: match.3.flatMap { Int($0) }, now: now,
                calendar: calendar)
        }
        if let match = lower.firstMatch(of: #/^([a-z]+)\.? (\d{1,2}),?(?: (\d{4}))?$/#) {
            return dated(
                day: Int(match.2), month: month(String(match.1)), year: match.3.flatMap { Int($0) }, now: now,
                calendar: calendar)
        }
        // "24/11/2026" or "11/24/26": day-first unless the locale is month-first.
        if let match = lower.firstMatch(of: #/^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$/#),
            let a = Int(match.1), let b = Int(match.2), var year = Int(match.3)
        {
            if year < 100 { year += 2000 }
            let format = DateFormatter.dateFormat(fromTemplate: "dMy", options: 0, locale: calendar.locale ?? .current)
            let monthFirst: Bool
            if a > 12 {
                monthFirst = false
            } else if b > 12 {
                monthFirst = true
            } else {
                monthFirst = format?.first == "M"
            }
            return dated(
                day: monthFirst ? b : a, month: monthFirst ? a : b, year: year, now: now, calendar: calendar)
        }
        return nil
    }

    private static func month(_ name: String) -> Int? {
        guard name.count >= 3 else { return nil }
        return months.firstIndex { $0.hasPrefix(name) }.map { $0 + 1 }
    }

    private static func dated(day: Int?, month: Int?, year: Int?, now: Date, calendar: Calendar) -> Date? {
        guard let day, let month, (1...31).contains(day), (1...12).contains(month) else { return nil }
        let currentYear = calendar.component(.year, from: now)
        var components = DateComponents(year: year ?? currentYear, month: month, day: day)
        guard var date = calendar.date(from: components), calendar.component(.day, from: date) == day else {
            return nil
        }
        // Without a year, a date "in the future" means last year.
        if year == nil, date > now {
            components.year = currentYear - 1
            date = calendar.date(from: components) ?? date
        }
        return date
    }

    /// Short label for the list: "9:41 PM", "Yesterday", "Monday", "24 Nov".
    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
            ?? 99
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

/// Keeps the pop-up's list current after one full scan, without touching
/// WhatsApp's window again:
/// - a WhatsApp notification bumps that chat (count + 1, time = now), or adds it;
/// - when WhatsApp's own total no longer matches (chats were read, or muted
///   chats got messages), the list is marked stale instead of guessed.
struct WhatsAppUnreadTracker: Equatable, Sendable {
    private(set) var list: WhatsAppUnreadList?
    private(set) var scannedAt: Date?
    /// The list may no longer match WhatsApp; a new scan would fix it.
    private(set) var isStale = false

    /// Stores a complete scan.
    mutating func apply(scan: WhatsAppUnreadList, at date: Date = .now) {
        list = scan
        scannedAt = date
        isStale = scan.isPartial
    }

    /// A WhatsApp notification arrived for `chat`. Without a name (names off,
    /// or the banner had none) only staleness can be recorded.
    mutating func noteNotification(
        chat name: String?, kind: WhatsAppUnreadList.Chat.Kind = .unknown, at date: Date = .now
    ) {
        guard var current = list else { return }
        guard let name, !name.isEmpty else {
            isStale = true
            return
        }
        var chats = current.chats
        if let index = chats.firstIndex(where: { $0.name == name }) {
            chats[index].count += 1
            chats[index].lastMessage = date
            if chats[index].kind == .unknown { chats[index].kind = kind }
        } else {
            chats.append(.init(name: name, count: 1, kind: kind, lastMessage: date))
            if let total = current.reportedTotal { current.reportedTotal = total + 1 }
        }
        current.chats = WhatsAppUnreadList.sorted(chats)
        list = current
    }

    /// Compares with WhatsApp's live unread-chat total (Web title, Dock badge).
    mutating func reconcile(total: Int?) {
        guard let total, let current = list else { return }
        if total != current.unreadChats { isStale = true }
        if total == 0 {
            // Everything was read: that much is certain.
            list = WhatsAppUnreadList(chats: [], source: current.source, reportedTotal: 0)
            isStale = false
        }
    }

    mutating func clear() {
        list = nil
        scannedAt = nil
        isStale = false
    }
}
