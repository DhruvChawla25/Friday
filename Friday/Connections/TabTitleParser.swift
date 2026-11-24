import Foundation

/// Extracts unread counts from browser tab titles.
///
/// Privacy: only titles that match the WhatsApp or Gmail inbox patterns are
/// used, and only the number (plus the Gmail account address) is kept.
/// Every other tab title is discarded immediately.
enum TabTitleParser {
    struct GmailAccount: Equatable, Sendable, Identifiable {
        let email: String
        let unread: Int
        var id: String { email }
    }

    /// `(74) WhatsApp` → 74, `WhatsApp` → 0, no WhatsApp tab → nil.
    static func whatsappUnread(in titles: [String]) -> Int? {
        var found: Int?
        for title in titles {
            if let match = title.wholeMatch(of: /\((\d[\d,]*)\)\s+WhatsApp.*/) {
                found = max(found ?? 0, number(match.1))
            } else if title.hasPrefix("WhatsApp") {
                found = max(found ?? 0, 0)
            }
        }
        return found
    }

    /// `Inbox (5) - me@gmail.com - Gmail` → me@gmail.com: 5. One entry per account.
    static func gmailAccounts(in titles: [String]) -> [GmailAccount] {
        var accounts: [String: Int] = [:]
        for title in titles {
            guard let match = title.wholeMatch(of: /Inbox(?: \((\d[\d,]*)\))? [-–] (\S+@\S+) [-–] .*Gmail/) else {
                continue
            }
            let email = String(match.2).lowercased()
            let unread = match.1.map(number) ?? 0
            accounts[email] = max(accounts[email] ?? 0, unread)
        }
        return accounts.map { GmailAccount(email: $0.key, unread: $0.value) }.sorted { $0.email < $1.email }
    }

    private static func number(_ text: Substring) -> Int {
        Int(text.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}
