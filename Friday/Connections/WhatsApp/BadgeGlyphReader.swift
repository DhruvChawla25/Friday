// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import CoreText
import Foundation

/// Reads the tiny digits inside WhatsApp's unread bubbles.
///
/// General OCR is unreliable on one or two 6–10 px glyphs, so this matches
/// each glyph's shape against digits rendered in the system font: a small,
/// fast, fully on-device template matcher working on anti-aliased ink.
struct BadgeGlyphReader: Sendable {
    /// A glyph resampled to a fixed grid of ink values (0…1), plus its width/height ratio.
    struct Shape: Sendable {
        var cells: [Double]
        var aspect: Double
    }

    enum Reading: Equatable, Sendable {
        case count(Int)
        case mention
    }

    static let columns = 8
    static let rows = 12
    static let shared = BadgeGlyphReader()

    let templates: [(symbol: Character, shape: Shape)]

    init() {
        var templates: [(Character, Shape)] = []
        for weight in [0.23, 0.3, 0.4, 0.5] {  // regular → bold
            let font = CTFontCreateWithFontDescriptor(
                CTFontDescriptorCreateWithAttributes(
                    [
                        kCTFontTraitsAttribute: [kCTFontWeightTrait: weight],
                        kCTFontFamilyNameAttribute: ".AppleSystemUIFont",
                    ] as CFDictionary), 48, nil)
            for symbol in "0123456789@" {
                if let mask = Self.render(symbol, font: font), let shape = Self.shape(of: mask) {
                    templates.append((symbol, shape))
                }
            }
        }
        self.templates = templates
    }

    /// `ink` holds how much each pixel inside the bubble differs from the bubble colour.
    func read(ink: InkMask) -> Reading? {
        let glyphs = ink.splitIntoGlyphs()
        guard !glyphs.isEmpty else { return nil }

        // Interpretation 1: a number, one glyph per digit.
        var digits = ""
        var digitDistance = 0.0
        var digitsValid = glyphs.count <= 4
        for glyph in glyphs where digitsValid {
            guard let shape = Self.shape(of: glyph), let best = best(for: shape, among: "0123456789") else {
                digitsValid = false
                break
            }
            digits.append(best.symbol)
            digitDistance = max(digitDistance, best.distance)
        }

        // Interpretation 2: one "@" (its internal gaps can split it into fake digits).
        if let whole = Self.shape(of: ink), let mention = best(for: whole, among: "@") {
            if !digitsValid || mention.distance < digitDistance { return .mention }
        }
        return digitsValid ? Int(digits).map(Reading.count) : nil
    }

    func best(for shape: Shape, among symbols: String) -> (symbol: Character, distance: Double)? {
        var best: (Character, Double)?
        for template in templates where symbols.contains(template.symbol) {
            var distance = 0.0
            for i in shape.cells.indices {
                let d = shape.cells[i] - template.shape.cells[i]
                distance += d * d
            }
            distance /= Double(shape.cells.count)
            // Width matters: it separates "1" from everything else.
            distance += 0.15 * pow(log(shape.aspect / template.shape.aspect), 2)
            if best == nil || distance < best!.1 { best = (template.symbol, distance) }
        }
        return best.map { ($0.0, $0.1) }
    }

    // MARK: - Shapes

    /// Crops to the ink and resamples it (bilinear) to a fixed grid.
    static func shape(of mask: InkMask) -> Shape? {
        guard let box = mask.inkBounds else { return nil }
        let w = Double(box.maxX - box.minX + 1), h = Double(box.maxY - box.minY + 1)
        var cells = [Double](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Double(box.minX) + (Double(column) + 0.5) / Double(columns) * w - 0.5
                let y = Double(box.minY) + (Double(row) + 0.5) / Double(rows) * h - 0.5
                cells[row * columns + column] = mask.sample(x: x, y: y)
            }
        }
        // Normalise contrast so light and heavy fonts compare fairly.
        if let peak = cells.max(), peak > 0 { cells = cells.map { $0 / peak } }
        return Shape(cells: cells, aspect: w / h)
    }

    private static func render(_ symbol: Character, font: CTFont) -> InkMask? {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: String(symbol),
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                    ]))
            context.textPosition = CGPoint(x: 8, y: 12)
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return nil }
        // A bitmap context's first row in memory is the top of the image, like screenshots.
        var mask = InkMask(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size { mask[x, y] = Double(pixels[y * size + x]) / 255 }
        }
        return mask
    }
}

/// A small greyscale image of glyph ink (0 = none, 1 = full).
struct InkMask: Sendable {
    static let threshold = 0.35

    let width: Int
    let height: Int
    private var values: [Double]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        values = [Double](repeating: 0, count: width * height)
    }

    subscript(x: Int, y: Int) -> Double {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }

    func isInk(_ x: Int, _ y: Int) -> Bool { self[x, y] >= Self.threshold }

    /// Bilinear sample; outside the mask counts as no ink.
    func sample(x: Double, y: Double) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        func value(_ x: Int, _ y: Int) -> Double {
            (x >= 0 && y >= 0 && x < width && y < height) ? self[x, y] : 0
        }
        let top = value(x0, y0) * (1 - fx) + value(x0 + 1, y0) * fx
        let bottom = value(x0, y0 + 1) * (1 - fx) + value(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }

    var inkBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where isInk(x, y) {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, minY, maxX, maxY)
    }

    /// Splits side-by-side glyphs at columns without ink ("12" → "1", "2").
    /// Slivers shorter than a third of the bubble are noise, not glyphs.
    func splitIntoGlyphs() -> [InkMask] {
        splitColumns().filter { glyph in
            guard let box = glyph.inkBounds else { return false }
            return box.maxY - box.minY + 1 >= max(3, height / 3)
        }
    }

    private func splitColumns() -> [InkMask] {
        var glyphs: [InkMask] = []
        var start: Int?
        for x in 0...width {
            let hasInk = x < width && (0..<height).contains { isInk(x, $0) }
            if hasInk, start == nil { start = x }
            if !hasInk, let s = start {
                var glyph = InkMask(width: x - s, height: height)
                for gx in 0..<(x - s) {
                    for y in 0..<height { glyph[gx, y] = self[s + gx, y] }
                }
                glyphs.append(glyph)
                start = nil
            }
        }
        return glyphs
    }
}
