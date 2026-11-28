// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import Observation

/// What is playing in Spotify and in YouTube / YouTube Music tabs in Chrome,
/// asked locally over Apple Events. No internet, no AI. Titles live in
/// memory only and are shown in the dashboard; they are never saved or logged.
///
/// Friday never launches Spotify or Chrome, and never asks for permission on
/// its own: the "Connect" buttons do that.
@MainActor
@Observable
final class MediaCenter {
    private(set) var items: [MediaItem] = []
    private(set) var access: [MediaApp: AppleEventAccess] = [:]
    /// Chrome's "Allow JavaScript from Apple Events" is off, so YouTube tabs
    /// show their title only, without play state or controls.
    private(set) var chromeJavaScriptBlocked = false

    @ObservationIgnored private var spotifyItem: MediaItem?
    @ObservationIgnored private var chromeItems: [MediaItem] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isVisible: () -> Bool = { false }
    @ObservationIgnored private var isRefreshing = false

    func isInstalled(_ app: MediaApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    func isRunning(_ app: MediaApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Polls every 3 s while the dashboard is open; Spotify's own
    /// "playback changed" broadcast refreshes it at once.
    func start(isVisible: @escaping () -> Bool) {
        self.isVisible = isVisible
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                if self.isVisible() { self.refresh() }
            }
        }
        timer?.tolerance = 0.5
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.refresh() }
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            await refreshSpotify()
            await refreshChrome()
            items = MediaScripts.sorted([spotifyItem].compactMap(\.self) + chromeItems)
        }
    }

    /// Shows macOS's "Friday wants to control …" prompt once.
    func connect(_ app: MediaApp) async {
        let bundleID = app.bundleID
        let result = await Task.detached { AppleEventAccess.check(bundleID: bundleID, askIfNeeded: true) }.value
        access[app] = result
        if result == .denied { openAutomationSettings() }
        refresh()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func send(_ control: MediaItem.Control, to item: MediaItem) async {
        let script: String?
        switch item.source {
        case .spotify:
            script = MediaScripts.spotify(control)
        case .youtube, .youtubeMusic:
            guard let window = item.chromeWindowID, let tab = item.chromeTabID else { return }
            script = MediaScripts.chrome(control, window: window, tab: tab)
        }
        guard let script else { return }
        _ = await AppleScriptRunner.run(script)
        try? await Task.sleep(for: .milliseconds(300))
        refresh()
    }

    /// For voice/typed commands: acts on what is playing, else the first item.
    func send(_ control: MediaItem.Control) async -> String {
        await refreshNow()
        guard let item = items.first(where: { $0.state == .playing }) ?? items.first else {
            return "Nothing is playing in Spotify or YouTube."
        }
        guard item.controls.contains(control) else {
            return "\(item.source.label) controls need Chrome's Allow JavaScript from Apple Events."
        }
        await send(control, to: item)
        switch control {
        case .playPause:
            return item.state == .playing ? "Paused \(item.source.label)." : "Playing \(item.source.label)."
        case .next: return "Next on \(item.source.label)."
        case .previous: return "Previous on \(item.source.label)."
        case .reveal: return "Showing \(item.source.label)."
        }
    }

    func describeNowPlaying() async -> String {
        await refreshNow()
        guard !items.isEmpty else { return "Nothing is playing in Spotify or YouTube." }
        return Self.describe(items)
    }

    static func describe(_ items: [MediaItem]) -> String {
        let lines = items.prefix(3).map { item -> String in
            let state = item.state == .playing ? "Playing" : item.state == .paused ? "Paused" : "Open"
            let what = item.subtitle.map { "\(item.title) by \($0)" } ?? item.title
            return "\(state) on \(item.source.label): \(what)."
        }
        let more = items.count > 3 ? " +\(items.count - 3) more." : ""
        return lines.joined(separator: " ") + more
    }

    private func refreshNow() async {
        await refreshSpotify()
        await refreshChrome()
        items = MediaScripts.sorted([spotifyItem].compactMap(\.self) + chromeItems)
    }

    private func currentAccess(_ app: MediaApp) async -> AppleEventAccess {
        guard isRunning(app) else { return .notRunning }
        let bundleID = app.bundleID
        return await Task.detached { AppleEventAccess.check(bundleID: bundleID, askIfNeeded: false) }.value
    }

    private func refreshSpotify() async {
        let state = await currentAccess(.spotify)
        access[.spotify] = state
        guard state == .granted else {
            spotifyItem = nil
            return
        }
        switch await AppleScriptRunner.run(MediaScripts.spotifyRead) {
        case .success(let text): spotifyItem = MediaScripts.parseSpotify(text)
        case .failure(let failure):
            if failure.isPermissionDenied { access[.spotify] = .denied }
            spotifyItem = nil
        }
    }

    private func refreshChrome() async {
        let state = await currentAccess(.chrome)
        access[.chrome] = state
        guard state == .granted else {
            chromeItems = []
            return
        }
        switch await AppleScriptRunner.run(MediaScripts.chromeRead) {
        case .success(let text):
            let reading = MediaScripts.parseChrome(text)
            chromeItems = reading.items
            chromeJavaScriptBlocked = reading.javaScriptBlocked
        case .failure(let failure):
            if failure.isPermissionDenied { access[.chrome] = .denied }
            chromeItems = []
        }
    }
}
