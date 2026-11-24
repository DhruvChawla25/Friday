import AppKit
import EventKit
import Observation

/// Live unread counts and schedule for the dashboard and the orb badge.
@MainActor
@Observable
final class Connections {
    enum Status: Equatable {
        case notConnected
        case denied
        case unavailable(String)
        case connected
    }

    private(set) var chromeStatus: Status = .notConnected
    private(set) var calendarStatus: Status = .notConnected
    private(set) var whatsappUnread: Int?
    private(set) var gmailAccounts: [TabTitleParser.GmailAccount] = []
    private(set) var calendar: CalendarSource.Summary?
    private(set) var lastRefresh: Date?

    private let calendarSource = CalendarSource()
    private var timer: Timer?

    var gmailUnread: Int { gmailAccounts.reduce(0) { $0 + $1.unread } }
    var totalUnread: Int { (whatsappUnread ?? 0) + gmailUnread }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    func refresh() {
        refreshChrome()
        refreshCalendar()
        lastRefresh = .now
    }

    /// Asks macOS for permission to read Chrome tab titles (one-time prompt).
    func connectChrome() async {
        guard ChromeTabs.isRunning else {
            chromeStatus = .unavailable("Open Chrome first")
            return
        }
        _ = await Task.detached { ChromeTabs.access(askIfNeeded: true) }.value
        refreshChrome()
    }

    func connectCalendar() async {
        _ = await calendarSource.requestAccess()
        refreshCalendar()
    }

    private func refreshChrome() {
        switch ChromeTabs.access(askIfNeeded: false) {
        case .granted:
            guard let titles = ChromeTabs.titles() else {
                chromeStatus = .unavailable("Chrome not running")
                return
            }
            chromeStatus = .connected
            whatsappUnread = TabTitleParser.whatsappUnread(in: titles)
            gmailAccounts = TabTitleParser.gmailAccounts(in: titles)
        case .notDetermined:
            chromeStatus = .notConnected
        case .denied:
            chromeStatus = .denied
        case .chromeNotRunning:
            // Keep the last known numbers; Chrome may just be closed.
            if chromeStatus == .connected { chromeStatus = .unavailable("Chrome not running") }
        }
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
