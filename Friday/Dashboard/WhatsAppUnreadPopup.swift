// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import Observation
import SwiftUI

/// Loads the list shown in the WhatsApp pop-up, choosing the best source:
/// 1. Accessibility (every unread chat, with times) when Friday may use it;
/// 2. the screen reader (chats visible in WhatsApp's window);
/// 3. WhatsApp Web's tab title (a total only).
/// Nothing here brings WhatsApp forward or switches Spaces.
@MainActor
@Observable
final class WhatsAppUnreadLoader {
    enum Notice: Equatable {
        /// The sandbox blocks Accessibility, so only visible chats are listed.
        case sandboxed
        case needsAccessibility
        case needsScreenPermission
        case noWindow
        case notRunning
        case notInstalled
        case unreadable
    }

    enum Phase: Equatable {
        case idle
        case loading(fullScan: Bool)
        case loaded
        case failed
    }

    private(set) var phase = Phase.idle
    /// A partial reading (loaded/visible rows only), used until a full scan exists.
    private(set) var partial: WhatsAppUnreadList?
    private(set) var notice: Notice?
    /// Accessibility works, so "Scan all chats" can be offered.
    private(set) var canScanAll = false

    let connections: Connections

    init(connections: Connections) {
        self.connections = connections
    }

    var showsNames: Bool { connections.showsNames }

    /// The full scan (kept current by notifications) if there is one, else
    /// the latest partial reading. Names are stripped when they are off.
    var list: WhatsAppUnreadList? {
        let list = connections.whatsappList.list ?? partial
        return showsNames ? list : list?.withoutNames()
    }

    var isStale: Bool { connections.whatsappList.list != nil && connections.whatsappList.isStale }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// Runs when the pop-up opens. Never changes what is on screen: with a
    /// full scan already made it only checks whether scanning is possible.
    func load() async {
        guard !isLoading else { return }
        phase = .loading(fullScan: false)
        let webTotal = connections.whatsappWebUnread

        guard connections.isWhatsAppInstalled else {
            partial = webTotal.map { WhatsAppUnreadList(chats: [], source: .screen, reportedTotal: $0) }
            finish(notice: .notInstalled)
            return
        }

        switch await WhatsAppAccessibilityReader.read(fullScan: false, readsNames: showsNames) {
        case .success(let result):
            canScanAll = true
            partial = result
            if result.source == .accessibilityFull, connections.whatsappList.list == nil {
                connections.applyWhatsAppScan(result)
            }
            finish(notice: nil)
            return
        case .failure(let failure):
            canScanAll = failure == .noWindow && !WhatsAppAccessibilityReader.isSandboxed
            notice = Self.notice(for: failure)
        }
        guard connections.whatsappList.list == nil else {
            finish(notice: notice)
            return
        }

        // Fall back to the visible rows in WhatsApp's window.
        guard connections.screenPermission else {
            partial = webTotal.map { WhatsAppUnreadList(chats: [], source: .screen, reportedTotal: $0) }
            finish(notice: notice == .sandboxed ? .needsScreenPermission : notice)
            return
        }
        switch await connections.readWhatsAppScreen(bringToFront: false) {
        case .success(let report):
            partial = WhatsAppUnreadList(screen: report, reportedTotal: webTotal)
            finish(notice: notice)
        case .failure(let failure):
            if let report = connections.freshScreenReport {
                partial = WhatsAppUnreadList(screen: report, reportedTotal: webTotal)
            } else {
                partial = webTotal.map { WhatsAppUnreadList(chats: [], source: .screen, reportedTotal: $0) }
            }
            finish(notice: failure == .notRunning ? .notRunning : (notice == .sandboxed ? .noWindow : notice))
        }
    }

    /// The one full scan, run only when the user clicks "Scan all chats".
    /// WhatsApp's list switches to its Unread filter and scrolls while it runs,
    /// then goes back; WhatsApp is not brought forward.
    func scanAll() async {
        guard !isLoading else { return }
        phase = .loading(fullScan: true)
        switch await WhatsAppAccessibilityReader.read(fullScan: true, readsNames: showsNames) {
        case .success(let result):
            connections.applyWhatsAppScan(result)
            finish(notice: nil)
        case .failure(let failure):
            finish(notice: Self.notice(for: failure))
        }
    }

