import SwiftUI

@main
struct FridayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Friday", systemImage: "circle.hexagongrid.fill") {
            CommandView(assistant: appDelegate.assistant)
                .frame(width: 400, height: 460)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(memory: appDelegate.assistant.memory)
        }
    }
}
