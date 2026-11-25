// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let assistant = Assistant.makeDefault()
    let connections = Connections()
    let aiUsage = AIUsageMonitor()
    private var orb: OrbController?
    private var dashboard: DashboardController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When hosting unit tests, do nothing visible.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // Only one Friday may run: a second copy hands over to the first and quits.
        if let existing = otherRunningInstance() {
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        let dashboard = DashboardController(
            rootView: DashboardView(assistant: assistant, connections: connections, aiUsage: aiUsage)
                .frame(width: DashboardPanel.size.width, height: DashboardPanel.size.height)
        )
        self.dashboard = dashboard

        let orb = OrbController()
        orb.onClick = { [weak self] in self?.toggleDashboard() }
        orb.menuProvider = { [weak self] in self?.orbMenu() ?? NSMenu() }
        orb.start()
        self.orb = orb

        connections.start()
        aiUsage.start { [weak dashboard] in dashboard?.isVisible ?? false }
        observeUnreadCount()

        // ⌃⌥Space toggles the dashboard from anywhere.
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            self?.toggleDashboard()
        }
    }

    /// Clicking the Dock icon (or opening Friday again) opens the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Friday", action: #selector(showDashboardAction), keyEquivalent: "")
        menu.addItem(withTitle: "Reset Orb Positions", action: #selector(resetOrbAction), keyEquivalent: "")
        return menu
    }

    func toggleDashboard() {
        connections.refresh()
        if dashboard?.isVisible == false { aiUsage.refresh() }
        dashboard?.toggle(from: orb?.frame)
    }

    func showDashboard() {
        connections.refresh()
        aiUsage.refresh()
        dashboard?.show(from: orb?.frame)
    }

    func resetAllOrbPositions() {
        orb?.resetAllPositions()
    }

    @objc private func showDashboardAction() { showDashboard() }
    @objc private func resetOrbAction() { resetAllOrbPositions() }
    @objc private func resetOrbForAppAction() { orb?.resetPositionForCurrentApp() }
    @objc private func refreshAction() { connections.refresh() }
    @objc private func settingsAction() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func orbMenu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            ("Open Friday", #selector(showDashboardAction)),
            ("Refresh Counts", #selector(refreshAction)),
            ("Reset Position for This App", #selector(resetOrbForAppAction)),
            ("Settings…", #selector(settingsAction)),
        ]
        for (title, action) in items {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Friday", action: #selector(quitAction), keyEquivalent: "").target = self
        return menu
    }

    /// Keeps the orb badge and Dock badge in sync with the unread total.
    private func observeUnreadCount() {
        withObservationTracking {
            let total = connections.totalUnread
            orb?.model.unread = total
            NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeUnreadCount() }
        }
    }

    private func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != current && !$0.isTerminated }
    }
}
