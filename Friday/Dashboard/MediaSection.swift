// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

/// "Now playing": Spotify and every YouTube / YouTube Music tab in Chrome,
/// with play/pause, next, previous and "show".
struct MediaSection: View {
    let media: MediaCenter

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "Now playing")
            VStack(spacing: 2) {
                if media.items.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.m)
                } else {
                    ForEach(media.items) { item in
                        MediaRow(item: item, media: media)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            if !prompts.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    ForEach(prompts, id: \.title) { prompt in
                        Button(prompt.title, action: prompt.perform).buttonStyle(ConnectButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
            if media.chromeJavaScriptBlocked {
                Text(
                    "For play state and controls on YouTube: Chrome → View → Developer → Allow JavaScript from Apple Events."
                )
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyText: String {
        let spotify = media.isRunning(.spotify)
        let chrome = media.isRunning(.chrome)
        if !spotify && !chrome { return "Nothing playing. Open Spotify or a YouTube tab in Chrome." }
        return "Nothing playing."
    }

    private struct Prompt {
        let title: String
        let perform: () -> Void
    }

    private var prompts: [Prompt] {
        [MediaApp.spotify, .chrome].compactMap { app in
            switch media.access[app] {
            case .notDetermined:
                Prompt(title: "Connect \(app.name)") { Task { await media.connect(app) } }
            case .denied:
                Prompt(title: "Allow \(app.name) in Settings") { media.openAutomationSettings() }
            case .granted, .notRunning, nil:
                nil
            }
        }
    }
}

private struct MediaRow: View {
    let item: MediaItem
    let media: MediaCenter
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            AppIconView(bundleID: item.source == .spotify ? MediaApp.spotify.bundleID : MediaApp.chrome.bundleID)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.state == .playing ? Theme.online : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                    Text([item.source.label, item.subtitle].compactMap(\.self).joined(separator: " · "))
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: Theme.Space.s) {
                control(.previous, symbol: "backward.fill", help: "Previous")
                control(
                    .playPause, symbol: item.state == .playing ? "pause.fill" : "play.fill",
                    help: item.state == .playing ? "Pause" : "Play")
                control(.next, symbol: "forward.fill", help: "Next")
                control(.reveal, symbol: "arrow.up.forward.app", help: "Show")
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.05 : 0))
        )
        .onHover { hovering = $0 }
    }

    @ViewBuilder private func control(_ control: MediaItem.Control, symbol: String, help: String) -> some View {
        let enabled = item.controls.contains(control)
        Button {
            Task { await media.send(control, to: item) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.orange : Theme.textSecondary.opacity(0.4))
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct AppIconView: View {
    let bundleID: String

    var body: some View {
        if let image = AppIcon(bundleID: bundleID, fallback: "music.note").image {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "music.note").foregroundStyle(Theme.orange)
        }
    }
}
