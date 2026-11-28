// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import EventKit
import Observation

/// Live unread counts and schedule for the dashboard and the orb badge.
///
/// WhatsApp:
/// - WhatsApp for Mac installed: Friday reads unread counts straight from
///   WhatsApp's own database on this Mac, read-only, every few seconds.
///   No internet, no screen recording, nothing is ever sent or changed.
/// - Not installed: the unread number in a WhatsApp Web tab's title in
///   Chrome (titles only, via Apple Events).
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

    private(set) var whatsappStatus: Status = .notConnected
    /// The latest reading of WhatsApp's database. In memory only.
    private(set) var whatsappReport: WhatsAppDatabase.Report?
    private(set) var whatsappReadDate: Date?
    /// The WhatsApp Web tab in Chrome, used when WhatsApp for Mac is not installed.
    private(set) var whatsappWeb: WhatsAppWebFallback.State?

    var whatsappWebUnread: Int? {
        if case .unread(let count) = whatsappWeb { return count }
        return nil
    }
    private(set) var calendarStatus: Status = .notConnected
    private(set) var calendar: CalendarSource.Summary?

    private let calendarSource = CalendarSource()
    private var timer: Timer?
    private var isReadingDatabase = false

    var showsNames: Bool {
        UserDefaults.standard.object(forKey: Self.showNamesKey) as? Bool ?? true
    }

    /// Unread chats: from WhatsApp's database, else WhatsApp Web's title.
    var whatsappUnread: Int? {
        Self.combinedUnread(database: whatsappReport?.unreadChats, web: whatsappWebUnread)
    }

    nonisolated static func combinedUnread(database: Int?, web: Int?) -> Int? {
        database ?? web
    }

    var totalUnread: Int { whatsappUnread ?? 0 }

    var isWhatsAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.whatsappBundleID) != nil
    }

    func start() {
        refresh()
        // Reading the database is a small local query, so poll often for a live feel.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        timer?.tolerance = 1

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.refresh() }
            }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    func refresh() {
        Task { await refreshWhatsApp() }
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

    /// Privacy & Security, where "App Management" / "Files and Folders" live.
    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
    }

    func openWhatsApp() {
        Task { _ = await checkWhatsApp(staysInFront: true) }
    }

    func connectCalendar() async {
        _ = await calendarSource.requestAccess()
        refreshCalendar()
    }

    // MARK: - WhatsApp

    /// Reads WhatsApp's unread chats and returns Friday's reply. Used by the
    /// "check whatsapp" / "open whatsapp" commands.
    func checkWhatsApp(staysInFront: Bool) async -> String {
        guard isWhatsAppInstalled else {
            let state = refreshWhatsAppWeb()
            if staysInFront, ChromeTabs.isInstalled, state == .chromeClosed || state == .noTab {
                ChromeTabs.openWhatsAppWeb()
                return "WhatsApp is not installed. Opened WhatsApp Web in Chrome."
            }
            return WhatsAppWebFallback.reply(for: state)
        }
        if staysInFront { launchWhatsApp() }
        let prefix = staysInFront ? "Opened WhatsApp. " : ""
        await refreshWhatsApp()
        guard let report = whatsappReport else {
            if case .unavailable(let reason) = whatsappStatus { return prefix + reason + "." }
            return prefix + "Could not read WhatsApp right now."
        }
        return prefix + Self.describe(report, names: showsNames)
    }

    static func describe(_ report: WhatsAppDatabase.Report, names: Bool, limit: Int = 5) -> String {
        guard report.unreadChats > 0 else { return "WhatsApp: no unread chats." }
        let chats = report.unreadChats == 1 ? "1 unread chat" : "\(report.unreadChats) unread chats"
        let messages = report.unreadMessages == 1 ? "1 message" : "\(report.unreadMessages) messages"
        var reply = "WhatsApp: \(chats), \(messages)."
        if report.mutedChats > 0 { reply += " \(report.mutedChats) muted." }
        if names {
            let list = report.chats.prefix(limit).map { chat -> String in
                let name = chat.name ?? "Unknown chat"
                return chat.count > 0 ? "\(name) (\(chat.count))" : name
            }
            let more = report.unreadChats > limit ? ", +\(report.unreadChats - limit) more" : ""
            reply += " Latest: " + list.joined(separator: ", ") + more + "."
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

    private func refreshWhatsApp() async {
        guard isWhatsAppInstalled else {
            whatsappReport = nil
            // Asking Chrome is an Apple Event; every 15 s is plenty.
            if Date.now.timeIntervalSince(lastWebRefresh) >= 15 {
                lastWebRefresh = .now
                refreshWhatsAppWeb()
            }
            return
        }
        whatsappWeb = nil
        guard !isReadingDatabase else { return }
        isReadingDatabase = true
        defer { isReadingDatabase = false }
        let names = showsNames
        let result = await Task.detached(priority: .utility) {
            WhatsAppDatabase.read(home: AIUsageMonitor.realHome, readsNames: names)
        }.value
        switch result {
        case .success(let report):
            whatsappReport = report
            whatsappReadDate = .now
            whatsappStatus = .connected
        case .failure(.notFound):
            whatsappReport = nil
            whatsappStatus = .unavailable("Open WhatsApp and sign in once")
        case .failure(.blocked):
            whatsappReport = nil
            whatsappStatus = .denied
        case .failure(.unreadable):
            // WhatsApp may be mid-write; keep the last good reading.
            if whatsappReport == nil { whatsappStatus = .unavailable("Could not read WhatsApp's data") }
        }
    }

    /// Fallback: reads the unread number from a WhatsApp Web tab title in Chrome.
    @discardableResult
    private func refreshWhatsAppWeb() -> WhatsAppWebFallback.State {
        let access = ChromeTabs.isRunning ? ChromeTabs.access(askIfNeeded: false) : .chromeNotRunning
        let state = WhatsAppWebFallback.state(
            chromeInstalled: ChromeTabs.isInstalled, access: access,
            titles: access == .granted ? ChromeTabs.titles() : nil)
        whatsappWeb = state
        switch state {
        case .unread: whatsappStatus = .connected
        case .needsPermission: whatsappStatus = .notConnected
        case .denied: whatsappStatus = .denied
        case .noChrome: whatsappStatus = .unavailable("WhatsApp is not installed")
        case .chromeClosed: whatsappStatus = .unavailable("Open WhatsApp Web in Chrome")
        case .noTab: whatsappStatus = .unavailable("No WhatsApp Web tab in Chrome")
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
