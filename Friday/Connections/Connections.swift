// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import EventKit
import Observation

/// Live unread counts and schedule for the dashboard and the orb badge.
///
/// WhatsApp has two sources:
/// - the Dock badge: instant, cheap, polled every 5 s (works only if WhatsApp
///   badges its icon);
/// - the screen reader: reads WhatsApp's chat list (unread chats, counts,
///   mentions, names). It runs when you ask, when the badge changes, on wake,
///   and every 10 minutes. In the background it only reads an already-visible
///   window and never changes what is on screen.
@MainActor
@Observable
final class Connections {
    enum Status: Equatable {
        case notConnected
        case denied
        case unavailable(String)
        case connected
    }

    static let whatsappBundleID = "net.whatsapp.WhatsApp"
    static let showNamesKey = "whatsappShowNames"
    static let recheckInterval: TimeInterval = 10 * 60

    private(set) var whatsappStatus: Status = .notConnected
    private(set) var whatsappBadge: Int?
    private(set) var whatsappScreen: WhatsAppChatListAnalyzer.Report?
    private(set) var whatsappScreenDate: Date?
    private(set) var screenPermission = WhatsAppScreenReader.hasPermission
    private(set) var isReadingWhatsApp = false
    private(set) var calendarStatus: Status = .notConnected
    private(set) var calendar: CalendarSource.Summary?

    private let calendarSource = CalendarSource()
    private var badgeTimer: Timer?
    private var recheckTimer: Timer?

    var showsNames: Bool {
        UserDefaults.standard.object(forKey: Self.showNamesKey) as? Bool ?? true
    }

    /// A screen reading is trusted for one recheck interval.
    var freshScreenReport: WhatsAppChatListAnalyzer.Report? {
        guard let date = whatsappScreenDate, Date.now.timeIntervalSince(date) < Self.recheckInterval else { return nil }
        return whatsappScreen
    }

    /// Unread WhatsApp messages: the fresh screen reading, else the Dock badge.
    var whatsappUnread: Int? {
        if let report = freshScreenReport { return max(report.unreadMessages, whatsappBadge ?? 0) }
        return whatsappBadge
    }

    var totalUnread: Int { whatsappUnread ?? 0 }

    var isWhatsAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.whatsappBundleID) != nil
    }

    func start() {
        refresh()
        Task { await readWhatsAppScreen(bringToFront: false) }

        // Badge reads are cheap and local, so poll often for a live feel.
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        // Heavier screen recheck every 10 minutes. Timers do not fire while
        // the Mac sleeps; the tolerance lets macOS batch wake-ups to save power.
        recheckTimer = Timer.scheduledTimer(withTimeInterval: Self.recheckInterval, repeats: true) { _ in
            MainActor.assumeIsolated {
                _ = Task { await self.readWhatsAppScreen(bringToFront: false) }
            }
        }
        recheckTimer?.tolerance = 60

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.refresh() }
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.refresh()
                Task { await self.readWhatsAppScreen(bringToFront: false) }
            }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    func refresh() {
        screenPermission = WhatsAppScreenReader.hasPermission
        Task { await refreshWhatsAppBadge() }
        refreshCalendar()
    }

    func openWhatsApp() {
        Task { _ = await checkWhatsApp(staysInFront: true) }
    }

    func requestScreenPermission() {
        screenPermission = WhatsAppScreenReader.requestPermission()
        if !screenPermission {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func connectCalendar() async {
        _ = await calendarSource.requestAccess()
        refreshCalendar()
    }

    // MARK: - WhatsApp

    /// Opens or shows WhatsApp if needed, reads its chat list and returns
    /// Friday's reply. Used by the "check whatsapp" / "open whatsapp" commands.
    func checkWhatsApp(staysInFront: Bool) async -> String {
        guard isWhatsAppInstalled else { return "WhatsApp is not installed." }
        guard WhatsAppScreenReader.hasPermission else {
            if staysInFront { launchWhatsApp() }
            return staysInFront
                ? "Opened WhatsApp. To read unread chats, allow screen reading in Friday's dashboard."
                : "Screen reading is off. Allow it in Friday's dashboard to check WhatsApp."
        }
        switch await readWhatsAppScreen(bringToFront: true, staysInFront: staysInFront) {
        case .success(let report):
            return (staysInFront ? "Opened WhatsApp. " : "") + Self.describe(report, names: showsNames)
        case .failure(.noWindow):
            return "WhatsApp's window did not appear. Open it once and try again."
        case .failure(.noPermission):
            return "Screen reading is off. Allow it in Friday's dashboard."
        case .failure:
            return "Could not read WhatsApp right now."
        }
    }

    @discardableResult
    func readWhatsAppScreen(
        bringToFront: Bool, staysInFront: Bool = false
    ) async -> Result<WhatsAppChatListAnalyzer.Report, WhatsAppScreenReader.Failure> {
        guard !isReadingWhatsApp else { return .failure(.captureFailed) }
        isReadingWhatsApp = true
        defer { isReadingWhatsApp = false }
        let result = await WhatsAppScreenReader.read(
            bringToFront: bringToFront, staysInFront: staysInFront, readsNames: showsNames)
        if case .success(let report) = result {
            whatsappScreen = report
            whatsappScreenDate = .now
        }
        return result
    }

    static func describe(_ report: WhatsAppChatListAnalyzer.Report, names: Bool) -> String {
        guard report.unreadChats > 0 else { return "WhatsApp: no unread chats." }
        let chats = report.unreadChats == 1 ? "1 unread chat" : "\(report.unreadChats) unread chats"
        let messages = report.unreadMessages == 1 ? "1 message" : "\(report.unreadMessages) messages"
        var reply = "WhatsApp: \(chats), \(messages)."
        if names {
            let list = report.chats.map { chat -> String in
                let name = chat.name ?? "Unknown chat"
                return chat.mentioned ? "\(name) (\(chat.count), mentioned you)" : "\(name) (\(chat.count))"
            }
            reply += " " + list.joined(separator: ", ") + "."
        }
        return reply
    }

    private func launchWhatsApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.whatsappBundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func refreshWhatsAppBadge() async {
        guard isWhatsAppInstalled else {
            whatsappStatus = .unavailable("WhatsApp is not installed")
            whatsappBadge = nil
            return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.whatsappBundleID).isEmpty
        guard running else {
            whatsappStatus = .unavailable("WhatsApp is closed")
            whatsappBadge = nil
            return
        }
        guard let count = await DockBadge.count(forBundleID: Self.whatsappBundleID) else {
            whatsappStatus = .unavailable("Could not read the Dock badge")
            whatsappBadge = nil
            return
        }
        let changed = whatsappBadge != nil && whatsappBadge != count
        whatsappStatus = .connected
        whatsappBadge = count
        // A badge change means a notification arrived (or chats were read):
        // recheck the chat list if the window is visible.
        if changed { await readWhatsAppScreen(bringToFront: false) }
    }

    private func refreshCalendar() {
        if calendarSource.isAuthorized {
            calendarStatus = .connected
            calendar = calendarSource.summary()
        } else {
            calendarStatus = calendarSource.isDenied ? .denied : .notConnected
            calendar = nil
        }
    }
}
