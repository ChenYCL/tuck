import SwiftUI

/// A labeled row pairing a title with a native `ColorPicker`, bridging `CodableColor`
/// to SwiftUI's `Color`.
struct ColorRow: View {
    private let title: LocalizedStringKey
    @Binding private var color: CodableColor
    private let supportsOpacity: Bool

    init(_ title: LocalizedStringKey, color: Binding<CodableColor>, supportsOpacity: Bool) {
        self.title = title
        self._color = color
        self.supportsOpacity = supportsOpacity
    }

    var body: some View {
        LabeledContent(title) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(nsColor: color.nsColor) },
                    set: { color = CodableColor(NSColor($0)) }
                ),
                supportsOpacity: supportsOpacity
            )
            .labelsHidden()
        }
    }
}
