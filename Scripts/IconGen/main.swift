// Renders Friday's app icon from the same ribbon renderer the app uses.
// Usage: Scripts/make-icon.sh   (writes Friday/Assets.xcassets/AppIcon.appiconset)
import AppKit
import SwiftUI

struct IconArtwork: View {
    var body: some View {
        // Apple's macOS icon grid: 824pt rounded square centred in a 1024pt canvas.
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.09, blue: 0.03), Color(red: 0.04, green: 0.03, blue: 0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.7, blue: 0.4).opacity(0.30), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )
            Canvas { context, size in
                RibbonPainter.draw(
                    in: &context, size: size, yaw: 0.55, time: 1.0, segments: 220,
                    showsOrbits: true, showsStars: true
                )
            }
            .padding(40)
        }
        .frame(width: 824, height: 824)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render(to directory: URL) throws {
    let renderer = ImageRenderer(content: IconArtwork())
    renderer.scale = 1
    guard let master = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }

    let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    var images: [[String: String]] = []
    for (points, scale) in sizes {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.imageInterpolation = .high
        NSGraphicsContext.current = context
        context.cgContext.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: directory.appending(path: "Contents.json"))
}

let output = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try MainActor.assumeIsolated { try render(to: output) }
print("✔ App icon written to \(output.path)")
