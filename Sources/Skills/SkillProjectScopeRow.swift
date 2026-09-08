import SwiftUI

struct SkillProjectScopeRow: View {
    let project: SkillProject
    let skill: StoredSkill
    @ObservedObject var model: SkillManagerModel

    var body: some View {
        HStack(spacing: 10) {
            ProjectMarkView(mark: project.mark, size: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).lineLimit(1)
                Text(project.displayPath(home: model.home))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if case .blocked = model.reach(of: skill, in: project) {
                    Text("A local item takes precedence")
                        .font(PanelFont.note).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            ProjectSkillControl(project: project, skill: skill, model: model)
        }
        .padding(.vertical, 2)
    }
}
