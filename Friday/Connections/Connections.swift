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

    static let whatsappBundleID = "net.whatsapp.WhatsApp"

    private(set) var whatsappStatus: Status = .notConnected
    private(set) var whatsappUnread: Int?
    private(set) var calendarStatus: Status = .notConnected
    private(set) var calendar: CalendarSource.Summary?

    private let calendarSource = CalendarSource()
    private var timer: Timer?

    var totalUnread: Int { whatsappUnread ?? 0 }

    var isWhatsAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.whatsappBundleID) != nil
    }

    func start() {
        refresh()
        // Badge reads are cheap and local, so poll often for a live feel.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
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

    func openWhatsApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.whatsappBundleID) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func connectCalendar() async {
        _ = await calendarSource.requestAccess()
        refreshCalendar()
    }

    private func refreshWhatsApp() async {
        guard isWhatsAppInstalled else {
            whatsappStatus = .unavailable("WhatsApp is not installed")
            whatsappUnread = nil
            return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.whatsappBundleID).isEmpty
        guard running else {
            whatsappStatus = .unavailable("WhatsApp is closed")
            whatsappUnread = nil
            return
        }
        if let count = await DockBadge.count(forBundleID: Self.whatsappBundleID) {
            whatsappStatus = .connected
            whatsappUnread = count
        } else {
            whatsappStatus = .unavailable("Could not read the Dock badge")
            whatsappUnread = nil
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
