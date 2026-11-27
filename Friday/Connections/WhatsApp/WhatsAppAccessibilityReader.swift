// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import ApplicationServices

/// Reads WhatsApp for Mac's chat list through the Accessibility API: each
/// chat row exposes its name, unread count and last-message time as labels,
/// so no screenshots or OCR are needed.
///
/// - It never activates WhatsApp, switches Spaces or moves windows.
/// - `read(fullScan: false)` only looks at the rows WhatsApp has loaded;
///   nothing on screen changes.
/// - `read(fullScan: true)` (only when the user asks) selects WhatsApp's
///   "Unread" filter, pages through the list, then puts the filter and
///   scroll position back. WhatsApp's list visibly moves while it runs.
///
/// Privacy: labels also contain message previews. They are parsed by
/// `WhatsAppAccessibilityParser`, which keeps only name, count and time; the
/// raw strings never leave the parsing function and are never logged.
///
/// Limitation: macOS's App Sandbox blocks the Accessibility API for other
/// apps (every call fails with `kAXErrorCannotComplete`), so this works only
/// in a build without the sandbox (see GitHub issue #6).
enum WhatsAppAccessibilityReader {
    static let bundleID = "net.whatsapp.WhatsApp"

    enum Failure: Error, Equatable {
        /// The App Sandbox blocks the Accessibility API.
        case sandboxed
        /// Friday is not allowed in System Settings → Privacy → Accessibility.
        case notTrusted
        case notRunning
        /// No WhatsApp window on this desktop (closed, or on another Space).
        case noWindow
        /// The window exists but its chat list did not answer.
        case unreadable
    }

    static var isSandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's Accessibility prompt (it only adds Friday to the list;
    /// the user still flips the switch in System Settings).
    @MainActor static func requestTrust() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func read(fullScan: Bool, readsNames: Bool) async -> Result<WhatsAppUnreadList, Failure> {
        await Task.detached(priority: .userInitiated) {
            Session.read(fullScan: fullScan, readsNames: readsNames)
        }.value
    }

    /// All AX work happens synchronously inside one detached task.
    private struct Session {
        let window: AXUIElement
        let readsNames: Bool

