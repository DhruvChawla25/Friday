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
                    icon: AppIcon(bundleID: "net.whatsapp.WhatsApp", fallback: "message.fill"),
                    value: connections.chromeStatus == .connected ? connections.whatsappUnread.map(String.init) : nil,
                    caption: whatsappCaption,
                    action: chromeAction
                )
                ConnectorTile(
                    name: "Gmail",
                    icon: AppIcon(bundleID: nil, fallback: "envelope.fill"),
                    value: connections.chromeStatus == .connected && !connections.gmailAccounts.isEmpty
                        ? String(connections.gmailUnread) : nil,
                    caption: gmailCaption,
                    action: chromeAction
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
            if connections.chromeStatus == .connected, !connections.gmailAccounts.isEmpty {
                GmailAccountsRow(accounts: connections.gmailAccounts)
            }
        }
    }

    private var chromeAction: ConnectorTile.Action? {
        switch connections.chromeStatus {
        case .connected: nil
        case .denied: .init(title: "Allow in Settings") { openAutomationSettings() }
        case .notConnected, .unavailable: .init(title: "Connect") { Task { await connections.connectChrome() } }
        }
    }

    private var calendarAction: ConnectorTile.Action? {
        switch connections.calendarStatus {
        case .connected: nil
        case .denied: .init(title: "Allow in Settings") { openCalendarSettings() }
        case .notConnected, .unavailable: .init(title: "Connect") { Task { await connections.connectCalendar() } }
        }
    }

    private var whatsappCaption: String {
        switch connections.chromeStatus {
        case .connected: connections.whatsappUnread == nil ? "Open WhatsApp Web in Chrome" : "unread chats"
        case .unavailable(let reason): reason
        case .denied: "Chrome access denied"
        case .notConnected: "Reads the unread number from Chrome"
        }
    }

    private var gmailCaption: String {
        switch connections.chromeStatus {
        case .connected:
            connections.gmailAccounts.isEmpty
                ? "Open your inboxes in Chrome"
                : "unread · \(connections.gmailAccounts.count) account\(connections.gmailAccounts.count == 1 ? "" : "s")"
        case .unavailable(let reason): reason
        case .denied: "Chrome access denied"
        case .notConnected: "Counts per account, from Chrome"
        }
    }

    private var calendarCaption: String {
        guard let summary = connections.calendar else {
            return connections.calendarStatus == .denied ? "Calendar access denied" : "Today's events"
        }
        guard let start = summary.nextStart, let title = summary.nextTitle else { return "nothing else today" }
        return "next \(start.formatted(date: .omitted, time: .shortened)) · \(title)"
    }

    private func openAutomationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
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
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .combine)
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

private struct ConnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.orange.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}

private struct GmailAccountsRow: View {
    let accounts: [TabTitleParser.GmailAccount]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Gmail accounts")
            FlowRow(spacing: 6) {
                ForEach(accounts) { account in
                    HStack(spacing: 6) {
                        Text(account.email)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.textSecondary)
                        Text("\(account.unread)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(account.unread > 0 ? Theme.amber : Theme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                }
            }
        }
    }
}

/// Simple wrapping layout for account chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for (index, point) in rows.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x)
        }
        return (origins, maxWidth, y + rowHeight)
    }
}
