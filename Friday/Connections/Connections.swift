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
/// - If the Mac app is not installed: the unread number in a WhatsApp Web
///   tab's title in Chrome (titles only, via Apple Events).
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
    /// The WhatsApp Web tab in Chrome. Used alongside the Mac app (its title
    /// counts every unread chat, not just the visible ones) and on its own
    /// when the Mac app is not installed.
    private(set) var whatsappWeb: WhatsAppWebFallback.State?

    /// Every unread chat from the one full scan (made when the user clicks
    /// "Scan all chats"), kept current by WhatsApp's notifications.
    /// In memory only; never written to disk.
    private(set) var whatsappList = WhatsAppUnreadTracker()
    private var notificationWatcher: WhatsAppNotificationWatcher?

    var whatsappWebUnread: Int? {
        if case .unread(let count) = whatsappWeb { return count }
        return nil
    }
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

    /// The best unread number available (see `combinedUnread`).
    var whatsappUnread: Int? {
        Self.combinedUnread(screenChats: freshScreenReport?.unreadChats, web: whatsappWebUnread, badge: whatsappBadge)
    }

    /// WhatsApp Web's title is live and counts every unread chat, so it wins
    /// when present (it also drops as soon as chats are read). Otherwise the
    /// larger of the screen reading (visible rows only) and the Dock badge.
    nonisolated static func combinedUnread(screenChats: Int?, web: Int?, badge: Int?) -> Int? {
        if let web { return web }
        return [screenChats, badge].compactMap { $0 }.max()
    }

    var totalUnread: Int { whatsappUnread ?? 0 }

    var isWhatsAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.whatsappBundleID) != nil
    }

    func start() {
        refresh()
        startNotificationWatcher()
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
        notificationWatcher?.start()  // no-op once running; picks up a late Accessibility grant
        Task { await refreshWhatsAppBadge() }
        refreshCalendar()
    }

    /// Asks macOS once for permission to read Chrome's tab titles.
    func connectChrome() async {
        let access = await Task.detached { ChromeTabs.access(askIfNeeded: true) }.value
        if access == .denied { openAutomationSettings() }
        refresh()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
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

    func applyWhatsAppScan(_ list: WhatsAppUnreadList) {
        whatsappList.apply(scan: list)
        whatsappList.reconcile(total: whatsappUnread)
    }

    /// Listens for WhatsApp notification banners (chat name and time only) to
    /// keep the scanned list current. Needs Accessibility, so it stays idle in
    /// the sandboxed build.
    private func startNotificationWatcher() {
        let watcher = WhatsAppNotificationWatcher { [weak self] event in
            guard let self else { return }
            whatsappList.noteNotification(chat: showsNames ? event.chat : nil, kind: event.kind, at: event.date)
        }
        watcher.start()
        notificationWatcher = watcher
    }

    /// Opens or shows WhatsApp if needed, reads its chat list and returns
    /// Friday's reply. Used by the "check whatsapp" / "open whatsapp" commands.
    func checkWhatsApp(staysInFront: Bool) async -> String {
        guard isWhatsAppInstalled else {
            let state = refreshWhatsAppWeb()
            if staysInFront, ChromeTabs.isInstalled, state == .chromeClosed || state == .noTab {
                ChromeTabs.openWhatsAppWeb()
                return "WhatsApp is not installed. Opened WhatsApp Web in Chrome."
            }
            return WhatsAppWebFallback.reply(for: state)
        }
        refreshWhatsAppWeb()
        let prefix = staysInFront ? "Opened WhatsApp. " : ""
        // Without screen reading, the WhatsApp Web tab still gives the total.
        let webReply = whatsappWebUnread.map { WhatsAppWebFallback.reply(for: .unread($0)) }
        guard WhatsAppScreenReader.hasPermission else {
            if staysInFront { launchWhatsApp() }
            if let webReply { return prefix + webReply + " Allow screen reading to see who." }
            return staysInFront
                ? "Opened WhatsApp. To read unread chats, allow screen reading in Friday's dashboard."
                : "Screen reading is off. Allow it in Friday's dashboard to check WhatsApp."
        }
        switch await readWhatsAppScreen(bringToFront: true, staysInFront: staysInFront) {
        case .success(let report):
            var reply = prefix + Self.describe(report, names: showsNames)
            if let web = whatsappWebUnread, web > report.unreadChats {
                reply += " WhatsApp Web shows \(web) unread chats in total."
            }
            return reply
        case .failure(let failure):
            if let webReply { return prefix + webReply }
            switch failure {
            case .noWindow: return "WhatsApp's window did not appear. Open it once and try again."
            case .noPermission: return "Screen reading is off. Allow it in Friday's dashboard."
            default: return "Could not read WhatsApp right now."
            }
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

    private var lastWebRefresh = Date.distantPast

    private func refreshWhatsAppBadge() async {
        // Asking Chrome is an Apple Event; every 15 s is plenty.
        if Date.now.timeIntervalSince(lastWebRefresh) >= 15 {
            lastWebRefresh = .now
            refreshWhatsAppWeb()
        }
        guard isWhatsAppInstalled else { return }
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
        whatsappList.reconcile(total: whatsappUnread)
        // A badge change means a notification arrived (or chats were read):
        // recheck the chat list if the window is visible.
        if changed { await readWhatsAppScreen(bringToFront: false) }
    }

    /// Fallback: reads the unread number from a WhatsApp Web tab title in Chrome.
    @discardableResult
    private func refreshWhatsAppWeb() -> WhatsAppWebFallback.State {
        let access = ChromeTabs.isRunning ? ChromeTabs.access(askIfNeeded: false) : .chromeNotRunning
        let state = WhatsAppWebFallback.state(
            chromeInstalled: ChromeTabs.isInstalled, access: access,
            titles: access == .granted ? ChromeTabs.titles() : nil)
        whatsappWeb = state
        // With the Mac app installed, the Dock badge and screen reader own the
        // status; the Web number is only added on top.
        guard !isWhatsAppInstalled else { return state }
        switch state {
        case .unread(let count):
            whatsappStatus = .connected
            whatsappBadge = count
        case .needsPermission:
            whatsappStatus = .notConnected
            whatsappBadge = nil
        case .denied:
            whatsappStatus = .denied
            whatsappBadge = nil
        case .noChrome:
            whatsappStatus = .unavailable("WhatsApp is not installed")
            whatsappBadge = nil
        case .chromeClosed:
            whatsappStatus = .unavailable("Open WhatsApp Web in Chrome")
            whatsappBadge = nil
        case .noTab:
            whatsappStatus = .unavailable("No WhatsApp Web tab in Chrome")
            whatsappBadge = nil
        }
        return state
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
