// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import Carbon

/// Reads tab titles from Google Chrome via Apple Events, for the WhatsApp Web
/// fallback. Friday never launches Chrome by itself and never reads page
/// contents, only titles.
@MainActor
enum ChromeTabs {
    nonisolated static let bundleID = "com.google.Chrome"

    enum Access: Equatable, Sendable {
        case granted, notDetermined, denied, chromeNotRunning
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Checks (and optionally asks for) permission to talk to Chrome.
    /// Asking shows the system prompt once and blocks, so call it off the main actor.
    nonisolated static func access(askIfNeeded: Bool) -> Access {
        var address = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { pointer in
            guard AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &address) == noErr else {
                return OSStatus(procNotFound)
            }
            defer { AEDisposeDesc(&address) }
            return AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, askIfNeeded)
        }
        switch Int(status) {
        case Int(noErr): return .granted
        case -1744: return .notDetermined  // errAEEventWouldRequireUserConsent
        case -1743: return .denied  // errAEEventNotPermitted
        case Int(procNotFound): return .chromeNotRunning
        // Any other (transient) error: offer "Connect Chrome" again rather
        // than wrongly claiming Chrome is closed.
        default: return .notDetermined
        }
    }

    /// Titles of every tab in every Chrome window, or nil if unavailable.
    /// Capped at 2 s so a busy or hung Chrome cannot freeze Friday.
    static func titles() -> [String]? {
        guard isRunning else { return nil }
        let script = NSAppleScript(
            source: """
                with timeout of 2 seconds
                    tell application id "\(bundleID)" to get title of every tab of every window
                end timeout
                """)
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error), error == nil else { return nil }
        var titles: [String] = []
        for windowIndex in stride(from: 1, through: result.numberOfItems, by: 1) {
            guard let window = result.atIndex(windowIndex) else { continue }
            for tabIndex in stride(from: 1, through: window.numberOfItems, by: 1) {
                if let title = window.atIndex(tabIndex)?.stringValue { titles.append(title) }
            }
        }
        return titles
    }

    /// Opens WhatsApp Web in Chrome. Chrome does the networking, not Friday.
    static func openWhatsAppWeb() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let page = URL(string: "https://web.whatsapp.com")
        else { return }
        NSWorkspace.shared.open([page], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
}
