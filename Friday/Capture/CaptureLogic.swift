// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// What the user asked Friday to capture.
enum CaptureKind: Sendable, Equatable {
    /// The whole display the pointer is on.
    case screenshot
    /// A region the user drags out.
    case snip

    /// The word used in saved file names: "Friday Screenshot …", "Friday Snip …".
    var fileLabel: String {
        switch self {
        case .screenshot: "Screenshot"
        case .snip: "Snip"
        }
    }
}

/// Recognises capture commands. Matching is strict (whole phrases only) so a
/// sentence that merely mentions a screenshot, like "remember the screenshot
/// is on my desktop", is left to other skills.
enum CaptureCommandParser {
    /// Polite or filler words dropped before matching: "Friday, please take a screenshot".
    static let fillerWords: Set<String> = [
        "friday", "hey", "please", "pls", "can", "could", "would", "will", "you", "a", "an", "the", "me", "my",
        "of", "now", "quick", "quickly", "just", "for", "do", "use",
    ]

    static let screenshotPhrases: Set<String> = [
        "ss", "take ss", "screenshot", "screen shot", "screenshots", "take screenshot", "take screen shot",
        "full screenshot", "take full screenshot", "screenshot screen", "screenshot whole screen",
        "screenshot full screen", "capture screen", "capture whole screen", "capture full screen",
        "capture entire screen", "screenshot entire screen", "grab screen", "screen grab", "screengrab",
        "print screen",
    ]

    static let snipPhrases: Set<String> = [
        "snip", "take snip", "snip tool", "snipping tool", "snipping", "open snip tool", "open snipping tool",
        "start snipping tool", "snip area", "snip region", "snip screen", "capture area", "capture region",
        "capture selection", "capture part screen", "screenshot area", "screenshot region", "screenshot selection",
        "take area screenshot", "area screenshot", "region screenshot", "partial screenshot",
        "take partial screenshot", "select area", "ss area", "ss region",
    ]

    static func parse(_ command: Command) -> CaptureKind? {
        let phrase = command.words.filter { !fillerWords.contains($0) }.joined(separator: " ")
        if snipPhrases.contains(phrase) { return .snip }
        if screenshotPhrases.contains(phrase) { return .screenshot }
        return nil
    }
}

/// Builds Desktop file names like `Friday Snip 2026-11-26 at 10.15.03.png` and
/// never reuses one: a clash becomes `… (2).png`, `… (3).png`, and so on.
struct CaptureFileNamer: Sendable {
    var timeZone: TimeZone = .autoupdatingCurrent

    func baseName(for kind: CaptureKind, at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let day = "\(String(format: "%04d", parts.year ?? 0))-\(two(parts.month))-\(two(parts.day))"
        let time = "\(two(parts.hour)).\(two(parts.minute)).\(two(parts.second))"
        return "Friday \(kind.fileLabel) \(day) at \(time)"
    }

    /// `index` 1 is the plain name; 2 and above add " (n)".
    func fileName(for kind: CaptureKind, at date: Date, index: Int = 1) -> String {
        let base = baseName(for: kind, at: date)
        return index <= 1 ? "\(base).png" : "\(base) (\(index)).png"
    }
}

/// Rectangle maths for captures. AppKit uses global coordinates with the
/// origin at the bottom-left of the main display; ScreenCaptureKit wants a
/// rectangle in the display's own points with the origin at its top-left,
/// plus an output size in pixels (points × backing scale).
enum CaptureGeometry {
    /// The display (by frame, in AppKit global coordinates) that contains `point`.
    static func displayIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        // Use a half-open test so a point on the seam between two displays picks one.
        frames.firstIndex { frame in
            point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y < frame.maxY
        }
    }

    /// The rectangle spanned by a drag, clamped to `bounds` and snapped outward
    /// to whole pixels at `scale` so the saved image has no half-pixel blur.
    static func selection(from start: CGPoint, to end: CGPoint, within bounds: CGRect, scale: CGFloat) -> CGRect {
        let raw = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let clamped = raw.intersection(bounds)
        guard !clamped.isNull else { return .zero }
        return snapToPixels(clamped, scale: scale).intersection(bounds)
    }

    static func snapToPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Converts `rect` (AppKit global) to the display-local, top-left-origin
    /// rectangle ScreenCaptureKit's `sourceRect` expects.
    static func displayLocalRect(_ rect: CGRect, displayFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height)
    }

    /// The output image size in pixels.
    static func pixelSize(of rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        let scale = max(scale, 1)
        return (Int((rect.width * scale).rounded()), Int((rect.height * scale).rounded()))
    }

    /// Selections smaller than this (in points) are treated as a stray click.
    static let minimumSelection: CGFloat = 4

    static func isUsableSelection(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelection && rect.height >= minimumSelection
    }
}
