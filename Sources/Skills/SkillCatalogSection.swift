import SwiftUI

struct SkillCatalogSection<Content: View>: View {
    let title: String
    let subtitle: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                Text(subtitle).font(PanelFont.note).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)],
                      alignment: .leading, spacing: 12) {
                content
            }
        }
    }
}
