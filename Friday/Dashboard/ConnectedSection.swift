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

    private var whatsappValue: String? {
        connections.whatsappUnread.map(String.init)
    }

    private var whatsappAction: ConnectorTile.Action? {
        if connections.isWhatsAppInstalled {
            switch connections.whatsappStatus {
            case .denied: return .init(title: "Allow access") { connections.openPrivacySettings() }
            case .unavailable: return .init(title: "Open WhatsApp") { connections.openWhatsApp() }
            case .connected, .notConnected: return nil
            }
        }
        switch connections.whatsappWeb {
        case .needsPermission: return .init(title: "Connect Chrome") { Task { await connections.connectChrome() } }
        case .denied: return .init(title: "Allow in Settings") { connections.openAutomationSettings() }
        case .chromeClosed, .noTab: return .init(title: "Open WhatsApp Web") { ChromeTabs.openWhatsAppWeb() }
        case .noChrome, .unread, nil: return nil
        }
    }

    private var whatsappCaption: String {
        if let report = connections.whatsappReport {
            return Self.caption(for: report, names: connections.showsNames)
        }
        if let web = connections.whatsappWebUnread {
            return web == 1 ? "unread chat (WhatsApp Web)" : "unread chats (WhatsApp Web)"
        }
        switch connections.whatsappStatus {
        case .denied: return "macOS blocked Friday from WhatsApp's data. Allow it, then reopen Friday"
        case .unavailable(let reason): return reason
        case .notConnected:
            return connections.isWhatsAppInstalled
                ? "Reading WhatsApp…" : "Connect Chrome to count unread chats from WhatsApp Web"
        case .connected: return "No unread chats"
        }
    }

    static func caption(for report: WhatsAppDatabase.Report, names: Bool) -> String {
        guard report.unreadChats > 0 else { return "No unread chats" }
        let label = report.unreadChats == 1 ? "unread chat" : "unread chats"
        let muted = report.mutedChats > 0 ? " · \(report.mutedChats) muted" : ""
        guard names else { return "\(label) · \(report.unreadMessages) messages" + muted }
        let latest = report.chats.prefix(2).map { $0.name ?? "Unknown" }
        let more = report.unreadChats > 2 ? " +\(report.unreadChats - 2)" : ""
        return "\(label): " + latest.joined(separator: ", ") + more
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
