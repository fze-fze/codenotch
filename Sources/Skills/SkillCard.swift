import SwiftUI

/// A keyboard-accessible details button, with tags and scope controls alongside it.
struct SkillCard<Footer: View>: View {
    let title: String
    let symbol: String
    let summary: String?
    let tags: [String]
    let filterTag: (String) -> Void
    let open: () -> Void
    @ViewBuilder let footer: Footer
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Image(systemName: symbol).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(summary ?? "No description")
                        .font(PanelFont.note)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), details")
            HStack(spacing: 4) {
                ForEach(tags.prefix(2), id: \.self) { tag in
                    Button { filterTag(tag) } label: { TagChip(tag: tag) }
                        .buttonStyle(.plain)
                        .help("Filter by #\(tag)")
                        .accessibilityLabel("Filter by tag \(tag)")
                }
                if tags.count > 2 {
                    Button("+\(tags.count - 2)", action: open)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Show all \(tags.count) tags")
                }
                if tags.isEmpty {
                    Button("Add tags", systemImage: "plus", action: open)
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 24)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Divider()
            HStack(spacing: 8) { footer }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .background(.primary.opacity(hovering ? 0.055 : 0.03), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(hovering ? 0.15 : 0.08)) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}
