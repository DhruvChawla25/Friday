// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Where WhatsApp's unread number comes from when the Mac app is not
/// installed: a WhatsApp Web tab in Chrome. Pure logic, unit-tested.
enum WhatsAppWebFallback {
    enum State: Equatable {
        case noChrome
        case chromeClosed
        case needsPermission
        case denied
        case noTab
        case unread(Int)
    }

    static func state(chromeInstalled: Bool, access: ChromeTabs.Access, titles: [String]?) -> State {
        guard chromeInstalled else { return .noChrome }
        switch access {
        case .chromeNotRunning: return .chromeClosed
        case .notDetermined: return .needsPermission
        case .denied: return .denied
        case .granted:
            guard let titles else { return .chromeClosed }
            return TabTitleParser.whatsappUnread(in: titles).map(State.unread) ?? .noTab
        }
    }

    /// Friday's reply to "check whatsapp" in fallback mode.
    static func reply(for state: State) -> String {
        switch state {
        case .noChrome: "WhatsApp is not installed, and Chrome is not available for WhatsApp Web."
        case .chromeClosed: "WhatsApp is not installed. Open WhatsApp Web in Chrome and try again."
        case .needsPermission: "Using WhatsApp Web in Chrome. Click Connect Chrome on the WhatsApp tile first."
        case .denied: "Friday may not read Chrome tab titles. Allow it in System Settings → Automation."
        case .noTab: "No WhatsApp Web tab is open in Chrome."
        case .unread(0): "WhatsApp Web: no unread messages."
        case .unread(1): "WhatsApp Web: 1 unread message."
        case .unread(let count): "WhatsApp Web: \(count) unread messages."
        }
    }
}
