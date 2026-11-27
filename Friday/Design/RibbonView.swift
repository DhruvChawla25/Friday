// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI

/// Draws the rotating 3D ribbon with SwiftUI Canvas: real-time geometry,
/// painter's-algorithm depth sorting and simple diffuse + specular lighting.
struct RibbonView: View {
    var segments = 72
    /// Seconds per full rotation.
    var period: Double = 9
    var showsOrbits = true
    var showsStars = true
    var paused = false
    var frameRate: Double = 30
    /// With Reduce Motion on, the ribbon holds still (a single frame).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / frameRate, paused: paused || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                RibbonPainter.draw(
                    in: &context,
                    size: size,
                    yaw: time / period * 2 * .pi,
                    time: time,
                    segments: segments,
                    showsOrbits: showsOrbits,
                    showsStars: showsStars
                )
            }
        }
        .accessibilityLabel("Friday")
    }
}

enum RibbonPainter {
    static let colorStart = (r: 1.00, g: 0.34, b: 0.00)
    static let colorEnd = (r: 1.00, g: 0.80, b: 0.40)
    static let light = Vec3(x: -0.45, y: 0.65, z: 0.85).normalized
    static let halfVector = (light + Vec3(x: 0, y: 0, z: 1)).normalized

    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        yaw: Double,
        time: Double,
        segments: Int,
        showsOrbits: Bool,
        showsStars: Bool
    ) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let pitch = 0.28

        if showsStars { drawStars(in: &context, size: size, time: time) }
        if showsOrbits { drawOrbits(in: &context, center: center, side: side, yaw: yaw) }

        func project(_ v: Vec3) -> CGPoint {
            let perspective = 3.6 / (3.6 - v.z)
            let scale = side * 0.36 * perspective
            return CGPoint(x: center.x + v.x * scale, y: center.y - v.y * scale)
        }

        let quads = RibbonModel.quads(segments: segments).map { quad -> (path: Path, depth: Double, color: Color) in
            let corners = quad.corners.map { $0.rotated(yaw: yaw, pitch: pitch) }
            var normal = quad.normal.rotated(yaw: yaw, pitch: pitch)
            let isBack = normal.z < 0
            if isBack { normal = normal * -1 }
            let diffuse = max(0, normal.dot(light))
            let specular = pow(max(0, normal.dot(halfVector)), 28)
            let shade = (0.62 + 0.55 * diffuse) * (isBack ? 0.72 : 1)
            let t = quad.t
            let r = colorStart.r + (colorEnd.r - colorStart.r) * t
            let g = colorStart.g + (colorEnd.g - colorStart.g) * t
            let b = colorStart.b + (colorEnd.b - colorStart.b) * t
            let color = Color(
                red: min(1, r * shade + specular * 0.45),
                green: min(1, g * shade + specular * 0.45),
                blue: min(1, b * shade + specular * 0.45)
            )
            var path = Path()
            path.addLines(corners.map(project))
            path.closeSubpath()
            let depth = corners.reduce(0) { $0 + $1.z } / 4
            return (path, depth, color)
        }

        // Soft glow behind the ribbon.
        let glowRect = CGRect(x: center.x - side * 0.4, y: center.y - side * 0.4, width: side * 0.8, height: side * 0.8)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.10).opacity(0.45), .clear]),
                center: center,
                startRadius: 0,
                endRadius: side * 0.4
            )
        )

        for quad in quads.sorted(by: { $0.depth < $1.depth }) {
            context.fill(quad.path, with: .color(quad.color))
            context.stroke(quad.path, with: .color(quad.color), lineWidth: max(0.5, side / 400))
        }
    }

    private static func drawOrbits(in context: inout GraphicsContext, center: CGPoint, side: Double, yaw: Double) {
        let tilts: [(angle: Double, squash: Double, opacity: Double)] = [(-0.45, 0.32, 0.55), (0.62, 0.22, 0.35)]
        for (index, orbit) in tilts.enumerated() {
            let radius = side * (0.46 - Double(index) * 0.04)
            let wobble = sin(yaw * 0.5 + Double(index)) * 0.04
            var ellipse = Path(
                ellipseIn: CGRect(
                    x: -radius, y: -radius * (orbit.squash + wobble), width: radius * 2,
                    height: radius * 2 * (orbit.squash + wobble))
            )
            ellipse = ellipse.applying(CGAffineTransform(rotationAngle: orbit.angle))
            ellipse = ellipse.applying(CGAffineTransform(translationX: center.x, y: center.y))
            context.stroke(
                ellipse, with: .color(Color(red: 1.0, green: 0.66, blue: 0.30).opacity(orbit.opacity)),
                lineWidth: max(0.5, side / 160))
        }
    }

    static func drawStars(in context: inout GraphicsContext, size: CGSize, time: Double) {
        var generator = SeededRandom(seed: 7)
        for _ in 0..<28 {
            let x = generator.next() * size.width
            let y = generator.next() * size.height
            let phase = generator.next() * 6.28
            let twinkle = 0.35 + 0.35 * sin(time * 1.3 + phase)
            let radius = 0.4 + generator.next() * 0.9
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 1, green: 0.9, blue: 0.78).opacity(twinkle))
            )
        }
    }
}

/// Deterministic random numbers, so stars stay in place between frames.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// A slow, twinkling star field for backgrounds.
struct StarfieldView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 8, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                RibbonPainter.drawStars(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityHidden(true)
    }
}
