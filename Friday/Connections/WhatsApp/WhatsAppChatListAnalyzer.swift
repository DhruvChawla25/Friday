// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import Vision

/// Finds unread chats in a screenshot of the WhatsApp for Mac window.
///
/// How it works:
/// 1. Find WhatsApp's green unread bubbles by colour and shape.
/// 2. Read the number inside each bubble.
/// 3. Read only the chat-name line next to each bubble.
///
/// Privacy: message previews, the open conversation and every other part of
/// the window are never passed to text recognition. The image and all text
/// are discarded when `analyze` returns.
struct WhatsAppChatListAnalyzer: Sendable {
    struct UnreadChat: Equatable, Sendable {
        var name: String?
        var count: Int
        /// Someone @-mentioned you in this chat.
        var mentioned = false
    }

    struct Report: Equatable, Sendable {
        var chats: [UnreadChat]
        /// The total shown on the Chats icon in WhatsApp's left rail, if any.
        var railTotal: Int?

        var unreadChats: Int { chats.count }
        var unreadMessages: Int { chats.reduce(0) { $0 + $1.count } }
    }

    /// Bubble found in the image, in pixels (top-left origin).
    struct Bubble: Equatable, Sendable {
        var rect: CGRect
    }

    /// Pixels per point of the screenshot (2 on Retina).
    var scale: CGFloat = 2
    var readsNames = true

    func analyze(_ image: CGImage) -> Report {
        guard let pixels = RGBAImage(image) else { return Report(chats: [], railTotal: nil) }
        let bubbles = findBubbles(in: pixels)
        let railLimit = 90 * scale
        let rail = bubbles.filter { $0.rect.maxX < railLimit }
        let list = unreadColumn(
            bubbles.filter { $0.rect.minX >= railLimit && $0.rect.midX < CGFloat(pixels.width) * 0.6 })

        let chats = rows(of: list).map { row -> UnreadChat in
            let readings = row.map { reading(of: $0, pixels: pixels) }
            let count = readings.compactMap { reading -> Int? in
                if case .count(let n) = reading { return n }
                return nil
            }.first
            let leftmost = row.min { $0.rect.minX < $1.rect.minX }!
            return UnreadChat(
                name: readsNames ? name(beside: leftmost, in: image) : nil,
                count: count ?? 1,
                mentioned: readings.contains(.mention)
            )
        }
        var railTotal: Int?
        if let badge = rail.first, case .count(let n) = reading(of: badge, pixels: pixels) { railTotal = n }
        return Report(chats: chats, railTotal: railTotal)
    }

    // MARK: - Bubble detection

    /// WhatsApp's unread green, in light and dark mode (#25D366, #1DAA61, #21C063, #00A884).
    static func isUnreadGreen(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let (h, s, v) = hsv(r, g, b)
        return (125...170).contains(h) && s > 0.5 && v > 0.5
    }

