import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let assistant = Assistant.makeDefault()
    private var panel: FloatingPanel?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌃⌥Space toggles the floating command panel from anywhere.
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            self?.togglePanel()
        }
    }

    func togglePanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.center()
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func makePanel() -> FloatingPanel {
        FloatingPanel(
            rootView: CommandView(assistant: assistant).frame(width: 520, height: 420)
        )
    }
}
