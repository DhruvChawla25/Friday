import AppKit
import Carbon

/// Reads tab titles from Google Chrome via Apple Events.
/// Friday never launches Chrome and never reads page contents, only titles.
@MainActor
enum ChromeTabs {
    nonisolated static let bundleID = "com.google.Chrome"

    enum Access: Equatable {
        case granted, notDetermined, denied, chromeNotRunning
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Checks (and optionally asks for) permission to talk to Chrome.
    /// Asking shows the system prompt once; it blocks, so call it off the main actor.
    nonisolated static func access(askIfNeeded: Bool) -> Access {
        var address = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { pointer in
            guard AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &address) == noErr else {
                return OSStatus(procNotFound)
            }
            defer { AEDisposeDesc(&address) }
            return AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, askIfNeeded)
        }
        switch Int(status) {
        case Int(noErr): return .granted
        case -1744: return .notDetermined  // errAEEventWouldRequireUserConsent
        case -1743: return .denied  // errAEEventNotPermitted
        default: return .chromeNotRunning
        }
    }

    /// Titles of every tab in every Chrome window, or nil if unavailable.
    static func titles() -> [String]? {
        guard isRunning else { return nil }
        let script = NSAppleScript(
            source: "tell application id \"\(bundleID)\" to get title of every tab of every window")
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error), error == nil else { return nil }
        var titles: [String] = []
        for windowIndex in stride(from: 1, through: result.numberOfItems, by: 1) {
            guard let window = result.atIndex(windowIndex) else { continue }
            for tabIndex in stride(from: 1, through: window.numberOfItems, by: 1) {
                if let title = window.atIndex(tabIndex)?.stringValue { titles.append(title) }
            }
        }
        return titles
    }
}
