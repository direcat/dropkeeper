import SwiftUI

// DropKeeper design tokens (see the design manual).
// The short names (`TK`, `Space.xs` … `Space.xl`) are the design manual's token names.
// swiftlint:disable:next type_name
enum TK {
    enum Petrol {
        static let p300 = Color(hex: 0xA3DDE0)
        static let p400 = Color(hex: 0x6AC2C6)
        static let p500 = Color(hex: 0x39A4A9)
        static let p700 = Color(hex: 0x0C6468)
    }
    enum Neutral {
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
        static let cardEdge = dynamic(light: Color.white.opacity(0.7), dark: Color.white.opacity(0.2))
        /// The rounded card behind a Settings group.
        static let group = dynamic(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.07))
        static let cardTint = dynamic(
            light: Color(hex: 0xF4F1EF).opacity(0.50), dark: Color(hex: 0x26262A).opacity(0.45))
        /// The selected segment of a segmented control.
        static let segmentOn = dynamic(light: Color.white, dark: Color.white.opacity(0.18))
        static let accent = dynamic(light: Petrol.p500, dark: Petrol.p400)
        static let accentText = dynamic(light: Petrol.p700, dark: Petrol.p300)
        /// The timeline knob stays white in both appearances.
        static let knob = Color.white
        static let onAccent = dynamic(light: Color.white, dark: Neutral.ink)
        static let warning = Color(hex: 0xEBA941)
        /// The ring's stops, from plenty of time to none: green, the amber warning above, and `destructive` as the red.
        static let ringGreen = dynamic(light: Color(hex: 0x2FB350), dark: Color(hex: 0x34C759))
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
        /// A Settings tab's selected background, and the small segmented control in a Settings row with its
        /// selected segment.
        static let tab: CGFloat = 8
        static let miniSegment: CGFloat = 8
        static let miniSegmentInner: CGFloat = 6
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
        /// The label under a Settings tab's icon.
        static let tabLabel: CGFloat = 11
    }
    enum Size {
        static let panelWidth: CGFloat = 380
        static let ring: CGFloat = 40
        /// Trailing padding of a text-only button at the end of a card row, so its text meets the card padding.
        static let textButtonInset: CGFloat = -TK.Space.m + TK.Space.xs
        /// The file icon inside the progress ring.
        static let ringIcon: CGFloat = 28
        static let ringLine: CGFloat = 2.5
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
        /// The divider between the prompt and reminder sections. The glass cards are drawn over a translucent
        /// material where a 0.5 pt line vanishes, so they keep a full point; Settings sits on an opaque window
        /// background and uses the finer `separator`.
        static let hairline: CGFloat = 1
        /// The divider between Settings rows and under the tab bar.
        static let separator: CGFloat = 0.5
        static let settingsWindow = CGSize(width: 680, height: 560)
        static let ruleEditor = CGSize(width: 480, height: 400)
        /// Room for the longest value label beside a Settings step slider, and the slider itself.
        static let stepSliderLabel: CGFloat = 90
        static let stepSliderWidth: CGFloat = 180
        /// A Settings row's minimum height and its vertical padding.
        static let settingsRow: CGFloat = 44
        static let settingsRowInset: CGFloat = 10
        /// Padding inside a Settings group card (sides) and around the scrolling content (sides, top).
        static let settingsGroupInset: CGFloat = 18
        static let settingsContentSide: CGFloat = 28
        static let settingsContentTop: CGFloat = 18
        /// The tab bar's icon, and its padding above the labels.
        static let tabIcon: CGFloat = 18
        static let tabInset: CGFloat = 5
        /// Inner padding of the Settings segmented control's track, and the room for a Settings picker.
        static let miniSegmentPadding: CGFloat = 2
        /// Vertical padding of a segment in the Settings segmented control.
        static let miniSegmentInset: CGFloat = 3
        static let settingsPicker: CGFloat = 170
        /// The wordmark in the About tab.
        static let lockup: CGFloat = 28
        /// The Statistics values' column.
        static let statisticsValue: CGFloat = 120
        /// The onboarding window's width, its wordmark, illustration and permission glyph.
        static let onboardingWidth: CGFloat = 560
        static let onboardingLockup: CGFloat = 32
        static let onboardingArt = CGSize(width: 320, height: 160)
        static let onboardingPermission: CGFloat = 64
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
        static let select = Animation.spring(response: 0.25, dampingFraction: 0.85)
        static let reduced = Animation.easeInOut(duration: 0.15)
        static let deletedNoticeSeconds: Double = 2.5
        static let ruleNoticeSeconds: Double = 6
        /// How often the prompt's hide bar and caption refresh.
        static let hideTick: Double = 1
        /// The ring runs down in steps of at most this many points of arc, but redraws no faster than
        /// `ringFastestTick` (short timers) and no slower than `ringSlowestTick` (long timers).
        static let ringStepPoints: CGFloat = 0.5
        static let ringFastestTick: Double = 1.0 / 30
        static let ringSlowestTick: Double = 10
        /// With Reduce Motion the ring only updates this often.
        static let ringReducedTick: Double = 1
        /// The panel's measured height is not trusted below this (an empty view's stale measurement).
        static let panelMinMeasuredHeight: CGFloat = 40
        /// A panel slides down this far into place when it appears, over `panelSlideDuration`, while it fades in.
        static let panelSlideOffset: CGFloat = 18
        static let panelSlideDuration: Double = 0.28
        static let panelReducedFadeDuration: Double = 0.15
        static let panelFadeOutDuration: Double = 0.22
        /// A visible panel that changes size follows its new frame over this long.
        static let panelResizeDuration: Double = 0.3
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
