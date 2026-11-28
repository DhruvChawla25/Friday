// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct ConnectedSection: View {
    let connections: Connections

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "Connected")
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ConnectorTile(
                    name: "WhatsApp",
                    icon: AppIcon(
                        bundleID: connections.isWhatsAppInstalled ? Connections.whatsappBundleID : ChromeTabs.bundleID,
                        fallback: "message.fill"),
                    value: whatsappValue,
                    caption: whatsappCaption,
                    action: whatsappAction,
                    onOpen: { WhatsAppUnreadPopup.shared.show(connections: connections) },
                    openHint: "Show every unread chat"
                )
                ConnectorTile(
                    name: "Mail",
                    icon: AppIcon(bundleID: nil, fallback: "envelope.fill"),
                    value: nil,
                    caption: "Coming soon: connects to your new mail app",
                    action: nil
                )
                .opacity(0.55)
                ConnectorTile(
                    name: "Calendar",
                    icon: AppIcon(bundleID: "com.apple.iCal", fallback: "calendar"),
                    value: connections.calendar.map { String($0.remainingToday) },
                    caption: calendarCaption,
                    action: calendarAction
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The largest of: WhatsApp Web title, fresh screen reading, Dock badge.
    private var whatsappValue: String? {
        connections.whatsappUnread.map(String.init)
    }

    /// True when the WhatsApp Web title gives a bigger number than the screen.
    private var webIsLargest: Bool {
        guard let web = connections.whatsappWebUnread else { return false }
        return web >= (connections.freshScreenReport?.unreadChats ?? 0) && web >= (connections.whatsappBadge ?? 0)
    }

    private var whatsappAction: ConnectorTile.Action? {
        // Chrome first: one click gives the full unread-chat total.
        if connections.whatsappWeb == .needsPermission {
            return .init(title: "Connect Chrome") { Task { await connections.connectChrome() } }
        }
        if !connections.isWhatsAppInstalled, let web = connections.whatsappWeb {
            switch web {
            case .denied: return .init(title: "Allow in Settings") { connections.openAutomationSettings() }
            case .chromeClosed, .noTab: return .init(title: "Open WhatsApp Web") { ChromeTabs.openWhatsAppWeb() }
            case .noChrome, .unread, .needsPermission: return nil
            }
        }
        guard connections.isWhatsAppInstalled else { return nil }
        if !connections.screenPermission {
            return .init(title: "Allow screen reading") { connections.requestScreenPermission() }
        }
        if connections.isReadingWhatsApp { return nil }
        if connections.whatsappBadgeLooksOff {
            return .init(title: "Turn on badge") { connections.openNotificationSettings() }
        }
        return .init(title: connections.whatsappStatus == .connected ? "Check now" : "Open WhatsApp") {
            Task { await connections.readWhatsAppScreen(bringToFront: true) }
        }
    }

    private var whatsappCaption: String {
        if connections.isReadingWhatsApp { return "Reading WhatsApp…" }
        if connections.isWhatsAppInstalled, !connections.screenPermission,
            let caption = ScreenPermissionFlow.caption(for: connections.screenPermissionStage)
        {
            return caption
        }
        if connections.whatsappBadgeLooksOff {
            return "WhatsApp's Dock badge is off: live counts need it"
        }
        if webIsLargest, let web = connections.whatsappWebUnread {
            let label = web == 1 ? "unread chat" : "unread chats"
            if let report = connections.freshScreenReport, connections.showsNames, !report.chats.isEmpty {
                let names = report.chats.prefix(2).map { $0.name ?? "Unknown" }
                return "\(label) (WhatsApp Web): " + names.joined(separator: ", ") + " +\(max(0, web - names.count))"
            }
            return "\(label) (WhatsApp Web)"
        }
        if connections.whatsappWeb == .needsPermission {
            return "Connect Chrome to count every unread chat from WhatsApp Web"
        }
        if !connections.isWhatsAppInstalled, connections.whatsappWeb == .denied { return "Chrome access denied" }
        if let report = connections.freshScreenReport {
            guard report.unreadChats > 0 else { return "No unread chats" }
            let label = report.unreadChats == 1 ? "unread chat" : "unread chats"
            guard connections.showsNames else { return "\(label) · \(report.unreadMessages) messages" }
            let names = report.chats.prefix(2).map { $0.name ?? "Unknown" }
            let more = report.chats.count > 2 ? " +\(report.chats.count - 2)" : ""
            return "\(label): " + names.joined(separator: ", ") + more
        }
        switch connections.whatsappStatus {
        case .connected:
            if connections.whatsappBadge == 0 { return "No unread messages, or WhatsApp's Dock badge is off" }
            return connections.whatsappBadge == 1 ? "unread message (Dock badge)" : "unread messages (Dock badge)"
        case .unavailable(let reason): return reason
        case .denied, .notConnected: return "Reads WhatsApp's chat list on screen"
        }
    }

    private var calendarAction: ConnectorTile.Action? {
        switch connections.calendarStatus {
        case .connected: nil
        case .denied: .init(title: "Allow in Settings") { openCalendarSettings() }
        case .notConnected, .unavailable: .init(title: "Connect") { Task { await connections.connectCalendar() } }
        }
    }

    private var calendarCaption: String {
        guard let summary = connections.calendar else {
            return connections.calendarStatus == .denied ? "Calendar access denied" : "Today's events"
        }
        guard let start = summary.nextStart, let title = summary.nextTitle else { return "nothing else today" }
        return "next \(start.formatted(date: .omitted, time: .shortened)) · \(title)"
    }

    private func openCalendarSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}

struct AppIcon {
    let bundleID: String?
    let fallback: String

    @MainActor var image: NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct ConnectorTile: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let name: String
    let icon: AppIcon
    let value: String?
    let caption: String
    let action: Action?
    /// Clicking the tile itself (outside its button) opens a detail view.
    var onOpen: (() -> Void)? = nil
    var openHint: String? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                iconView.frame(width: 22, height: 22)
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Circle()
                    .fill(value == nil ? Color.white.opacity(0.2) : Theme.online)
                    .frame(width: 6, height: 6)
            }
            Text(value ?? "—")
                .font(Theme.Font.metric)
                .foregroundStyle(value == nil ? Theme.textSecondary : Theme.amber)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(ConnectButtonStyle())
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(value == nil ? Theme.hairline : Theme.orange.opacity(0.3), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .onTapGesture { onOpen?() }
        .onHover { inside in
            hovering = inside
            guard onOpen != nil else { return }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(openHint ?? "")
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
        .accessibilityAction { onOpen?() }
    }

    @ViewBuilder private var iconView: some View {
        if let image = icon.image {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: icon.fallback)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.orange)
                .padding(2)
        }
    }
}

struct ConnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.orange.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}
