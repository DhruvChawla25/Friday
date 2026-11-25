// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

/// A loading-bar meter: the used part fills left to right in a strong colour
/// over a lighter track of the same hue. Orange normally, amber when close
/// to the limit, red when nearly out. With no known fraction it shows an
/// empty dashed track, so a missing limit never looks like "0 % used".
struct UsageBar: View {
    let fraction: Double?
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if let value = UsageFormat.clamp(fraction) {
                    Capsule().fill(color(value).opacity(0.22))
                    Capsule()
                        .fill(color(value))
                        .frame(width: value > 0 ? max(height, proxy.size.width * value) : 0)
                } else {
                    Capsule()
                        .strokeBorder(Theme.textSecondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(fraction.map { UsageFormat.percentUsed($0) } ?? "Limit unknown")
    }

    private func color(_ value: Double) -> Color {
        switch UsageFormat.level(value) {
        case .normal: Theme.orange
        case .warning: Theme.amber
        case .critical: Theme.badge
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        UsageBar(fraction: 0.15)
        UsageBar(fraction: 0.8)
        UsageBar(fraction: 0.97)
        UsageBar(fraction: nil)
    }
    .padding()
    .frame(width: 300)
    .background(Theme.ink)
}
