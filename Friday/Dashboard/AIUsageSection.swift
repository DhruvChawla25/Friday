// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

/// "AI usage": one card per installed AI tool, with a bar per limit window.
struct AIUsageSection: View {
    let monitor: AIUsageMonitor

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.m, alignment: .top),
        GridItem(.flexible(), spacing: Theme.Space.m, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionLabel(text: "AI usage")
                Spacer()
                if monitor.isLoading { ProgressView().controlSize(.mini) }
            }
            if monitor.tools.isEmpty {
                Text("Reading local usage…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else if monitor.installed.isEmpty {
                Text("No supported AI tools found on this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                TimelineView(.everyMinute) { context in
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.m) {
                        ForEach(monitor.installed) { usage in
                            ToolUsageCard(usage: usage, now: context.date)
                        }
                    }
                }
            }
            if !monitor.notInstalled.isEmpty {
                Text("Not found: " + monitor.notInstalled.map(\.tool.displayName).joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
    }
}

private struct ToolUsageCard: View {
    let usage: ToolUsage
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            header
            if let detail = usage.liveDetail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            ForEach(Array(usage.meters.enumerated()), id: \.offset) { _, meter in
                MeterRow(meter: meter, now: now)
            }
            Text(footer)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .lineLimit(2)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(usage.isLive ? Theme.orange.opacity(0.3) : Theme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            iconView.frame(width: 18, height: 18)
            Text(usage.tool.displayName).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            if usage.isLive {
                HStack(spacing: 4) {
                    Circle().fill(Theme.online).frame(width: 6, height: 6)
                    Text("LIVE").font(Theme.Font.label).tracking(1.2).foregroundStyle(Theme.online)
                }
            }
        }
    }

    @ViewBuilder private var iconView: some View {
        if let image = AppIcon(bundleID: usage.tool.bundleID, fallback: "sparkles").image {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "terminal")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.orange)
                .padding(1)
        }
    }

    private var footer: String {
        var text = usage.source
        if let last = usage.lastActive { text += " · last used " + UsageFormat.ago(last, now: now) }
        return text
    }
}

private struct MeterRow: View {
    let meter: UsageMeter
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.window)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                if let fraction = meter.usedFraction {
                    Text(UsageFormat.percentUsed(fraction))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.amber)
                }
            }
            UsageBar(fraction: meter.usedFraction)
            if meter.resetsAt != nil || meter.usedFraction != nil {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let reset = meter.resetsAt {
                        Text(UsageFormat.resets(at: reset, now: now, estimate: meter.resetIsEstimate))
                    }
                    Spacer(minLength: 4)
                    if let fraction = meter.usedFraction { Text(UsageFormat.percentLeft(fraction)) }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var caption: String {
        [meter.detail, meter.note].compactMap(\.self).joined(separator: " · ")
    }
}