        static func read(fullScan: Bool, readsNames: Bool) -> Result<WhatsAppUnreadList, Failure> {
            guard
                let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            else { return .failure(.notRunning) }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 2)
            var windows: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows)
            if error == .cannotComplete || error == .apiDisabled {
                if isSandboxed { return .failure(.sandboxed) }
                if !isTrusted { return .failure(.notTrusted) }
                return .failure(.unreadable)
            }
            if !isTrusted { return .failure(.notTrusted) }
            let session = ((windows as? [AXUIElement]) ?? []).lazy
                .map { Session(window: $0, readsNames: readsNames) }
                .first { $0.table() != nil }
            guard let session else { return .failure(.noWindow) }
            return fullScan ? session.scanAll() : session.readLoaded()
        }

        /// Rows WhatsApp has already loaded. Changes nothing on screen.
        func readLoaded() -> Result<WhatsAppUnreadList, Failure> {
            guard let table = table() else { return .failure(.unreadable) }
            var collector = Collector()
            collector.add(cells(of: table), readsNames: readsNames)
            let total = unreadTotal()
            let complete = total.map { collector.chats.count >= $0 } ?? false
            return .success(
                WhatsAppUnreadList(
                    chats: collector.chats, source: complete ? .accessibilityFull : .accessibilityVisible,
                    reportedTotal: total))
        }

        /// Selects the Unread filter, pages through it, then restores the list.
        func scanAll() -> Result<WhatsAppUnreadList, Failure> {
            let total = unreadTotal()
            let previous = Chip.all.first { chip($0).map(isSelected) ?? false } ?? Chip.everything
            if previous != Chip.unread { select(Chip.unread) }
            defer { restore(previous) }

            var collector = Collector()
            var idlePages = 0
            for _ in 0..<120 {
                guard let table = table() else { break }
                let added = collector.add(cells(of: table), readsNames: readsNames)
                idlePages = added == 0 ? idlePages + 1 : 0
                if idlePages >= 2 { break }
                if let total, collector.chats.count >= total, added == 0 { break }
                AXUIElementPerformAction(table, "AXScrollDownByPage" as CFString)
                usleep(300_000)
            }
            return .success(
                WhatsAppUnreadList(chats: collector.chats, source: .accessibilityFull, reportedTotal: total))
        }

        // MARK: - Elements

        enum Chip {
            static let everything = "ChatListFilterAction_All"
            static let unread = "ChatListFilterAction_Unread"
            static let all = [everything, unread, "ChatListFilterAction_Favorites", "ChatListFilterAction_Groups"]
        }

        func table() -> AXUIElement? { find("ChatListView_TableView", in: window) }
        func chip(_ id: String) -> AXUIElement? { find(id, in: window) }

        func unreadTotal() -> Int? {
            chip(Chip.unread).flatMap { string($0, kAXDescriptionAttribute) }
                .flatMap(WhatsAppAccessibilityParser.unreadChatTotal)
        }

        func isSelected(_ element: AXUIElement) -> Bool {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &value) == .success
            else { return false }
            return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
        }

        /// Presses a filter chip and waits (up to ~2 s) for it to take effect.
        @discardableResult
        func select(_ id: String) -> Bool {
            for _ in 0..<3 {
                guard let chip = chip(id) else { return false }
                AXUIElementPerformAction(chip, kAXPressAction as CFString)
                for _ in 0..<10 {
                    usleep(200_000)
                    if let chip = self.chip(id), isSelected(chip) { return true }
                }
            }
            return false
        }

        /// Scrolls back to the top (where the filter chips live) and re-selects
        /// the filter the user had.
        func restore(_ previous: String) {
            for _ in 0..<150 {
                guard let table = table() else { return }
                if chip(previous) != nil, isAtTop(table) { break }
                AXUIElementPerformAction(table, "AXScrollUpByPage" as CFString)
                usleep(40_000)
            }
            usleep(250_000)
            if let current = chip(previous), !isSelected(current) { select(previous) }
        }

        func isAtTop(_ table: AXUIElement) -> Bool {
            children(table).first.map { string($0, kAXIdentifierAttribute) == "ChatListView_chipButtonsCell" } ?? false
        }

        /// (description, value) of each chat row currently loaded.
        func cells(of table: AXUIElement) -> [(String, String)] {
            children(table).compactMap { row in
                var cell = row
                let kids = children(row)
                if kids.count == 1 { cell = kids[0] }
                // Filter chips, the archive row and headers have identifiers; chats do not.
                guard (string(cell, kAXIdentifierAttribute) ?? "").isEmpty,
                    let description = string(cell, kAXDescriptionAttribute), !description.isEmpty
                else { return nil }
                return (description, string(cell, kAXValueAttribute) ?? "")
            }
        }

        // MARK: - AX helpers

        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
            else { return [] }
            return (value as? [AXUIElement]) ?? []
        }

        func string(_ element: AXUIElement, _ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }

        func find(_ identifier: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
            guard depth < 16 else { return nil }
            if string(element, kAXIdentifierAttribute) == identifier { return element }
            for child in children(element) {
                if let found = find(identifier, in: child, depth: depth + 1) { return found }
            }
            return nil
        }
    }

    /// Collects parsed chats across pages, skipping rows already seen.
    struct Collector {
        private(set) var chats: [WhatsAppUnreadList.Chat] = []
        private var seen = Set<String>()

        /// Returns how many new unread chats were added. The raw labels are
        /// used only for parsing and a hashed de-duplication key.
        @discardableResult
        mutating func add(_ cells: [(String, String)], readsNames: Bool, now: Date = .now) -> Int {
            var added = 0
            for (description, value) in cells {
                // Parse with names so duplicates can be told apart, then drop
                // the name if names are off.
                guard
                    var chat = WhatsAppAccessibilityParser.chat(
                        description: description, value: value, readsNames: true, now: now)
                else { continue }
                let key = "\(chat.name ?? "")|\(chat.count)|\(chat.lastMessage?.timeIntervalSince1970 ?? 0)"
                guard seen.insert(key).inserted else { continue }
                if !readsNames { chat.name = nil }
                chats.append(chat)
                added += 1
            }
            return added
        }
    }
}
