import SwiftUI

struct LibraryCard: View {
    let skill: StoredSkill
    @ObservedObject var model: SkillManagerModel
    let filterTag: (String) -> Void
    let open: () -> Void

    private var linkedProjects: [SkillProject] {
        let ids = Set(model.projectsUsing(skill.name))
        return model.projects.filter { ids.contains($0.id) }
    }

    private var scopeLabel: String {
        if skill.isGlobal { return "Global" }
        guard let first = linkedProjects.first else { return "No shared scope" }
        return linkedProjects.count == 1 ? first.name : "\(linkedProjects.count) projects"
    }

    var body: some View {
        SkillCard(title: skill.displayName, symbol: "square.stack.3d.up",
                  summary: skill.summary,
                  tags: model.tags(for: skill.name, declared: skill.frontmatter.tags),
                  filterTag: filterTag, open: open) {
            Button(action: open) {
                Label(scopeLabel, systemImage: skill.isGlobal ? "globe" : linkedProjects.isEmpty ? "minus.circle" : "folder")
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundStyle(skill.isGlobal || !linkedProjects.isEmpty ? Color.accentColor : .secondary)
            .help(linkedProjects.isEmpty ? "Manage global and project scope" : linkedProjects.map(\.name).joined(separator: ", "))
            Spacer(minLength: 0)
            Toggle("Global", isOn: Binding(
                get: { skill.isGlobal },
                set: { model.setGlobal($0, skill: skill.name) }
            ))
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .accessibilityLabel("Use \(skill.displayName) globally")
        }
    }
}
