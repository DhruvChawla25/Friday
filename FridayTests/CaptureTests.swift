// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import Testing

@testable import Friday

// All tests use synthetic data. None of them capture the screen or show the overlay.

struct CaptureCommandParserTests {
    @Test(arguments: [
        "screenshot", "Screenshot.", "ss", "SS", "take a screenshot", "Take a screen shot please",
        "Friday, take a screenshot", "capture the whole screen", "can you take a screenshot?", "print screen",
    ])
    func recognisesScreenshot(_ text: String) {
        #expect(CaptureCommandParser.parse(Command(text)) == .screenshot)
    }

    @Test(arguments: [
        "snip", "Snip!", "snipping tool", "open snipping tool", "snip tool", "capture area", "capture a region",
        "capture part of the screen", "screenshot an area", "please use the snipping tool", "take a snip",
    ])
    func recognisesSnip(_ text: String) {
        #expect(CaptureCommandParser.parse(Command(text)) == .snip)
    }

    @Test(arguments: [
        "remember the screenshot is on my desktop", "what time is it", "open Safari", "screenshot my bank password",
        "delete screenshots", "", "ssh",
    ])
    func ignoresOtherSentences(_ text: String) {
        #expect(CaptureCommandParser.parse(Command(text)) == nil)
    }
}

struct CaptureFileNamerTests {
    // 2026-11-26 10:15:03 UTC
    let date = Date(timeIntervalSince1970: 1_795_688_103)
    let namer = CaptureFileNamer(timeZone: TimeZone(identifier: "UTC")!)

    @Test func namesMatchMacStyle() {
        #expect(namer.fileName(for: .screenshot, at: date) == "Friday Screenshot 2026-11-26 at 10.15.03.png")
        #expect(namer.fileName(for: .snip, at: date) == "Friday Snip 2026-11-26 at 10.15.03.png")
    }

    @Test func laterIndicesAddNumber() {
        #expect(namer.fileName(for: .snip, at: date, index: 2) == "Friday Snip 2026-11-26 at 10.15.03 (2).png")
        #expect(namer.fileName(for: .snip, at: date, index: 1) == "Friday Snip 2026-11-26 at 10.15.03.png")
    }

    @Test func usesGivenTimeZone() {
        let kolkata = CaptureFileNamer(timeZone: TimeZone(identifier: "Asia/Kolkata")!)
        #expect(kolkata.fileName(for: .screenshot, at: date) == "Friday Screenshot 2026-11-26 at 15.45.03.png")
    }
}

struct CaptureFileWriterTests {
    let date = Date(timeIntervalSince1970: 1_795_688_103)

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "FridayCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func neverOverwrites() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = CaptureFileWriter(directory: directory, namer: CaptureFileNamer(timeZone: .gmt))

        let first = try writer.write(Data([1]), kind: .snip, at: date)
        let second = try writer.write(Data([2]), kind: .snip, at: date)
        let third = try writer.write(Data([3]), kind: .snip, at: date)

        #expect(first.lastPathComponent == "Friday Snip 2026-11-26 at 10.15.03.png")
        #expect(second.lastPathComponent == "Friday Snip 2026-11-26 at 10.15.03 (2).png")
        #expect(third.lastPathComponent == "Friday Snip 2026-11-26 at 10.15.03 (3).png")
        #expect(try Data(contentsOf: first) == Data([1]))
        #expect(try Data(contentsOf: third) == Data([3]))
    }

    @Test func skipsGapsTakenByOtherFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let namer = CaptureFileNamer(timeZone: .gmt)
        try Data([9]).write(to: directory.appending(path: namer.fileName(for: .screenshot, at: date)))
        let writer = CaptureFileWriter(directory: directory, namer: namer)

        let url = try writer.write(Data([1]), kind: .screenshot, at: date)
        #expect(url.lastPathComponent == "Friday Screenshot 2026-11-26 at 10.15.03 (2).png")
        #expect(
            try Data(contentsOf: directory.appending(path: namer.fileName(for: .screenshot, at: date))) == Data([9]))
    }

    @Test func givesUpAfterMaxAttempts() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var writer = CaptureFileWriter(directory: directory, namer: CaptureFileNamer(timeZone: .gmt))
        writer.maxAttempts = 2
        _ = try writer.write(Data([1]), kind: .snip, at: date)
        _ = try writer.write(Data([1]), kind: .snip, at: date)
        #expect(throws: CaptureError.self) { try writer.write(Data([1]), kind: .snip, at: date) }
    }

    @Test func encodesPNG() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try #require(context.makeImage())
        let data = try #require(PNGEncoder.data(from: image))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}

