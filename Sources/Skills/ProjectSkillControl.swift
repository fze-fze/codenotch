import SwiftUI

/// Shared by both directions of the skill ↔ project relationship.
struct ProjectSkillControl: View {
    let project: SkillProject
    let skill: StoredSkill
    @ObservedObject var model: SkillManagerModel

    private var reach: SkillManagerModel.ProjectReach { model.reach(of: skill, in: project) }

    var body: some View {
        switch reach {
        case .everywhere:
            Label("Global", systemImage: "globe")
                .font(PanelFont.note)
                .foregroundStyle(.secondary)
                .help("Inherited from global scope")
        case .linked, .absent:
            // Label hidden: the switch already says on or off, and the words
            // for it changed with the state ("Add" / "Active") — a caption that
            // moves under the pointer is harder to read than no caption.
            Toggle("", isOn: Binding(
                get: { reach == .linked },
                set: { model.setLinked($0, skill: skill.name, in: project) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Use \(skill.displayName) in \(project.name)")
        case .blocked:
            Button("Reveal conflict", systemImage: "exclamationmark.triangle") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    project.url.appendingPathComponent(".agents/skills/\(skill.name)")
                ])
            }
            .controlSize(.small)
        }
    }
}
