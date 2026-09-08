import SwiftUI

struct AgentCard: View {
    let skill: AgentSkill
    @ObservedObject var model: SkillManagerModel
    let filterTag: (String) -> Void
    let open: () -> Void

    var body: some View {
        SkillCard(title: skill.displayName, symbol: "person.crop.square",
                  summary: skill.summary,
                  tags: model.tags(for: skill.name, declared: skill.frontmatter.tags),
                  filterTag: filterTag, open: open) {
            HStack(spacing: 5) {
                ProviderGlyphView(glyph: skill.agent.glyph, size: 13).accessibilityHidden(true)
                Text(skill.agent.displayName).lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(skill.collidesWithLibrary ? "Name conflict" : "Add to Library", action: open)
                .controlSize(.small)
                .help("Review this skill before adding it to Library")
        }
    }
}