    private func finish(notice: Notice?) {
        self.notice = notice
        phase = list == nil ? .failed : .loaded
    }

    nonisolated static func notice(for failure: WhatsAppAccessibilityReader.Failure) -> Notice {
        switch failure {
        case .sandboxed: .sandboxed
        case .notTrusted: .needsAccessibility
        case .notRunning: .notRunning
        case .noWindow: .noWindow
        case .unreadable: .unreadable
        }
    }
}

/// The floating pop-up panel. Closes with Esc, ⌘W, or a click elsewhere.
final class WhatsAppUnreadPanel: NSPanel {
    static let size = CGSize(width: 400, height: 500)
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

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func resignKey() {
        super.resignKey()
        onDismiss?()  // a click outside the pop-up
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            onDismiss?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class WhatsAppUnreadPopup {
    static let shared = WhatsAppUnreadPopup()

    private var panel: WhatsAppUnreadPanel?
    private var loader: WhatsAppUnreadLoader?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(connections: Connections, near anchor: NSWindow? = NSApp.keyWindow) {
        let loader = self.loader ?? WhatsAppUnreadLoader(connections: connections)
        self.loader = loader
        let panel =
            self.panel
            ?? WhatsAppUnreadPanel(
                rootView: WhatsAppUnreadView(loader: loader, onClose: { [weak self] in self?.hide() })
                    .frame(width: WhatsAppUnreadPanel.size.width, height: WhatsAppUnreadPanel.size.height))
        panel.onDismiss = { [weak self] in self?.hide() }
        self.panel = panel

        let size = WhatsAppUnreadPanel.size
        if let frame = anchor?.frame {
            // Overlap the dashboard's right side, like a sheet sliding out of it.
            let screen = anchor?.screen?.visibleFrame ?? frame
            let x = min(frame.maxX - size.width * 0.6, screen.maxX - size.width - 12)
            panel.setFrame(
                CGRect(
                    x: max(screen.minX + 12, x), y: frame.midY - size.height / 2, width: size.width, height: size.height
                ),
                display: false)
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(
                CGRect(
                    x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width,
                    height: size.height),
                display: false)
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        Task { await loader.load() }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.onDismiss = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}

struct WhatsAppUnreadView: View {
    let loader: WhatsAppUnreadLoader
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content
            if let notice = loader.notice, loader.phase != .idle {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                NoticeBar(notice: notice, loader: loader)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.orange.opacity(0.5), Theme.hairline], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "WhatsApp · Unread")
                Text(loader.list?.headline ?? (loader.isLoading ? "Reading WhatsApp…" : "Unread chats"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.amber)
                    .contentTransition(.numericText())
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if loader.canScanAll {
                Button(loader.connections.whatsappList.list == nil ? "Scan all chats" : "Scan again") {
                    Task { await loader.scanAll() }
                }
                .buttonStyle(ConnectButtonStyle())
                .disabled(loader.isLoading)
                .help("Reads every unread chat once. WhatsApp's list scrolls while Friday reads it.")
            }
            Button {
                Task { await loader.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .disabled(loader.isLoading)
            .help("Read again")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private var subtitle: String? {
        guard let list = loader.list else { return nil }
        var parts: [String] = []
        if list.isPartial, !list.chats.isEmpty {
            parts.append("Showing \(list.chats.count) visible in WhatsApp")
        }
        if loader.isStale { parts.append("May be out of date: scan again") }
        if let date = loader.connections.whatsappList.scannedAt, !loader.isStale {
            parts.append("Scanned \(date.formatted(date: .omitted, time: .shortened)), updated by notifications")
        }
        if !loader.showsNames { parts.append("Names hidden in Settings") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        if case .loading(let fullScan) = loader.phase, loader.list == nil || fullScan {
            VStack(spacing: Theme.Space.m) {
                ProgressView().controlSize(.small).tint(Theme.orange)
                Text(fullScan ? "Reading every unread chat…" : "Reading WhatsApp…")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                if fullScan {
                    Text("WhatsApp's list scrolls while Friday reads it.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let list = loader.list, !list.chats.isEmpty {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(list.chats.enumerated()), id: \.element.id) { index, chat in
                        ChatRow(chat: chat, index: index)
                    }
                }
                .padding(Theme.Space.s)
            }
            .scrollIndicators(.automatic)
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: loader.list?.unreadChats == 0 ? "checkmark.circle" : "tray")
                    .font(.system(size: 26)).foregroundStyle(Theme.orange.opacity(0.8))
                Text(emptyText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyText: String {
        if loader.list?.unreadChats == 0 { return "All caught up." }
        if let total = loader.list?.reportedTotal, total > 0 {
            return "WhatsApp reports \(total) unread chats,\nbut Friday can't list them yet."
        }
        return "Nothing to show yet."
    }
}

private struct ChatRow: View {
    let chat: WhatsAppUnreadList.Chat
    let index: Int
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.orange.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.orange.opacity(0.12)))
                .help(kindLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.name ?? placeholder)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(chat.name == nil ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(kindLabel)
                    if chat.mentioned { Text("@ mentioned").foregroundStyle(Theme.amber) }
                    if chat.muted { Image(systemName: "bell.slash.fill") }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 4) {
                Text(chat.lastMessage.map { WhatsAppTimeParser.label(for: $0) } ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(chat.count > 999 ? "999+" : String(chat.count))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(chat.muted ? Theme.textSecondary : Theme.orange))
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0.025))
        )
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private var placeholder: String {
        switch chat.kind {
        case .group, .community: "Group chat \(index + 1)"
        case .person, .unknown: "Chat \(index + 1)"
        }
    }

    private var icon: String {
        switch chat.kind {
        case .person: "person.fill"
        case .group: "person.3.fill"
        case .community: "person.3.sequence.fill"
        case .unknown: "bubble.left.fill"
        }
    }

    private var kindLabel: String {
        switch chat.kind {
        case .person: "Person"
        case .group: "Group"
        case .community: "Community group"
        case .unknown: "Chat"
        }
    }
}

private struct NoticeBar: View {
    let notice: WhatsAppUnreadLoader.Notice
    let loader: WhatsAppUnreadLoader

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "info.circle").foregroundStyle(Theme.orange)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.perform).buttonStyle(ConnectButtonStyle())
            }
        }
        .padding(Theme.Space.m)
    }

