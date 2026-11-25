// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import ApplicationServices

/// One WhatsApp notification, reduced to what Friday may keep.
struct WhatsAppNotificationEvent: Equatable, Sendable {
    var chat: String
    var kind: WhatsAppUnreadList.Chat.Kind
    var date: Date
}

/// Turns a notification banner's accessibility labels into an event.
///
/// Privacy: a banner shows the app name, a title (the chat, or
/// "Sender @ Group") and the message text. Only the app name and the title
/// are read; the body is never touched.
enum WhatsAppNotificationParser {
    /// - Parameters:
    ///   - appName: the banner's app label, if it has a separate one.
    ///   - title: the banner's title line.
    ///   - description: the banner's own description, used only to find the
    ///     app name and title ("WhatsApp, <title>, …") when there are no
    ///     separate labels. Everything after the title is ignored.
    static func event(appName: String?, title: String?, description: String?, at date: Date)
        -> WhatsAppNotificationEvent?
    {
        var app = appName.map(WhatsAppAccessibilityParser.clean)
        var title = title.map(WhatsAppAccessibilityParser.clean)
        if app == nil || title == nil, let description {
            let parts = WhatsAppAccessibilityParser.clean(description).components(separatedBy: ", ")
            if app == nil { app = parts.first }
            if title == nil, parts.count > 1 { title = parts[1] }
        }
        guard app?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("WhatsApp") == .orderedSame,
            let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty
        else { return nil }
        // Group messages: "Sender @ Group".
        if let range = title.range(of: " @ ", options: .backwards) {
            let group = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !group.isEmpty { return .init(chat: group, kind: .group, date: date) }
        }
        return .init(chat: title, kind: .unknown, date: date)
    }
}

/// Watches Notification Center for WhatsApp banners through the
/// Accessibility API. Read-only: it never clicks, dismisses or opens anything.
///
/// It only sees banners macOS actually shows (not during Focus / Do Not
/// Disturb, or if WhatsApp's notification style is "None"), and, like all
/// Accessibility use, it is blocked by the App Sandbox. Missed banners are
/// caught by `WhatsAppUnreadTracker.reconcile`, which marks the list stale.
@MainActor
final class WhatsAppNotificationWatcher {
    static let notificationCenterBundleID = "com.apple.notificationcenterui"

    private let onEvent: @MainActor (WhatsAppNotificationEvent) -> Void
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var recent: [String: Date] = [:]

    init(onEvent: @escaping @MainActor (WhatsAppNotificationEvent) -> Void) {
        self.onEvent = onEvent
    }

    var isRunning: Bool { observer != nil }

    /// Starts (or restarts, if Notification Center relaunched) observing.
    func start() {
        guard !WhatsAppAccessibilityReader.isSandboxed, WhatsAppAccessibilityReader.isTrusted,
            let center = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterBundleID)
                .first
        else { return }
        if observer != nil, center.processIdentifier == pid { return }
        stop()

        var created: AXObserver?
        guard AXObserverCreate(center.processIdentifier, Self.callback, &created) == .success, let created else {
            return
        }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(created, app, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        pid = center.processIdentifier
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        pid = 0
    }

    private static let callback: AXObserverCallback = { _, element, _, context in
        guard let context else { return }
        let watcher = Unmanaged<WhatsAppNotificationWatcher>.fromOpaque(context).takeUnretainedValue()
        // Parse here so only the Sendable events (name + time) cross over.
        let now = Date.now
        let events = banners(in: element).compactMap { event(from: $0, at: now) }
        guard !events.isEmpty else { return }
        // AX observers deliver on the run loop they were added to: the main one.
        MainActor.assumeIsolated { watcher.handle(events, at: now) }
    }

    private func handle(_ events: [WhatsAppNotificationEvent], at now: Date) {
        for event in events {
            // One banner can trigger several AX events; count it once.
            if let last = recent[event.chat], now.timeIntervalSince(last) < 2 { continue }
            recent[event.chat] = now
            recent = recent.filter { now.timeIntervalSince($0.value) < 10 }
            onEvent(event)
        }
    }

    // MARK: - Reading banners

    /// Banner elements: subroles such as AXNotificationCenterBanner/Alert.
    nonisolated private static func banners(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 8 else { return [] }
        if let subrole = string(element, kAXSubroleAttribute), subrole.hasPrefix("AXNotificationCenter") {
            return [element]
        }
        return children(element).flatMap { banners(in: $0, depth: depth + 1) }
    }

    /// Reads only the app label and the title. Static texts are taken by
    /// identifier when present; the body text is never read.
    nonisolated private static func event(from banner: AXUIElement, at date: Date) -> WhatsAppNotificationEvent? {
        var appName: String?
        var title: String?
        for child in children(banner) where string(child, kAXRoleAttribute) == kAXStaticTextRole {
            switch string(child, kAXIdentifierAttribute) {
            case "appName", "app-name": appName = string(child, kAXValueAttribute)
            case "title": title = string(child, kAXValueAttribute)
            default: continue
            }
        }
        let description = (appName == nil || title == nil) ? string(banner, kAXDescriptionAttribute) : nil
        return WhatsAppNotificationParser.event(appName: appName, title: title, description: description, at: date)
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
