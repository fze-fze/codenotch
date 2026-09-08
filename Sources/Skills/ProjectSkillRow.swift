import SwiftUI

struct ProjectSkillRow: View {
    let project: SkillProject
    let skill: StoredSkill
    @ObservedObject var model: SkillManagerModel
    let open: () -> Void

    private var state: MountState {
        (model.projectSkills[project.id] ?? []).first { $0.name == skill.name }?.state ?? .notMounted
    }

    private var note: String? {
        switch state {
        case .conflict(.realItem): return "Project-owned skill takes precedence"
        case .conflict(.foreignLink): return "A local link points to another skill"
        case .conflict(.brokenLink): return "Broken project link"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.displayName).lineLimit(1).truncationMode(.middle)
                    if let note {
                        Text(note).font(PanelFont.note).foregroundStyle(.orange)
                    } else if let summary = skill.summary {
                        Text(summary).font(PanelFont.note).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(skill.displayName), details")
            ProjectSkillControl(project: project, skill: skill, model: model)
        }
        .padding(.vertical, 3)
    }
}
