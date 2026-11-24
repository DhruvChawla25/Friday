// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// The expanded Friday window, centred on the active screen.
final class DashboardPanel: NSPanel {
    static let size = CGSize(width: 660, height: 480)
    var onDismiss: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = true

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" || event.charactersIgnoringModifiers == "m" {
            onDismiss?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Shows and hides the dashboard with a short "expand from the orb" animation.
@MainActor
final class DashboardController: NSObject, NSWindowDelegate {
    private let panel: DashboardPanel
    private var lastHidden = Date.distantPast
    var isVisible: Bool { panel.isVisible }

    init<Content: View>(rootView: Content) {
        panel = DashboardPanel(rootView: rootView)
        super.init()
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.hide() }
    }

    /// `from` is the orb frame, used as the animation origin.
    func toggle(from origin: CGRect?) {
        // A click on the orb also makes the dashboard resign key; ignore that bounce.
        if Date.now.timeIntervalSince(lastHidden) < 0.25 { return }
        isVisible ? hide() : show(from: origin)
    }

    func show(from origin: CGRect?) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = DashboardPanel.size
        let target = CGRect(
            x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 40, width: size.width,
            height: size.height)

        // Start slightly offset towards the orb, then glide into place.
        var start = target
        if let origin {
            start.origin.x += (origin.midX - target.midX) * 0.08
            start.origin.y += (origin.midY - target.midY) * 0.08
        }
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        lastHidden = .now
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
