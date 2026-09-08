import SwiftUI

struct TagChip: View {
    let tag: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colour)
                .frame(width: 5, height: 5)
            Text(tag)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(tag)")
            }
        }
        .font(.system(size: 12))
        .help(tag)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(Color.primary.opacity(0.06))
        }
    }

    private var colour: Color { SkillTags.colour(for: tag) }
}
