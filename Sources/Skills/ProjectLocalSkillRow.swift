import SwiftUI

struct ProjectLocalSkillRow: View {
    let skill: ProjectSkill

    private var status: String {
        switch skill.state {
        case .conflict(.realItem): return "Project-owned"
        case .conflict(.brokenLink): return "Broken link"
        case .conflict(.foreignLink): return "External link"
        default: return "Project link"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Label(skill.displayName, systemImage: skill.isOwn ? "folder" : "link")
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(status).font(PanelFont.note).foregroundStyle(.secondary)
            Button("Show in Finder", systemImage: "arrow.up.forward.square") {
                NSWorkspace.shared.activateFileViewerSelecting([skill.url])
            }
            .labelStyle(.iconOnly)
        }
        .help(skill.url.path)
    }
}
