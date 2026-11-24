import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let assistant = Assistant.makeDefault()
    private var panel: FloatingPanel?
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

        // ⌃⌥Space toggles the floating command panel from anywhere.
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            self?.togglePanel()
        }

        // The menu bar icon can be hidden (e.g. behind the notch), so always
        // show the panel on launch to make it obvious Friday is running.
        showPanel()
    }

    /// Opening Friday again (Finder, Spotlight, `open`) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { panel.center() }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> FloatingPanel {
        FloatingPanel(
            rootView: CommandView(assistant: assistant).frame(width: 520, height: 420)
        )
    }

    private func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != current && !$0.isTerminated }
    }
}
