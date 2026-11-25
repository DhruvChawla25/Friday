// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

/// Two small buttons in the command bar: full screenshot and snip. They go
/// through the normal command path so the result appears in the log.
/// When Screen Recording permission is missing, an "Allow" button opens
/// the right System Settings pane.
struct CaptureButtons: View {
    let assistant: Assistant
    var coordinator: ScreenCaptureCoordinator = .shared

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if coordinator.needsPermission {
                Button("Allow") { coordinator.openScreenRecordingSettings() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.amber)
                    .help("Open Screen Recording settings")
            }
            iconButton("camera.viewfinder", label: "Screenshot", command: "screenshot")
            iconButton("crop", label: "Snip", command: "snip")
        }
        .disabled(assistant.isWorking)
    }

    private func iconButton(_ symbol: String, label: String, command: String) -> some View {
        Button {
            Task { await assistant.submit(command) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(label) to Desktop")
        .accessibilityLabel("\(label) to Desktop")
    }
}
