import SwiftUI

struct SkillSheet: View {
    let sheet: SkillsSheet
    @ObservedObject var model: SkillManagerModel
    let close: () -> Void
    @State private var promotedID: String?
    @State private var promotionCandidate: String?

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            HStack {
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .font(PanelFont.row)
        .scrollIndicators(.hidden)
        .frame(width: 540, height: 600)
        .onChange(of: model.isRefreshing) { _, refreshing in
            guard !refreshing, let candidate = promotionCandidate else { return }
            if model.storeSkills.contains(where: { $0.name == candidate }),
               case .agent(let id) = sheet,
               !model.agentSkills.values.flatMap({ $0 }).contains(where: { $0.id == id }) {
                promotedID = candidate
            }
            if promotedID != nil || model.problem != nil { promotionCandidate = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch promotedID.map(SkillsSheet.library) ?? sheet {
        case .library(let id):
            if let skill = model.storeSkills.first(where: { $0.id == id }) {
                LibraryDetailView(skill: skill, model: model, close: close)
            } else {
                gone
            }
        case .agent(let id):
            if let skill = model.agentSkills.values.flatMap({ $0 })
                .first(where: { $0.id == id }) {
                AgentSkillDetailView(skill: skill, model: model) { promotionCandidate = $0 }
            } else {
                gone
            }
        }
    }

    private var gone: some View {
        Text("That skill is no longer there")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
