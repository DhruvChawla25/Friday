// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

/// Where the Screen Recording permission flow stands, for the WhatsApp tile
/// and pop-up. Pure, so it can be tested without touching TCC.
///
/// macOS shows its Screen Recording prompt at most once, and after that
/// `CGRequestScreenCaptureAccess()` silently returns false. Friday is only
/// listed in System Settings once it has actually asked ScreenCaptureKit
/// for content, and `CGPreflightScreenCaptureAccess()` keeps answering false
/// until Friday is reopened, even after the user turns it on.
enum ScreenPermissionFlow {
    enum Stage: Equatable {
        /// Not asked yet in this run.
        case idle
        /// Asked, still off: System Settings was opened for the user.
        case waitingForSettings
        /// ScreenCaptureKit works, but this run still reads as "off":
        /// Friday must be reopened to use it.
        case needsRelaunch
        case granted
    }

    /// - Parameters:
    ///   - preflight: `CGPreflightScreenCaptureAccess()` in this run.
    ///   - captureWorks: whether a ScreenCaptureKit query succeeded, or nil
    ///     when none was tried.
    ///   - asked: whether the user clicked "Allow screen reading" in this run.
    static func stage(preflight: Bool, captureWorks: Bool?, asked: Bool) -> Stage {
        if preflight { return .granted }
        if captureWorks == true { return .needsRelaunch }
        return asked ? .waitingForSettings : .idle
    }

    /// A short line for the tile, or nil to keep the usual caption.
    static func caption(for stage: Stage) -> String? {
        switch stage {
        case .waitingForSettings: "Turn on Friday in Screen Recording, then reopen Friday"
        case .needsRelaunch: "Screen Recording is on: quit and reopen Friday to use it"
        case .idle, .granted: nil
        }
    }
}
