// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import ScreenCaptureKit

/// Captures only WhatsApp's own window (never the whole screen) and reads
/// its chat list with `WhatsAppChatListAnalyzer`. The capture lives in memory
/// for well under a second and is never saved.
@MainActor
enum WhatsAppScreenReader {
    static let bundleID = "net.whatsapp.WhatsApp"

    enum Failure: Error, Equatable {
        case noPermission
        case notRunning
        case noWindow
        case captureFailed
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (first time) or returns the current state.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Reads the chat list.
    /// - Parameter bringToFront: open/show WhatsApp if its window is closed or
    ///   hidden. When false (background rechecks), only an already-visible
    ///   window is read and nothing on screen changes.
    /// - Parameter staysInFront: keep WhatsApp in front afterwards (the user
    ///   asked to open it); otherwise return focus to the previous app.
    static func read(
        bringToFront: Bool, staysInFront: Bool = false, readsNames: Bool
    ) async -> Result<WhatsAppChatListAnalyzer.Report, Failure> {
        guard hasPermission else { return .failure(.noPermission) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure(.notRunning)
        }
        let previous = NSWorkspace.shared.frontmostApplication
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        if !isRunning && !bringToFront { return .failure(.notRunning) }

        var window = try? await mainWindow()
        if window == nil, bringToFront {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            // Wait (up to ~5 s) for the window to appear and draw its chat list.
            for _ in 0..<25 where window == nil {
                try? await Task.sleep(for: .milliseconds(200))
                window = try? await mainWindow()
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        guard let window else { return .failure(.noWindow) }

        defer {
            if bringToFront, !staysInFront, let previous, previous.bundleIdentifier != bundleID {
                previous.activate()
            }
        }
        guard let (image, scale) = try? await capture(window) else { return .failure(.captureFailed) }
        let analyzer = WhatsAppChatListAnalyzer(scale: scale, readsNames: readsNames)
        let report = await Task.detached(priority: .userInitiated) { analyzer.analyze(image) }.value
        return .success(report)
    }

    /// WhatsApp's main window, if it is open and on screen.
    private static func mainWindow() async throws -> SCWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows
            .filter {
                $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0
                    && $0.frame.width >= 500 && $0.frame.height >= 400
            }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func capture(_ window: SCWindow) async throws -> (CGImage, CGFloat) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, scale)
    }
}
