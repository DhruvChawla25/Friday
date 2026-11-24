// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct FridayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(memory: appDelegate.assistant.memory, onResetOrb: appDelegate.resetAllOrbPositions)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Friday") { appDelegate.showDashboard() }
                    .keyboardShortcut("o")
            }
        }
    }
}
