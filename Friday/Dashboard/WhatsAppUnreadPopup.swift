// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

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

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(connections: Connections, near anchor: NSWindow? = NSApp.keyWindow) {
        let panel =
            self.panel
            ?? WhatsAppUnreadPanel(
                rootView: WhatsAppUnreadView(connections: connections, onClose: { [weak self] in self?.hide() })
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
        connections.refresh()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.onDismiss = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}

/// Every unread chat, read from WhatsApp's own database (names, counts, mute
/// state and last-message time only; never message text).
struct WhatsAppUnreadView: View {
    let connections: Connections
    let onClose: () -> Void

    private var report: WhatsAppDatabase.Report? { connections.whatsappReport }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content
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
                Text(headline)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.amber)
                    .contentTransition(.numericText())
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button {
                connections.openWhatsApp()
            } label: {
                Text("Open WhatsApp")
            }
            .buttonStyle(ConnectButtonStyle())
            .disabled(!connections.isWhatsAppInstalled)
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

    private var headline: String {
        if let report {
            return report.unreadChats == 1 ? "1 unread chat" : "\(report.unreadChats) unread chats"
        }
        if let web = connections.whatsappWebUnread { return "\(web) unread chats" }
        return "Unread chats"
    }

    private var subtitle: String? {
        guard let report else { return nil }
        var parts = ["\(report.unreadMessages) messages"]
        if report.mutedChats > 0 { parts.append("\(report.mutedChats) muted") }
        if report.archivedUnreadChats > 0 { parts.append("+\(report.archivedUnreadChats) in Archived") }
        if !connections.showsNames { parts.append("Names hidden in Settings") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        if let report, !report.chats.isEmpty {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(report.chats) { chat in
                        ChatRow(chat: chat)
                    }
                }
                .padding(Theme.Space.s)
            }
            .scrollIndicators(.automatic)
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: report != nil ? "checkmark.circle" : "tray")
                    .font(.system(size: 26)).foregroundStyle(Theme.orange.opacity(0.8))
                Text(emptyText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyText: String {
        if report != nil { return "All caught up." }
        if connections.whatsappWebUnread != nil {
            return "WhatsApp Web's tab title gives only the total.\nInstall WhatsApp for Mac to see each chat."
        }
        if connections.whatsappStatus == .denied {
            return "macOS blocked Friday from WhatsApp's data.\nAllow it in Privacy & Security, then reopen Friday."
        }
        return "Nothing to show yet."
    }
}

private struct ChatRow: View {
    let chat: WhatsAppDatabase.Chat
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
                    if chat.muted { Image(systemName: "bell.slash.fill") }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 4) {
                Text(chat.lastMessage.map(Self.timeLabel) ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(countLabel)
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

    private var countLabel: String {
        if chat.count == 0 { return "•" }
        return chat.count > 999 ? "999+" : String(chat.count)
    }

    /// "14:05" today, "Yesterday", else a short date, like WhatsApp's list.
    static func timeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var placeholder: String {
        switch chat.kind {
        case .group: "Group chat \(chat.id + 1)"
        case .person, .channel: "Chat \(chat.id + 1)"
        }
    }

    private var icon: String {
        switch chat.kind {
        case .person: "person.fill"
        case .group: "person.3.fill"
        case .channel: "megaphone.fill"
        }
    }

    private var kindLabel: String {
        switch chat.kind {
        case .person: "Person"
        case .group: "Group"
        case .channel: "Channel"
        }
    }
}
