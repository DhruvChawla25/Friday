// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// What happened after a capture request.
enum CaptureOutcome: Sendable, Equatable {
    /// Saved to the Desktop under `fileName`.
    case saved(fileName: String, copiedToClipboard: Bool)
    /// The user pressed Esc during a snip.
    case cancelled
    /// macOS has not given Friday Screen Recording permission.
    case permissionNeeded
    case failed(String)
}

protocol CapturePerforming: Sendable {
    @MainActor func capture(_ kind: CaptureKind) async -> CaptureOutcome
}

/// "screenshot", "ss", "snip", "snipping tool", "capture area".
/// Saves a PNG to the Desktop. Nothing leaves the Mac.
struct CaptureSkill: Skill {
    let name = "Screenshot"
    let example = "screenshot  ·  snip"

    let capturer: any CapturePerforming

    func canHandle(_ command: Command) -> Bool {
        CaptureCommandParser.parse(command) != nil
    }

    func handle(_ command: Command) async -> String {
        guard let kind = CaptureCommandParser.parse(command) else { return Persona.captureWhat }
        return Persona.capture(await capturer.capture(kind))
    }
}

extension Persona {
    static let captureWhat = "Say \"screenshot\" for the whole screen or \"snip\" to select an area."
    static let captureCancelled = "Snip cancelled. Nothing saved."
    static let capturePermission =
        "Friday needs Screen Recording permission. Open System Settings → Privacy & Security → "
        + "Screen & System Audio Recording, turn on Friday, then try again. "
        + "Use the \"Allow\" button next to the capture buttons to open that pane."

    static func capture(_ outcome: CaptureOutcome) -> String {
        switch outcome {
        case .saved(let fileName, let copied):
            "Saved \(fileName) to Desktop." + (copied ? " Also copied to the clipboard." : "")
        case .cancelled: captureCancelled
        case .permissionNeeded: capturePermission
        case .failed(let reason): "Could not capture the screen: \(reason)"
        }
    }
}
