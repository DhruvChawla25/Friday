// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

/// Shared state the orb renders.
@MainActor
@Observable
final class OrbModel {
    var unread = 0
    var isWorking = false
    var isHidden = false
}

/// The small always-on orb: the rotating ribbon on a dark glass disc,
/// with an unread badge.
struct OrbView: View {
    let model: OrbModel
    static let diameter: CGFloat = 46

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.inkRaised.opacity(0.92), Theme.ink.opacity(0.96)],
                            center: .center, startRadius: 0, endRadius: Self.diameter / 2
                        )
                    )
                Circle()
                    .strokeBorder(Theme.orange.opacity(0.45), lineWidth: 1)
                RibbonView(
                    segments: 48,
                    period: model.isWorking ? 2.5 : 9,
                    showsOrbits: true,
                    showsStars: false,
                    paused: model.isHidden
                )
                .padding(5)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .shadow(color: Theme.orange.opacity(0.35), radius: 6)

            if model.unread > 0 {
                Text(model.unread > 99 ? "99+" : "\(model.unread)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Theme.badge))
                    .offset(x: 5, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(6)
        .animation(.spring(duration: 0.3), value: model.unread)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Friday, \(model.unread) unread")
        .accessibilityAddTraits(.isButton)
    }
}
