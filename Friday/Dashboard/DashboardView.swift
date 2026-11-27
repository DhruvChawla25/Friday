// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

struct DashboardView: View {
    let assistant: Assistant
    let connections: Connections
    let aiUsage: AIUsageMonitor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(connections: connections)
            hairline
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ConnectedSection(connections: connections)
                    AIUsageSection(monitor: aiUsage)
                    if !assistant.exchanges.isEmpty {
                        CommandLog(assistant: assistant)
                    }
                }
                .padding(Theme.Space.xl)
            }
            .scrollIndicators(.never)
            hairline
            CommandBar(assistant: assistant)
        }
        .foregroundStyle(Theme.textPrimary)
        .background {
            if reduceTransparency {
                // Reduce Transparency: one solid colour, no see-through star layer.
                Theme.ink
            } else {
                ZStack {
                    Theme.backgroundGradient
                    StarfieldView()
                        .opacity(0.5)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.orange.opacity(0.45), Theme.hairline], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .environment(\.colorScheme, .dark)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

private struct DashboardHeader: View {
    let connections: Connections

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            RibbonView(segments: 64, showsOrbits: true, showsStars: false)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("FRIDAY")
                    .font(Theme.Font.title)
                    .tracking(5)
                HStack(spacing: 6) {
                    Circle().fill(Theme.online).frame(width: 6, height: 6)
                    Text("SYS: ONLINE  ·  OFFLINE MODE  ·  NO NETWORK")
                        .font(Theme.Font.label)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            TimelineView(.everyMinute) { context in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.amber)
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased())
                        .font(Theme.Font.label)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HeaderMenu(connections: connections)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }
}

private struct HeaderMenu: View {
    let connections: Connections

    var body: some View {
        Menu {
            Button("Refresh") { connections.refresh() }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Friday") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }
}

private struct CommandLog: View {
    let assistant: Assistant

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                SectionLabel(text: "Log")
                Spacer()
                Button("Clear") { assistant.clearLog() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(assistant.exchanges.suffix(6)) { exchange in
                VStack(alignment: .leading, spacing: 3) {
                    Text("› \(exchange.request)")
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.amber.opacity(0.85))
                    Text(exchange.reply)
                        .font(Theme.Font.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CommandBar: View {
    let assistant: Assistant
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.orange)
            TextField("", text: $draft, prompt: Text("Command  ·  try \"help\"").foregroundStyle(Theme.textSecondary))
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .focused($focused)
                .onSubmit(send)
            if assistant.isWorking {
                ProgressView().controlSize(.small)
            }
            CaptureButtons(assistant: assistant)
            Text("⌃⌥Space")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
        .onAppear { focused = true }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await assistant.submit(text) }
    }
}