    private var text: String {
        switch notice {
        case .sandboxed:
            "Only chats visible in WhatsApp's window are listed. Reading every unread chat needs the Accessibility "
                + "API, which Friday's App Sandbox blocks (GitHub issue #6)."
        case .needsAccessibility:
            "Allow Friday in System Settings → Privacy & Security → Accessibility to list every unread chat."
        case .needsScreenPermission:
            "Allow screen reading so Friday can list the chats visible in WhatsApp's window."
        case .noWindow:
            "Open WhatsApp's window on this desktop so Friday can read its chat list."
        case .notRunning:
            "WhatsApp is not running."
        case .notInstalled:
            "WhatsApp Web's tab title gives only the total. Install WhatsApp for Mac to see each chat."
        case .unreadable:
            "WhatsApp's chat list did not answer. Try again in a moment."
        }
    }

    private var action: (title: String, perform: () -> Void)? {
        switch notice {
        case .needsAccessibility:
            (
                "Allow",
                {
                    WhatsAppAccessibilityReader.requestTrust()
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            )
        case .needsScreenPermission:
            ("Allow", { loader.connections.requestScreenPermission() })
        case .noWindow, .notRunning:
            // A click here is the user's choice to bring WhatsApp forward.
            ("Open WhatsApp", { loader.connections.openWhatsApp() })
        case .sandboxed, .notInstalled, .unreadable:
            nil
        }
    }
}
