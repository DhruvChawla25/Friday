import AppKit

/// Owns the orb window and keeps it in the right place:
/// - on the screen with the cursor (like Wispr Flow),
/// - where the user last dragged it for the frontmost app,
/// - otherwise in the first corner/edge that avoids toolbars and desktop icons,
/// - moved to another screen, or hidden, when the screen is full screen.
@MainActor
final class OrbController {
    let model = OrbModel()
    private let panel: OrbPanel
    private let store: OrbPositionStore
    private var timer: Timer?
    private var isDragging = false
    private var currentAppKey: String?
    private var currentVisible: CGRect = .zero
    /// The last app the user was working in (never Friday itself).
    private var lastExternalApp: NSRunningApplication?

    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    init(store: OrbPositionStore = OrbPositionStore()) {
        self.store = store
        panel = OrbPanel(model: model)
        panel.interaction.onClick = { [weak self] in self?.onClick?() }
        panel.interaction.onDragBegan = { [weak self] in self?.isDragging = true }
        panel.interaction.onDragEnded = { [weak self] origin in self?.dragEnded(at: origin) }
        panel.interaction.menuProvider = { [weak self] in self?.menuProvider?() ?? NSMenu() }
    }

    var frame: CGRect { panel.frame }

    func start() {
        update(animated: false)
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { self.update(animated: true) }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.update(animated: true) }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.update(animated: false) }
        }
    }

    func resetPositionForCurrentApp() {
        if let key = currentAppKey { store.reset(key) }
        update(animated: true)
    }

    func resetAllPositions() {
        store.resetAll()
        update(animated: true)
    }

    // MARK: - Placement

    private func update(animated: Bool) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.processIdentifier != ownPID { lastExternalApp = frontmost }
        // While Friday is in front (dashboard open), keep an already-placed orb still.
        if frontmost?.processIdentifier == ownPID, panel.isVisible { return }
        guard !isDragging,
            let environment = ScreenEnvironment.capture(front: lastExternalApp, excludingPID: ownPID)
        else { return }

        // Pick the cursor's screen unless it is full screen; then any other screen.
        let screens = NSScreen.screens
        let candidates = [environment.cursorScreen] + screens.filter { $0 != environment.cursorScreen }
        guard let screen = candidates.first(where: { !environment.fullScreenScreens.contains($0.displayID) }) else {
            setHidden(true)
            return
        }
        setHidden(false)

        let visible = screen.visibleFrame
        let size = OrbPanel.size
        currentAppKey = environment.frontAppID
        currentVisible = visible

        let origin: CGPoint
        if let key = environment.frontAppID, let saved = store.position(for: key) {
            origin = OrbPlacement.absolute(saved, visible: visible, size: size)
        } else {
            let busy = OrbPlacement.busyZones(
                windows: environment.windowFrames.filter { $0.intersects(screen.frame) },
                isDesktop: environment.desktopIconsVisible(on: screen),
                visible: visible
            )
            origin = OrbPlacement.automaticOrigin(visible: visible, size: size, busy: busy)
        }
        move(to: origin, animated: animated)
    }

    private func move(to origin: CGPoint, animated: Bool) {
        let current = panel.frame.origin
        guard hypot(current.x - origin.x, current.y - origin.y) > 1 else { return }
        // Jumping between screens should not glide across the gap.
        let sameScreen =
            NSScreen.screens.first { $0.frame.contains(current) }
            == NSScreen.screens.first { $0.frame.contains(origin) }
        if animated && sameScreen {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrameOrigin(origin)
            }
        } else {
            panel.setFrameOrigin(origin)
        }
    }

    private func setHidden(_ hidden: Bool) {
        guard model.isHidden != hidden else { return }
        model.isHidden = hidden
        panel.ignoresMouseEvents = hidden
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = hidden ? 0 : 1
        }
    }

    private func dragEnded(at origin: CGPoint) {
        isDragging = false
        let screen =
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: origin.x + 10, y: origin.y + 10)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let snapped = OrbPlacement.snapped(origin, visible: visible, size: OrbPanel.size)
        move(to: snapped, animated: true)
        if let key = currentAppKey {
            store.save(OrbPlacement.relative(snapped, visible: visible, size: OrbPanel.size), for: key)
        }
    }
}
