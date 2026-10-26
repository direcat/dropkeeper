import SwiftUI

/// A slider over a short list of discrete values, with the selected one's label trailing.
struct StepSlider<Value: Hashable>: View {
    let title: LocalizedStringKey
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    init(
        _ title: LocalizedStringKey, values: [Value], selection: Binding<Value>, label: @escaping (Value) -> String
    ) {
        self.title = title
        self.values = values
        self._selection = selection
        self.label = label
    }

    /// Where `value` sits in `values`. An unknown value snaps to the nearest one when the values are numbers,
    /// else to the first.
    nonisolated static func index(of value: Value, in values: [Value]) -> Int {
        if let exact = values.firstIndex(of: value) { return exact }
        guard let target = number(value) else { return 0 }
        let distances = values.map { number($0).map { abs($0 - target) } ?? .infinity }
        return distances.indices.min { distances[$0] < distances[$1] } ?? 0
    }

    private nonisolated static func number(_ value: Value) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init)
    }

    var body: some View {
        let index = Self.index(of: selection, in: values)
        LabeledContent(title) {
            HStack(spacing: TK.Space.m) {
                Slider(
                    value: Binding(
                        get: { Double(index) },
                        set: { newValue in
                            let next = Int(newValue.rounded())
                            if values.indices.contains(next) { selection = values[next] }
                        }),
                    in: 0...Double(max(values.count - 1, 1)), step: 1
                )
                .labelsHidden()
                Text(values.isEmpty ? "" : label(values[index]))
                    .monospacedDigit()
                    .frame(minWidth: TK.Size.stepSliderLabel, alignment: .trailing)
            }
        }
    }
}
