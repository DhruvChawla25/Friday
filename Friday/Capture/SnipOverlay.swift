// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit

/// A dimmed, crosshair overlay on every display. The user drags out a
/// rectangle; Esc (or switching away) cancels. The overlay only draws: the
/// pixels come from ScreenCaptureKit afterwards, with Friday excluded.
@MainActor
final class SnipOverlay {
    private var windows: [SnipOverlayWindow] = []
    private var continuation: CheckedContinuation<CaptureTarget?, Never>?
    private var resignObserver: NSObjectProtocol?
    private var cursorPushed = false

    /// Where the drag started and the screen it started on.
    private var anchor: (point: CGPoint, screen: NSScreen)?
    private var selection: CGRect = .zero

    func selectRegion() async -> CaptureTarget? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    private func present() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return finish(with: nil) }
        windows = screens.map { screen in
            let window = SnipOverlayWindow(screen: screen)
            let view = SnipOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.handler = self
            window.contentView = view
            return window
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyIndex = CaptureGeometry.displayIndex(containing: mouse, in: screens.map(\.frame)) ?? 0
        for (index, window) in windows.enumerated() {
            if index == keyIndex { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
        }
        NSCursor.crosshair.push()
        cursorPushed = true
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(with: nil) }
        }
    }

    private func finish(with target: CaptureTarget?) {
        guard let continuation else { return }
        self.continuation = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if cursorPushed { NSCursor.pop() }
        cursorPushed = false
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        continuation.resume(returning: target)
    }

    // MARK: - Events from the views (global AppKit coordinates)

    fileprivate func began(at point: CGPoint) {
        let screens = NSScreen.screens
        guard let index = CaptureGeometry.displayIndex(containing: point, in: screens.map(\.frame)) else { return }
        anchor = (point, screens[index])
        selection = .zero
        redraw()
    }

    fileprivate func dragged(to point: CGPoint) {
        guard let anchor else { return }
        selection = CaptureGeometry.selection(
            from: anchor.point, to: point, within: anchor.screen.frame, scale: anchor.screen.backingScaleFactor)
        redraw()
    }

    fileprivate func ended(at point: CGPoint) {
        dragged(to: point)
        guard let anchor, CaptureGeometry.isUsableSelection(selection) else {
            // A click without a drag: keep the overlay up for another try.
            self.anchor = nil
            selection = .zero
            redraw()
            return
        }
        finish(
            with: CaptureTarget(displayID: anchor.screen.displayID, displayFrame: anchor.screen.frame, rect: selection))
    }

    fileprivate func cancel() { finish(with: nil) }

    fileprivate var currentSelection: CGRect { selection }

    private func redraw() { windows.forEach { $0.contentView?.needsDisplay = true } }
}

private final class SnipOverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

private final class SnipOverlayView: NSView {
    weak var handler: SnipOverlay?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            handler?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { handler?.cancel() }
    override func rightMouseDown(with event: NSEvent) { handler?.cancel() }

    override func mouseDown(with event: NSEvent) { handler?.began(at: globalPoint(event)) }
    override func mouseDragged(with event: NSEvent) { handler?.dragged(to: globalPoint(event)) }
    override func mouseUp(with event: NSEvent) { handler?.ended(at: globalPoint(event)) }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, let handler else { return }
        // The selection in this view's coordinates (empty on other displays).
        let global = handler.currentSelection
        let local = global.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY).intersection(bounds)

        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard !local.isNull, local.width > 0, local.height > 0 else { return }

        NSColor.clear.setFill()
        local.fill(using: .copy)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let size = CaptureGeometry.pixelSize(of: local, scale: window.backingScaleFactor)
        let label = "\(size.width) × \(size.height)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attributes)
        var origin = CGPoint(x: local.maxX - textSize.width - 6, y: local.minY - textSize.height - 6)
        if origin.y < bounds.minY { origin.y = local.minY + 6 }
        origin.x = max(bounds.minX + 4, origin.x)
        let pill = CGRect(origin: origin, size: textSize).insetBy(dx: -5, dy: -2)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        label.draw(at: origin, withAttributes: attributes)
    }
}
