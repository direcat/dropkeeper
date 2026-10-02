import SwiftUI

// DropKeeper design tokens (see the design manual).
// The short names (`TK`, `Space.xs` … `Space.xl`) are the design manual's token names.
// swiftlint:disable:next type_name
enum TK {
    enum Petrol {
        static let p100 = Color(hex: 0xEAF8F9)
        static let p200 = Color(hex: 0xD2EEF0)
        static let p300 = Color(hex: 0xA3DDE0)
        static let p400 = Color(hex: 0x6AC2C6)
        static let p500 = Color(hex: 0x39A4A9)
        static let p600 = Color(hex: 0x188489)
        static let p700 = Color(hex: 0x0C6468)
        static let p800 = Color(hex: 0x034649)
        static let p900 = Color(hex: 0x002A2D)
        static let glow = Color(hex: 0x7FDDDD)
    }
    enum Neutral {
        static let n100 = Color(hex: 0xF1F6F7)
        static let n200 = Color(hex: 0xE3E9E9)
        static let n300 = Color(hex: 0xCDD2D2)
        static let n400 = Color(hex: 0xADB2B2)
        static let n500 = Color(hex: 0x8E9393)
        static let n600 = Color(hex: 0x717676)
        static let n700 = Color(hex: 0x545959)
        static let n800 = Color(hex: 0x3A3E3E)
        static let n900 = Color(hex: 0x212525)
        static let ink = Color(hex: 0x1D1F20)
    }
    /// Notch is always black hardware – fixed palette, independent of appearance.
    enum Notch {
        static let surface = Color.black
        static let surfaceRaised = Neutral.n900
        static let textPrimary = Color.white
        static let textSecondary = Neutral.n400
        static let hairline = Neutral.n800
        static let accent = Petrol.p400
        static let accentText = Petrol.p300
        static let accentFill = Petrol.p500
        static let onAccent = Color.black
        static let urgent = Color(hex: 0xEBA941)
    }
    enum FileType {
        static let image = Color(hex: 0x9274C3)
        static let document = Color(hex: 0xCD605A)
        static let archive = Color(hex: 0xCA933E)
        static let installer = Color(hex: 0x558AC0)
        static let code = Color(hex: 0x50A064)
        static let other = Color(hex: 0x808888)
        static let backgroundOpacity = 0.16
    }
    enum Space {
        // swiftlint:disable:next identifier_name
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }
    enum Radius {
        static let control: CGFloat = 8
        static let notchBottom: CGFloat = 20
        static let fileGlyph: CGFloat = 8
    }
    enum Size {
        static let notchPanelWidth: CGFloat = 420
        static let fileGlyph: CGFloat = 36
        static let listRow: CGFloat = 44
        static let timelineDot: CGFloat = 8
        static let timelineDotSelected: CGFloat = 12
    }
    enum Motion {
        static let open = Animation.spring(response: 0.35, dampingFraction: 0.82)
        static let close = Animation.easeIn(duration: 0.22)
        static let select = Animation.spring(response: 0.25, dampingFraction: 0.85)
        static let pulse = Animation.easeInOut(duration: 0.5)
        static let reduced = Animation.easeInOut(duration: 0.15)
        static let deletedNoticeSeconds: Double = 2.5
        static let urgentThresholdSeconds = 10
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
