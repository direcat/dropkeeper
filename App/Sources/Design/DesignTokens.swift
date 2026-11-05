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
    /// Appearance-aware colors: each resolves to its light or dark value from the effective appearance of the
    /// view (Auto follows the system; Settings can force Light or Dark).
    enum Palette {
        static let textPrimary = dynamic(light: Color(hex: 0x1D1D1F), dark: Color(hex: 0xF5F5F7))
        static let textSecondary = dynamic(light: Color(hex: 0x6E6E73), dark: Color(hex: 0xA1A1A6))
        static let textTertiary = dynamic(light: Color(hex: 0xA1A1A6), dark: Color(hex: 0x6E6E73))
        static let fill = dynamic(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.08))
        static let fillStrong = dynamic(
            light: Color(hex: 0x767680).opacity(0.14), dark: Color(hex: 0x767680).opacity(0.28))
        static let hairline = dynamic(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.08))
        /// The inner highlight along the edge of a glass card.
        static let cardEdge = dynamic(light: Color.white.opacity(0.5), dark: Color.white.opacity(0.12))
        static let cardTint = dynamic(
            light: Color(hex: 0xF4F1EF).opacity(0.80), dark: Color(hex: 0x26262A).opacity(0.78))
        /// The selected segment of a segmented control.
        static let segmentOn = dynamic(light: Color.white, dark: Color.white.opacity(0.18))
        static let accent = dynamic(light: Petrol.p500, dark: Petrol.p400)
        static let accentText = dynamic(light: Petrol.p700, dark: Petrol.p300)
        /// The timeline knob stays white in both appearances.
        static let knob = Color.white
        static let onAccent = dynamic(light: Color.white, dark: Neutral.ink)
        static let warning = Color(hex: 0xEBA941)
        static let destructive = dynamic(light: Color(hex: 0xD9534F), dark: Color(hex: 0xFF6B6B))

        private static func dynamic(light: Color, dark: Color) -> Color {
            let lightColor = NSColor(light)
            let darkColor = NSColor(dark)
            return Color(
                nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
                })
        }
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
        static let card: CGFloat = 24
        static let compactCard: CGFloat = 18
        static let group: CGFloat = 14
        static let segment: CGFloat = 12
        /// The selected segment inside the track's inner padding.
        static let segmentInner: CGFloat = 9
        static let control: CGFloat = 10
        static let button: CGFloat = 11
        static let fileGlyph: CGFloat = 8
    }
    /// Text sizes in points. The panel tokens are the original 11/12/13 pt plus 2; the form tokens are
    /// for form-like text (Settings, Onboarding, captions and hints in the panel).
    enum TextSize {
        static let small: CGFloat = 13
        static let body: CGFloat = 14
        static let title: CGFloat = 15
        static let formBody: CGFloat = 15
        static let formCallout: CGFloat = 14
        static let formCaption: CGFloat = 12
    }
    enum Size {
        static let panelWidth: CGFloat = 380
        static let ring: CGFloat = 40
        /// Trailing padding of a text-only button at the end of a card row, so its text meets the card padding.
        static let textButtonInset: CGFloat = -TK.Space.m + TK.Space.xs
        /// The file icon inside the progress ring.
        static let ringIcon: CGFloat = 28
        static let ringLine: CGFloat = 3.5
        /// The inner stroke of a glass card.
        static let cardStroke: CGFloat = 0.5
        static let fileGlyph: CGFloat = 40
        /// Vertical padding of a list row, and the inner padding of a segmented control's track.
        static let listRowInset: CGFloat = 6
        static let segmentPadding: CGFloat = 3
        /// The small icon inside a list row's progress ring and in a muted row.
        static let listIcon: CGFloat = 22
        /// The tallest the list's scrolling part grows before it scrolls.
        static let listMaxHeight: CGFloat = 340
        /// The Finder icon of a History row.
        static let historyIcon: CGFloat = 28
        /// The round "•••" button on a list row.
        static let rowMenuButton: CGFloat = 24
        /// The round "•••" button in the list footer.
        static let moreButton: CGFloat = 30
        static let timelineDot: CGFloat = 10
        static let timelineKnob: CGFloat = 22
        /// The translucent accent ring around the knob.
        static let timelineKnobHalo: CGFloat = 4
        static let timelineTrackWidth: CGFloat = 4
        /// The Finder icon in the prompt header and the round close button.
        static let promptIcon: CGFloat = 44
        static let closeButton: CGFloat = 24
        /// The auto-hide progress bar under the prompt buttons.
        static let hideBar: CGFloat = 3
        /// A hairline divider between panel sections.
        static let hairline: CGFloat = 1
        static let settingsWindow = CGSize(width: 680, height: 560)
        static let ruleEditor = CGSize(width: 480, height: 400)
        /// Room for the longest value label beside a Settings step slider.
        static let stepSliderLabel: CGFloat = 90
    }
    /// Opacities of decorations that are not colors of their own.
    enum Opacity {
        static let knobHalo = 0.25
        /// A muted row (a file that could not be deleted).
        static let muted = 0.6
    }
    /// The soft shadow under the timeline knob.
    enum Shadow {
        static let knobOpacity = 0.3
        static let knobRadius: CGFloat = 2
        static let knobOffset: CGFloat = 1
    }
    enum Motion {
        static let open = Animation.spring(response: 0.35, dampingFraction: 0.82)
        static let close = Animation.easeIn(duration: 0.22)
        static let select = Animation.spring(response: 0.25, dampingFraction: 0.85)
        static let reduced = Animation.easeInOut(duration: 0.15)
        static let deletedNoticeSeconds: Double = 2.5
        static let ruleNoticeSeconds: Double = 6
        static let urgentThresholdSeconds = 10
        /// How often the prompt's hide bar and caption refresh.
        static let hideTick: Double = 1
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
