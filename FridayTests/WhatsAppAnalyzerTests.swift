// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import Friday

/// Renders a fake WhatsApp chat list so the analyzer can be tested without
/// real chats. Layout mirrors WhatsApp for Mac: left rail, avatars, name line,
/// preview line, unread bubble on the right.
struct FakeChatList {
    struct Row {
        var name: String
        var badge: String?  // "3", "12", or nil (read chat)
        var mention = false
    }

    var rows: [Row]
    var scale: CGFloat = 2
    var dark = true

    func render() -> CGImage {
        let size = CGSize(width: 1000 * scale, height: CGFloat(rows.count) * 72 * scale + 80 * scale)
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Flip so we draw with a top-left origin, like the screen.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)

        let background = dark ? CGColor(red: 0.07, green: 0.11, blue: 0.13, alpha: 1) : CGColor(gray: 1, alpha: 1)
        let text = dark ? CGColor(gray: 0.92, alpha: 1) : CGColor(gray: 0.07, alpha: 1)
        let secondary = CGColor(gray: 0.55, alpha: 1)
        let green =
            dark
            ? CGColor(red: 0.13, green: 0.75, blue: 0.39, alpha: 1)
            : CGColor(red: 0.15, green: 0.83, blue: 0.40, alpha: 1)
        let badgeText = dark ? CGColor(red: 0.07, green: 0.11, blue: 0.13, alpha: 1) : CGColor(gray: 1, alpha: 1)

        context.setFillColor(background)
        context.fill(CGRect(origin: .zero, size: CGSize(width: size.width / scale, height: size.height / scale)))

        for (index, row) in rows.enumerated() {
            let top = 80 + CGFloat(index) * 72
            context.setFillColor(secondary)
            context.fillEllipse(in: CGRect(x: 110, y: top + 10, width: 48, height: 48))  // avatar
            draw(row.name, at: CGPoint(x: 172, y: top + 14), size: 16, color: text, in: context)
            draw(
                "Preview text that must never be read", at: CGPoint(x: 172, y: top + 40), size: 14, color: secondary,
                in: context)
            draw(
                "11:42", at: CGPoint(x: 520, y: top + 14), size: 12, color: row.badge == nil ? secondary : green,
                in: context)
            guard let badge = row.badge else { continue }
            let width: CGFloat = badge.count > 1 ? 28 : 20
            let badgeRect = CGRect(x: 560 - width, y: top + 38, width: width, height: 20)
            context.setFillColor(green)
            context.addPath(CGPath(roundedRect: badgeRect, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
            draw(badge, centeredIn: badgeRect, size: 12, color: badgeText, in: context)
            if row.mention {
                let mentionRect = CGRect(x: badgeRect.minX - 26, y: badgeRect.minY, width: 20, height: 20)
                context.setFillColor(green)
                context.fillEllipse(in: mentionRect)
                draw("@", centeredIn: mentionRect, size: 12, color: badgeText, in: context)
            }
        }
        return context.makeImage()!
    }

    private func font(_ size: CGFloat) -> CTFont {
        CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes(
                [kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3], kCTFontFamilyNameAttribute: ".AppleSystemUIFont"]
                    as CFDictionary), size, nil)
    }

    private func line(_ string: String, size: CGFloat, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: string,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font(size),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                ]))
    }

    private func draw(_ string: String, at point: CGPoint, size: CGFloat, color: CGColor, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: point.x, y: point.y + size)
        CTLineDraw(line(string, size: size, color: color), context)
        context.restoreGState()
    }

    private func draw(_ string: String, centeredIn rect: CGRect, size: CGFloat, color: CGColor, in context: CGContext) {
        let ctLine = line(string, size: size, color: color)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil))
        let capHeight = CTFontGetCapHeight(font(size))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: rect.midX - width / 2, y: rect.midY + capHeight / 2)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }
}

struct WhatsAppAnalyzerTests {
    static let rows: [FakeChatList.Row] = [
        .init(name: "Rahul Sharma", badge: "3"),
        .init(name: "Mom", badge: nil),
        .init(name: "Project Group", badge: "12", mention: true),
        .init(name: "Priya", badge: "1"),
        .init(name: "Gym Buddies", badge: "99"),
        .init(name: "Aman", badge: "7"),
    ]

    @Test(arguments: [(CGFloat(2), true), (2, false), (1, true), (1, false)])
    func readsCountsAndMentions(scale: CGFloat, dark: Bool) {
        let image = FakeChatList(rows: Self.rows, scale: scale, dark: dark).render()
        let report = WhatsAppChatListAnalyzer(scale: scale, readsNames: false).analyze(image)
        #expect(report.chats.map(\.count) == [3, 12, 1, 99, 7])
        #expect(report.chats.map(\.mentioned) == [false, true, false, false, false])
        #expect(report.unreadChats == 5)
        #expect(report.unreadMessages == 122)
    }

    @Test(arguments: [CGFloat(2), 1])
    func readsChatNamesButNotPreviews(scale: CGFloat) {
        let image = FakeChatList(rows: Self.rows, scale: scale).render()
        let report = WhatsAppChatListAnalyzer(scale: scale).analyze(image)
        #expect(report.chats.map(\.name) == ["Rahul Sharma", "Project Group", "Priya", "Gym Buddies", "Aman"])
        #expect(!report.chats.contains { $0.name?.contains("Preview") == true })
    }

    @Test func noUnreadChats() {
        let rows = Self.rows.map { FakeChatList.Row(name: $0.name, badge: nil) }
        let report = WhatsAppChatListAnalyzer(scale: 2).analyze(FakeChatList(rows: rows).render())
        #expect(report.chats.isEmpty)
    }

    @Test func greenDetection() {
        #expect(WhatsAppChatListAnalyzer.isUnreadGreen(r: 0x25, g: 0xD3, b: 0x66))  // classic
        #expect(WhatsAppChatListAnalyzer.isUnreadGreen(r: 0x21, g: 0xC0, b: 0x63))  // dark mode
        #expect(!WhatsAppChatListAnalyzer.isUnreadGreen(r: 0x00, g: 0x5C, b: 0x4B))  // sent bubble, dark
        #expect(!WhatsAppChatListAnalyzer.isUnreadGreen(r: 0xD9, g: 0xFD, b: 0xD3))  // sent bubble, light
    }

    @Test func timestampsAreNotNames() {
        #expect(WhatsAppChatListAnalyzer.looksLikeTime("11:42"))
        #expect(WhatsAppChatListAnalyzer.looksLikeTime("9:05 pm"))
        #expect(!WhatsAppChatListAnalyzer.looksLikeTime("Rahul"))
    }
}
