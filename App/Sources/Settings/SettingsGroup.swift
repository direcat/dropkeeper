import DropKeeperCore
import SwiftUI

/// A Settings group: a small header above a rounded card whose rows are separated by hairlines, and an optional
/// footnote under the card. Rows are at least 44 pt tall; see `SettingsRow`.
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: Text?
    let content: Content

    init(
        _ title: LocalizedStringKey, footer: Text? = nil, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    /// A group without a header.
    init(footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = nil
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TK.Space.s - TK.Space.xs / 2) {
            if let title {
                Text(title)
                    .font(.system(size: TK.TextSize.formCaption, weight: .semibold))
                    .foregroundStyle(TK.Palette.textSecondary)
                    .padding(.horizontal, TK.Space.xs)
                    .accessibilityAddTraits(.isHeader)
            }
            card
            if let footer {
                footer
                    .font(.system(size: TK.TextSize.formCaption))
                    .foregroundStyle(TK.Palette.textSecondary)
                    .padding(.horizontal, TK.Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: TK.Radius.group, style: .continuous)
        return VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id {
                        Rectangle().fill(TK.Palette.hairline).frame(height: TK.Size.separator)
                    }
                }
            }
        }
        .padding(.horizontal, TK.Size.settingsGroupInset)
        .background(TK.Palette.group, in: shape)
        .overlay { shape.strokeBorder(TK.Palette.hairline, lineWidth: TK.Size.cardStroke) }
    }
}

/// One row of a group: the title with an optional caption under it, and the control on the right.
struct SettingsRow<Title: View, Control: View>: View {
    let title: Title
    let caption: LocalizedStringKey?
    let control: Control

    init(
        caption: LocalizedStringKey? = nil, @ViewBuilder title: () -> Title, @ViewBuilder control: () -> Control
    ) {
        self.title = title()
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: TK.Space.xl) {
            VStack(alignment: .leading, spacing: TK.Space.xs / 2) {
                title.font(.system(size: TK.TextSize.formBody))
                if let caption {
                    Text(caption)
                        .font(.system(size: TK.TextSize.formCaption))
                        .foregroundStyle(TK.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, TK.Size.settingsRowInset)
        .frame(minHeight: TK.Size.settingsRow)
    }
}

extension SettingsRow where Title == Text {
    init(_ title: LocalizedStringKey, caption: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.init(caption: caption, title: { Text(title) }, control: control)
    }
}

/// A row that is one text button, in the accent color.
struct SettingsButtonRow: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Button(action: action) {
                Text(title)
                    .font(.system(size: TK.TextSize.formBody))
                    .foregroundStyle(isEnabled ? TK.Palette.accentText : TK.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.vertical, TK.Size.settingsRowInset)
        .frame(minHeight: TK.Size.settingsRow)
    }
}

extension Text {
    /// The small secondary text under a row's title.
    func settingsCaption() -> some View {
        font(.system(size: TK.TextSize.formCaption)).foregroundStyle(TK.Palette.textSecondary)
    }
}

/// A row with a switch on the right.
struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, caption: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title, caption: caption) {
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A small segmented control for a Settings row: a soft track with a raised selected segment.
struct SettingsSegmented<Value: Hashable>: View {
    let label: LocalizedStringKey
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                segment(value)
            }
        }
        .padding(TK.Size.miniSegmentPadding)
        .background(
            TK.Palette.fillStrong, in: RoundedRectangle(cornerRadius: TK.Radius.miniSegment, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }

    private func segment(_ value: Value) -> some View {
        let selected = selection == value
        return Button {
            withAnimation(reduceMotion ? nil : TK.Motion.select) { selection = value }
        } label: {
            Text(verbatim: title(value))
                .font(.system(size: TK.TextSize.formCaption, weight: .medium))
                .foregroundStyle(selected ? TK.Palette.textPrimary : TK.Palette.textSecondary)
                .padding(.horizontal, TK.Space.m)
                .padding(.vertical, TK.Size.miniSegmentInset)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: TK.Radius.miniSegmentInner, style: .continuous)
                            .fill(TK.Palette.segmentOn)
                            .shadow(
                                color: .black.opacity(TK.Shadow.knobOpacity / 2), radius: TK.Shadow.knobRadius / 2,
                                y: TK.Shadow.knobOffset)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The names of the Appearance setting's values.
enum AppearanceLabel {
    static func title(_ appearance: Appearance) -> String {
        switch appearance {
        case .auto: String(localized: "Auto", comment: "Appearance setting: follow the system's Light or Dark")
        case .light: String(localized: "Light", comment: "Appearance setting: always light")
        case .dark: String(localized: "Dark", comment: "Appearance setting: always dark")
        }
    }
}
