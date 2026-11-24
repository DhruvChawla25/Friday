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
    private var lastShown = Date.distantPast
    /// Bumped on every show/hide so a stale animation can't finish the wrong way.
    private var generation = 0
    var isVisible: Bool { panel.isVisible && panel.alphaValue > 0.01 }

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
        generation += 1
        let current = generation
        lastShown = .now
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
        // macOS may throttle animations for an app that is not frontmost, so
        // the end state must not depend on the animation completing.
        finish(after: 0.3, generation: current) { panel in
            panel.alphaValue = 1
            panel.setFrame(target, display: true)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        generation += 1
        let current = generation
        lastHidden = .now
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }
        finish(after: 0.2, generation: current) { panel in
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    /// Applies an animation's end state, unless a newer show/hide started since.
    private func finish(
        after delay: TimeInterval, generation expected: Int, _ apply: @escaping (DashboardPanel) -> Void
    ) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == expected else { return }
            apply(self.panel)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // While Friday is still becoming the active app, focus can bounce; ignore that.
        guard Date.now.timeIntervalSince(lastShown) > 0.4 else { return }
        hide()
    }
}
