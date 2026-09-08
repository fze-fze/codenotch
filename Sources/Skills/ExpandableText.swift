import SwiftUI

/// A block of text clamped to a few lines, with a **More** that appears only
/// when there is more.
///
/// The first version guessed from the character count, and the guess was wrong
/// in the way that matters: a description of 290 characters is over the
/// threshold and still fits in three lines at this width, so the button
/// appeared, was pressed, and nothing happened. A control that does nothing is
/// worse than no control — it is the one thing a user cannot debug.
///
/// So it measures. Two invisible copies of the same text at the same width, one
/// unlimited and one clamped, and the button exists exactly when their heights
/// differ. That is the only honest test of "there is more to show", and it
/// survives every width, font size and translation without a threshold to tune.
struct ExpandableText: View {
    let text: String
    var limit: Int = 3

    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0

    /// Half a point of slack: the two measurements are the same layout with
    /// the same font, so they agree exactly or differ by a whole line.
    private var isTruncated: Bool { fullHeight > clampedHeight + 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(expanded ? nil : limit)
                .background(alignment: .topLeading) { probes }

            if isTruncated {
                Button(expanded ? "Less" : "More") {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.link)
            }
        }
    }

    /// Both copies are laid out inside the visible text's background, so they
    /// are proposed the same width it has — which is the whole point. Measuring
    /// at any other width would answer a different question.
    private var probes: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .background(HeightReader(key: FullHeight.self))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(limit)
                .background(HeightReader(key: ClampedHeight.self))
        }
        .hidden()
        .allowsHitTesting(false)
        .onPreferenceChange(FullHeight.self) { fullHeight = $0 }
        .onPreferenceChange(ClampedHeight.self) { clampedHeight = $0 }
    }
}

/// Publishes the height of whatever it is put behind.
private struct HeightReader<Key: PreferenceKey>: View where Key.Value == CGFloat {
    let key: Key.Type

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: Key.self, value: proxy.size.height)
        }
    }
}

private struct FullHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ClampedHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
