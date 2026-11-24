import Foundation

/// Minimal 3D vector maths for the ribbon renderer.
struct Vec3: Equatable, Sendable {
    var x: Double, y: Double, z: Double

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }

    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    func cross(_ o: Vec3) -> Vec3 { Vec3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x) }
    var length: Double { dot(self).squareRoot() }
    var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }

    /// Rotation around the Y axis, then the X axis.
    func rotated(yaw: Double, pitch: Double) -> Vec3 {
        let cy = cos(yaw), sy = sin(yaw)
        let r1 = Vec3(x: x * cy + z * sy, y: y, z: -x * sy + z * cy)
        let cp = cos(pitch), sp = sin(pitch)
        return Vec3(x: r1.x, y: r1.y * cp - r1.z * sp, z: r1.y * sp + r1.z * cp)
    }
}

/// A twisted, tapering ribbon swept along an S-shaped spine:
/// Friday's logo, built procedurally so it can rotate in real 3D.
enum RibbonModel {
    struct Quad: Sendable {
        /// Corners in order: left(t0), right(t0), right(t1), left(t1).
        var corners: [Vec3]
        var normal: Vec3
        /// Position along the ribbon, 0…1 (drives the colour gradient).
        var t: Double
    }

    static func spine(_ t: Double) -> Vec3 {
        let s = t * 2 - 1
        return Vec3(
            x: 0.42 * sin(s * .pi * 0.95),
            y: 1.05 * s,
            z: 0.30 * cos(s * .pi * 0.95)
        )
    }

    static func width(_ t: Double) -> Double {
        0.50 * pow(sin(.pi * t), 0.7)
    }

    static func twist(_ t: Double) -> Double {
        .pi * 1.6 * t + 0.2
    }

    /// Edge points of the ribbon cross-section at `t`.
    static func edges(at t: Double) -> (left: Vec3, right: Vec3) {
        let epsilon = 0.001
        let tangent = (spine(min(t + epsilon, 1)) - spine(max(t - epsilon, 0))).normalized
        let reference = abs(tangent.z) < 0.9 ? Vec3(x: 0, y: 0, z: 1) : Vec3(x: 1, y: 0, z: 0)
        let normal = tangent.cross(reference).normalized
        let binormal = tangent.cross(normal).normalized
        let angle = twist(t)
        let direction = normal * cos(angle) + binormal * sin(angle)
        let half = direction * (width(t) / 2)
        let center = spine(t)
        return (center - half, center + half)
    }

    static func quads(segments: Int) -> [Quad] {
        precondition(segments > 0)
        var result: [Quad] = []
        result.reserveCapacity(segments)
        var previous = edges(at: 0)
        for index in 1...segments {
            let t1 = Double(index) / Double(segments)
            let current = edges(at: t1)
            let corners = [previous.left, previous.right, current.right, current.left]
            let normal = (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized
            result.append(Quad(corners: corners, normal: normal, t: t1 - 0.5 / Double(segments)))
            previous = current
        }
        return result
    }
}
