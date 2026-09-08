import SwiftUI

struct ProjectRow: View {
    let project: SkillProject
    @ObservedObject var model: SkillManagerModel
    @State private var pickingMark = false

    var body: some View {
        HStack(spacing: 6) {
            ProjectMarkView(mark: project.mark, size: 14)
            Text(project.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            if needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Not every agent here reads the same thing")
            }
            let count = model.projectSkills[project.id]?.count ?? 0
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .help("\(count) project entries")
            }
        }
        .padding(.vertical, 3)
        .popover(isPresented: $pickingMark, arrowEdge: .trailing) {
            ProjectMarkPicker(mark: project.mark) { model.setMark($0, project: project) }
        }
        .contextMenu {
            Button(project.isPinned ? "Unpin" : "Pin") {
                model.setPinned(!project.isPinned, project: project)
            }
            Button("Icon & Colour…") { pickingMark = true }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            }
            Divider()
            Button("Forget") { model.forgetProject(project) }
        }
    }

    /// Something here is half-done — skills its agents cannot all see, or
    /// instructions only one of them reads.
    private var needsAttention: Bool {
        let hasSkills = !(model.projectSkills[project.id] ?? []).isEmpty
        let bridged = model.projectBridges[project.id] == .linked
        let instructions = model.projectInstructions[project.id] ?? .none
        return (hasSkills && !bridged) || instructions == .absent
            || instructions == .claudeOnly || instructions == .divergent
    }
}
