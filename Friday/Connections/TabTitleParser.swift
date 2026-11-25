// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Finds WhatsApp Web's unread number in browser tab titles.
///
/// Privacy: only the number in a WhatsApp tab's title is kept. Every other
/// tab title is discarded immediately and never stored or logged.
enum TabTitleParser {
    /// `(74) WhatsApp` → 74, `WhatsApp` → 0, no WhatsApp tab → nil.
    static func whatsappUnread(in titles: [String]) -> Int? {
        var found: Int?
        for title in titles {
            if let match = title.wholeMatch(of: /\((\d[\d,]*)\)\s+WhatsApp.*/) {
                found = max(found ?? 0, Int(match.1.replacingOccurrences(of: ",", with: "")) ?? 0)
            } else if title == "WhatsApp" || title.hasPrefix("WhatsApp ") {
                found = max(found ?? 0, 0)
            }
        }
        return found
    }
}
