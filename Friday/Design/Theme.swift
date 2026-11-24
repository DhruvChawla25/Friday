import SwiftUI

/// Friday's design tokens. Every colour, font and spacing value comes from here.
enum Theme {
    // Palette: JARVIS-style HUD orange/amber on warm near-black.
    static let emberDeep = Color(red: 0.62, green: 0.20, blue: 0.02)
    static let orange = Color(red: 1.00, green: 0.48, blue: 0.08)
    static let amber = Color(red: 1.00, green: 0.74, blue: 0.32)
    static let ink = Color(red: 0.047, green: 0.035, blue: 0.027)
    static let inkRaised = Color(red: 0.090, green: 0.066, blue: 0.050)
    static let hairline = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let online = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let badge = Color(red: 1.00, green: 0.30, blue: 0.42)

    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.13, green: 0.07, blue: 0.03), ink],
        startPoint: .top,
        endPoint: .bottom
    )

    enum Font {
        static let label = SwiftUI.Font.system(size: 10, weight: .medium, design: .monospaced)
        static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold, design: .monospaced)
        static let metric = SwiftUI.Font.system(size: 30, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 13)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let corner: CGFloat = 14
}

/// Small uppercase monospace section label, e.g. "CONNECTED".
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(1.6)
            .foregroundStyle(Theme.textSecondary)
    }
}
