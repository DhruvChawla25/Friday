// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import ImageIO
import Observation
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Takes screenshots and snips and saves them as PNGs on the Desktop.
///
/// Friday hides its own windows first and also excludes itself from the
/// capture filter, so neither the dashboard, the orb nor the snip overlay
/// can appear in the image. Images stay on this Mac.
@MainActor
@Observable
final class ScreenCaptureCoordinator: CapturePerforming {
    static let shared = ScreenCaptureCoordinator()

    /// True after a capture failed for lack of Screen Recording permission.
    private(set) var needsPermission = false
    var copiesToClipboard = true
    private var isCapturing = false

    static let screenRecordingSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(Self.screenRecordingSettings)
    }

    func capture(_ kind: CaptureKind) async -> CaptureOutcome {
        guard !isCapturing else { return .failed("a capture is already in progress.") }
        guard CGPreflightScreenCaptureAccess() else {
            // Adds Friday to the Screen Recording list (and prompts the first time).
            _ = CGRequestScreenCaptureAccess()
            needsPermission = true
            return .permissionNeeded
        }
        needsPermission = false
        isCapturing = true
        defer { isCapturing = false }

        let hidden = HiddenFridayWindows.hide()
        defer { hidden.restore() }
        // Give the window server a moment to take Friday's windows off screen.
        try? await Task.sleep(for: .milliseconds(200))

        let target: CaptureTarget
        switch kind {
        case .screenshot:
            guard let screen = Self.screenUnderPointer() else { return .failed("no display found.") }
            target = CaptureTarget(displayID: screen.displayID, displayFrame: screen.frame, rect: screen.frame)
        case .snip:
            guard let selection = await SnipOverlay().selectRegion() else { return .cancelled }
            target = selection
        }

        let png: Data
        do {
            png = try await ScreenImageGrabber.pngData(for: target)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                needsPermission = true
                return .permissionNeeded
            }
            return .failed(error.localizedDescription)
        }

        let url: URL
        do {
            url = try CaptureFileWriter(directory: Self.desktop).write(png, kind: kind, at: .now)
        } catch {
            return .failed("could not save to the Desktop (\(error.localizedDescription)).")
        }
        let copied = copiesToClipboard && Self.copyToClipboard(png)
        return .saved(fileName: url.lastPathComponent, copiedToClipboard: copied)
    }

    /// The real Desktop (not the sandbox container's), allowed by the
    /// `home-relative-path.read-write` entitlement for `/Desktop/`.
    nonisolated static var desktop: URL {
        AIUsageMonitor.realHome.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    private static func screenUnderPointer() -> NSScreen? {
        let screens = NSScreen.screens
        let index = CaptureGeometry.displayIndex(containing: NSEvent.mouseLocation, in: screens.map(\.frame))
        return index.map { screens[$0] } ?? NSScreen.main
    }

    private static func copyToClipboard(_ png: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }
}

/// One display and the part of it to capture, in AppKit global coordinates.
struct CaptureTarget: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    let displayFrame: CGRect
    let rect: CGRect
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case encodingFailed
    case noFreeFileName

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "that display is no longer connected."
        case .encodingFailed: "could not encode the image as PNG."
        case .noFreeFileName: "too many files with the same name on the Desktop."
        }
    }
}

/// Captures with ScreenCaptureKit, leaving Friday's own windows out.
enum ScreenImageGrabber {
    static func pngData(for target: CaptureTarget) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let friday = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: friday, exceptingWindows: [])

        let local = CaptureGeometry.displayLocalRect(target.rect, displayFrame: target.displayFrame)
        let size = CaptureGeometry.pixelSize(of: local, scale: CGFloat(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let data = PNGEncoder.data(from: image) else { throw CaptureError.encodingFailed }
        return data
    }
}

enum PNGEncoder {
    static func data(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// Writes a capture into `directory` without ever replacing an existing file.
struct CaptureFileWriter: Sendable {
    let directory: URL
    var namer = CaptureFileNamer()
    var maxAttempts = 1000

    func write(_ data: Data, kind: CaptureKind, at date: Date) throws -> URL {
        for index in 1...max(1, maxAttempts) {
            let url = directory.appending(path: namer.fileName(for: kind, at: date, index: index))
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { continue }
            do {
                // Exclusive create: if another file appeared in between, try the next name.
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CaptureError.noFreeFileName
    }
}

/// Friday's visible windows, taken off screen for a capture and put back after.
@MainActor
struct HiddenFridayWindows {
    let windows: [NSWindow]
    let keyWindow: NSWindow?

    static func hide() -> HiddenFridayWindows {
        let visible = NSApp.windows.filter(\.isVisible)
        let hidden = HiddenFridayWindows(windows: visible, keyWindow: NSApp.keyWindow)
        visible.forEach { $0.orderOut(nil) }
        return hidden
    }

    func restore() {
        windows.forEach { $0.orderFrontRegardless() }
        if let keyWindow, windows.contains(keyWindow) {
            NSApp.activate()
            keyWindow.makeKeyAndOrderFront(nil)
        }
    }
}
