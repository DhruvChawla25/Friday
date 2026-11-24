// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit

/// A snapshot of what is on screen: which screen the cursor is on, the
/// frontmost app and its window frame, and which screens are full screen.
/// Uses window *frames* only (CGWindowList bounds), never window contents.
@MainActor
struct ScreenEnvironment {
    let cursorScreen: NSScreen
    let frontAppID: String?
    let frontWindow: CGRect?
    let isDesktop: Bool
    let fullScreenScreens: Set<CGDirectDisplayID>
    /// Frames of all normal app windows (AppKit coordinates).
    let windowFrames: [CGRect]

    /// True when no app window covers the desktop icon column on `screen`,
    /// i.e. desktop icons there are visible and should not be covered.
    func desktopIconsVisible(on screen: NSScreen) -> Bool {
        let visible = screen.visibleFrame
        let column = CGRect(
            x: visible.maxX - OrbPlacement.desktopIconColumn, y: visible.maxY - 200,
            width: OrbPlacement.desktopIconColumn, height: 200
        )
        return !windowFrames.contains { $0.contains(column) }
    }

    /// `front` is the app the user is working in (Friday itself is never passed).
    static func capture(front: NSRunningApplication?, excludingPID ownPID: pid_t) -> ScreenEnvironment? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let mouse = NSEvent.mouseLocation
        let cursorScreen = screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? primary

        let frontPID = front?.processIdentifier
        let windows = windowList(primaryHeight: primary.frame.height).filter { $0.pid != ownPID }

        let frontWindow = windows.first { $0.pid == frontPID }?.frame
        let isDesktop = front?.bundleIdentifier == "com.apple.finder" && frontWindow == nil

        var fullScreen: Set<CGDirectDisplayID> = []
        for screen in screens {
            let frame = screen.frame
            if windows.contains(where: {
                abs($0.frame.width - frame.width) < 2 && abs($0.frame.height - frame.height) < 2
                    && frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }) {
                fullScreen.insert(screen.displayID)
            }
        }
        return ScreenEnvironment(
            cursorScreen: cursorScreen,
            frontAppID: isDesktop ? OrbPositionStore.desktopKey : front?.bundleIdentifier,
            frontWindow: frontWindow,
            isDesktop: isDesktop,
            fullScreenScreens: fullScreen,
            windowFrames: windows.map(\.frame)
        )
    }

    private struct WindowInfo {
        let pid: pid_t
        let frame: CGRect  // AppKit coordinates
    }

    /// Normal-level, on-screen windows, front to back.
    private static func windowList(primaryHeight: CGFloat) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.width > 80, bounds.height > 80
            else { return nil }
            // CoreGraphics uses a top-left origin; convert to AppKit's bottom-left.
            let frame = CGRect(
                x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return WindowInfo(pid: pid, frame: frame)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
