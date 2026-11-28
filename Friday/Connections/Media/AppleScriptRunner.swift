// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Carbon
import Foundation

/// Runs AppleScript (Apple Events to Spotify and Chrome) on one background
/// queue, so a slow or hung app can never freeze Friday's interface.
/// NSAppleScript is not thread-safe, so every script runs on the same queue.
enum AppleScriptRunner {
    struct Failure: Error, Equatable, Sendable {
        var code: Int
        var message: String
        /// macOS refused: the user has not allowed Friday to control this app.
        var isPermissionDenied: Bool { code == -1743 || code == -1744 }
    }

    private static let queue = DispatchQueue(label: "com.dhruvchawla.friday.applescript", qos: .userInitiated)

    /// Runs `source` and returns its result as text.
    static func run(_ source: String) async -> Result<String, Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
                    let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
                    continuation.resume(returning: .failure(Failure(code: code, message: message)))
                } else {
                    continuation.resume(returning: .success(result?.stringValue ?? ""))
                }
            }
        }
    }
}

/// Whether Friday may send Apple Events to an app (System Settings →
/// Privacy & Security → Automation).
enum AppleEventAccess: Equatable, Sendable {
    case granted, notDetermined, denied, notRunning

    /// Asking shows the system prompt once and blocks, so call it off the main actor.
    static func check(bundleID: String, askIfNeeded: Bool) -> AppleEventAccess {
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
        case -1743: return .denied
        case Int(procNotFound): return .notRunning
        default: return .notDetermined
        }
    }
}