    func findBubbles(in pixels: RGBAImage) -> [Bubble] {
        let width = pixels.width, height = pixels.height
        var visited = [Bool](repeating: false, count: width * height)
        var bubbles: [Bubble] = []
        var stack: [Int] = []

        for start in 0..<(width * height) where !visited[start] {
            visited[start] = true
            guard pixels.isGreen(start) else { continue }
            // Flood-fill this green region.
            var minX = width, minY = height, maxX = 0, maxY = 0, area = 0
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % width, y = index / width
                area += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let next = ny * width + nx
                    if !visited[next] {
                        visited[next] = true
                        if pixels.isGreen(next) { stack.append(next) }
                    }
                }
            }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            if looksLikeBubble(rect, area: area) { bubbles.append(Bubble(rect: rect)) }
        }
        return bubbles
    }

    /// Pill or circle, 14–30 pt tall, mostly filled (the digits are holes).
    func looksLikeBubble(_ rect: CGRect, area: Int) -> Bool {
        let h = rect.height / scale, w = rect.width / scale
        guard (14...30).contains(h), (14...52).contains(w) else { return false }
        let aspect = w / h
        let fill = CGFloat(area) / (rect.width * rect.height)
        return (0.8...2.6).contains(aspect) && fill > 0.5
    }

    /// Unread count bubbles line up on the right of the chat list. Keep those,
    /// plus mention ("@") bubbles just to their left on the same rows.
    func unreadColumn(_ bubbles: [Bubble]) -> [Bubble] {
        guard bubbles.count > 1 else { return bubbles }
        let tolerance = 6 * scale
        let best = bubbles.max { a, b in
            bubbles.filter { abs($0.rect.maxX - a.rect.maxX) <= tolerance }.count
                < bubbles.filter { abs($0.rect.maxX - b.rect.maxX) <= tolerance }.count
        }!
        let column = best.rect.maxX
        return bubbles.filter { $0.rect.maxX <= column + tolerance && $0.rect.maxX >= column - 45 * scale }
    }

    /// Groups bubbles that sit on the same chat row.
    func rows(of bubbles: [Bubble]) -> [[Bubble]] {
        var rows: [[Bubble]] = []
        for bubble in bubbles.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let last = rows.last?.last, abs(last.rect.midY - bubble.rect.midY) < 10 * scale {
                rows[rows.count - 1].append(bubble)
            } else {
                rows.append([bubble])
            }
        }
        return rows
    }

    // MARK: - Reading text

    /// Reads what is inside a bubble: a number, or "@" for a mention.
    func reading(of bubble: Bubble, pixels: RGBAImage) -> BadgeGlyphReader.Reading? {
        BadgeGlyphReader.shared.read(ink: pixels.ink(inside: bubble.rect.integral))
    }

    /// Reads the chat name: the top text line of the bubble's row, left of
    /// the timestamp. Only this strip is passed to text recognition.
    func name(beside bubble: Bubble, in image: CGImage) -> String? {
        let top = max(0, bubble.rect.midY - 40 * scale)
        let bottom = bubble.rect.midY + 4 * scale
        let left = 90 * scale
        let right = bubble.rect.minX - 70 * scale  // stop before the timestamp
        let strip = CGRect(x: left, y: top, width: right - left, height: bottom - top).integral
        guard strip.width > 20, strip.height > 8, let crop = image.cropping(to: strip) else { return nil }
        // The name is the highest line in the strip; previews sit lower.
        let lines = recognizeLines(crop).sorted { $0.y < $1.y }
        let name = lines.first { !Self.looksLikeTime($0.text) }?.text.trimmingCharacters(in: .whitespaces)
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func looksLikeTime(_ text: String) -> Bool {
        text.wholeMatch(of: /\d{1,2}[:.]\d{2}\s*([ap]\.?m\.?)?/.ignoresCase()) != nil
    }

    /// Recognised lines with their top position (0 = top of the image).
    private func recognizeLines(_ image: CGImage) -> [(text: String, y: CGFloat)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, 1 - observation.boundingBox.maxY)
        }
    }

    static func hsv(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (h: Double, s: Double, v: Double) {
        let r = Double(r) / 255, g = Double(g) / 255, b = Double(b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
        var h = 0.0
        if delta > 0 {
            if maxV == r {
                h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }
        if h < 0 { h += 360 }
        return (h, maxV == 0 ? 0 : delta / maxV, maxV)
    }
}

/// An RGBA8 copy of a CGImage with fast pixel access.
struct RGBAImage: Sendable {
    let width: Int
    let height: Int
    let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        data = buffer
    }

    func isGreen(_ index: Int) -> Bool {
        let o = index * 4
        return WhatsAppChatListAnalyzer.isUnreadGreen(r: data[o], g: data[o + 1], b: data[o + 2])
    }

    /// Glyph ink inside a bubble: for pixels between the bubble's left and
    /// right green edges on each row, how far the colour is from the bubble's
    /// green (anti-aliased digit edges get partial values).
    func ink(inside rect: CGRect) -> InkMask {
        let x0 = max(0, Int(rect.minX)), y0 = max(0, Int(rect.minY))
        let x1 = min(width, Int(rect.maxX)), y1 = min(height, Int(rect.maxY))
        var mask = InkMask(width: max(0, x1 - x0), height: max(0, y1 - y0))
        guard x1 > x0, y1 > y0 else { return mask }

        // Reference: the average green of the bubble.
        var sum = (r: 0.0, g: 0.0, b: 0.0), n = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 where isGreen(y * width + x) {
                let o = (y * width + x) * 4
                sum.r += Double(data[o])
                sum.g += Double(data[o + 1])
                sum.b += Double(data[o + 2])
                n += 1
            }
        }
        guard n > 0 else { return mask }
        let green = (r: sum.r / n, g: sum.g / n, b: sum.b / n)

        // Skip a thin rim so the bubble's anti-aliased outline is not read as ink.
        let rim = max(1, Int((Double(y1 - y0) * 0.12).rounded()))
        for y in (y0 + rim)..<max(y0 + rim, y1 - rim) {
            guard let first = (x0..<x1).first(where: { isGreen(y * width + $0) }),
                let last = (x0..<x1).last(where: { isGreen(y * width + $0) }), last - first > rim * 2
            else { continue }
            for x in (first + rim)...(last - rim) {
                let o = (y * width + x) * 4
                let dr = Double(data[o]) - green.r, dg = Double(data[o + 1]) - green.g,
                    db = Double(data[o + 2]) - green.b
                let distance = (dr * dr + dg * dg + db * db).squareRoot() / 180
                mask[x - x0, y - y0] = min(1, distance)
            }
        }
        return mask
    }
}
