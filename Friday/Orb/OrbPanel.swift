// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// Borderless, non-activating window that holds the orb. It never takes
/// focus from the app you are using, appears on every Space, and stays out
/// of full-screen Spaces.
final class OrbPanel: NSPanel {
    static let size = CGSize(width: OrbView.diameter + 12, height: OrbView.diameter + 12)

    let interaction: OrbInteractionView

    init(model: OrbModel) {
        interaction = OrbInteractionView(frame: CGRect(origin: .zero, size: Self.size))
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: OrbView(model: model))
        hosting.frame = interaction.bounds
        hosting.autoresizingMask = [.width, .height]
        interaction.addSubview(hosting)
        contentView = interaction
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Handles click, drag and right-click on the orb.
final class OrbInteractionView: NSView {
    var onClick: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onDragBegan: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private var mouseDownScreenPoint: CGPoint?
    private var windowOriginAtMouseDown: CGPoint?
    private var isDragging = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenPoint = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreenPoint, let origin = windowOriginAtMouseDown, let window else { return }
        let now = NSEvent.mouseLocation
        let delta = CGPoint(x: now.x - start.x, y: now.y - start.y)
        if !isDragging, hypot(delta.x, delta.y) > 4 {
            isDragging = true
            onDragBegan?()
            NSCursor.closedHand.push()
        }
        if isDragging {
            window.setFrameOrigin(CGPoint(x: origin.x + delta.x, y: origin.y + delta.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreenPoint = nil
            isDragging = false
        }
        if isDragging {
            NSCursor.pop()
            if let window { onDragEnded?(window.frame.origin) }
        } else {
            onClick?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