struct CaptureGeometryTests {
    // Main display 1440×900 pt at the origin; a second 1920×1080 display to its right,
    // bottoms aligned; a third above the main display.
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 900, width: 1440, height: 900)

    @Test func findsDisplayUnderPointer() {
        let frames = [main, right, above]
        #expect(CaptureGeometry.displayIndex(containing: CGPoint(x: 10, y: 10), in: frames) == 0)
        #expect(CaptureGeometry.displayIndex(containing: CGPoint(x: 2000, y: 500), in: frames) == 1)
        #expect(CaptureGeometry.displayIndex(containing: CGPoint(x: 100, y: 1000), in: frames) == 2)
        // The seam belongs to exactly one display.
        #expect(CaptureGeometry.displayIndex(containing: CGPoint(x: 1440, y: 10), in: frames) == 1)
        #expect(CaptureGeometry.displayIndex(containing: CGPoint(x: 5000, y: 10), in: frames) == nil)
    }

    @Test func selectionNormalisesDragDirection() {
        let rect = CaptureGeometry.selection(
            from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), within: main, scale: 1)
        #expect(rect == CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    @Test func selectionIsClampedToStartDisplay() {
        let rect = CaptureGeometry.selection(
            from: CGPoint(x: 1400, y: 100), to: CGPoint(x: 1600, y: -50), within: main, scale: 2)
        #expect(rect == CGRect(x: 1400, y: 0, width: 40, height: 100))
    }

    @Test func selectionSnapsOutwardToRetinaPixels() {
        let rect = CaptureGeometry.selection(
            from: CGPoint(x: 10.3, y: 20.2), to: CGPoint(x: 50.6, y: 40.9), within: main, scale: 2)
        #expect(rect == CGRect(x: 10, y: 20, width: 41, height: 21))
        #expect(CaptureGeometry.pixelSize(of: rect, scale: 2) == (82, 42))
    }

    @Test func convertsToDisplayLocalTopLeft() {
        // 100×50 rect whose bottom-left is 10 pt from the left and 20 pt from the bottom of the main display.
        let onMain = CaptureGeometry.displayLocalRect(CGRect(x: 10, y: 20, width: 100, height: 50), displayFrame: main)
        #expect(onMain == CGRect(x: 10, y: 830, width: 100, height: 50))

        let onRight = CaptureGeometry.displayLocalRect(
            CGRect(x: 1500, y: 1000, width: 200, height: 80), displayFrame: right)
        #expect(onRight == CGRect(x: 60, y: 0, width: 200, height: 80))

        let onAbove = CaptureGeometry.displayLocalRect(
            CGRect(x: 0, y: 900, width: 1440, height: 900), displayFrame: above)
        #expect(onAbove == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test func pixelSizeUsesScale() {
        #expect(CaptureGeometry.pixelSize(of: main, scale: 2) == (2880, 1800))
        #expect(CaptureGeometry.pixelSize(of: right, scale: 1) == (1920, 1080))
    }

    @Test func tinySelectionsAreClicks() {
        #expect(!CaptureGeometry.isUsableSelection(CGRect(x: 0, y: 0, width: 2, height: 100)))
        #expect(CaptureGeometry.isUsableSelection(CGRect(x: 0, y: 0, width: 4, height: 4)))
        #expect(CaptureGeometry.selection(from: .zero, to: CGPoint(x: 10, y: 10), within: right, scale: 2) == .zero)
    }
}

private final class FakeCapturer: CapturePerforming, @unchecked Sendable {
    var outcome: CaptureOutcome
    private(set) var requests: [CaptureKind] = []

    init(_ outcome: CaptureOutcome) { self.outcome = outcome }

    @MainActor func capture(_ kind: CaptureKind) async -> CaptureOutcome {
        requests.append(kind)
        return outcome
    }
}

@MainActor
struct CaptureSkillTests {
    @Test func reportsSavedFile() async {
        let capturer = FakeCapturer(.saved(fileName: "Friday Snip 2026-11-26 at 10.15.03.png", copiedToClipboard: true))
        let reply = await CaptureSkill(capturer: capturer).handle(Command("snip"))
        #expect(reply == "Saved Friday Snip 2026-11-26 at 10.15.03.png to Desktop. Also copied to the clipboard.")
        #expect(capturer.requests == [.snip])
    }

    @Test func screenshotWithoutClipboard() async {
        let capturer = FakeCapturer(.saved(fileName: "x.png", copiedToClipboard: false))
        let reply = await CaptureSkill(capturer: capturer).handle(Command("take a screenshot"))
        #expect(reply == "Saved x.png to Desktop.")
        #expect(capturer.requests == [.screenshot])
    }

    @Test func cancelledAndPermission() async {
        #expect(
            await CaptureSkill(capturer: FakeCapturer(.cancelled)).handle(Command("snip")) == Persona.captureCancelled)
        let reply = await CaptureSkill(capturer: FakeCapturer(.permissionNeeded)).handle(Command("ss"))
        #expect(reply == Persona.capturePermission)
        #expect(reply.contains("Screen & System Audio Recording"))
    }

    @Test func registryRoutesOpenSnippingTool() async {
        let capturer = FakeCapturer(.cancelled)
        let registry = SkillRegistry(skills: [CaptureSkill(capturer: capturer)])
        _ = await registry.respond(to: "open snipping tool")
        #expect(capturer.requests == [.snip])
    }
}
