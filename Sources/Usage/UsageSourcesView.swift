import SwiftUI

struct UsageSourcesView: View {
    let model: UsageDashboardModel

    var body: some View {
        DisclosureGroup("Local history & coverage") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(UsageAgent.allCases) { agent in
                    HStack {
                        Text(agent.title).frame(width: 110, alignment: .leading)
                        if agent.supportsHistory {
                            Text(model.sourceFiles[agent, default: 0] > 0
                                 ? "\(model.sourceFiles[agent, default: 0]) local log files"
                                 : "No local logs found")
                        } else {
                            Text("Token history unavailable from this agent’s local data")
                        }
                    }
                }
                Divider()
                Text("Codex sessions and archives, Claude Code projects (including subagents), and Gemini CLI chats are read locally. Imported token metadata is kept across log deletion and rotation. Prompts and responses are never saved by Usage.")
                Text("Lifetime covers all imported local history, across accounts on this Mac. It cannot recover logs deleted before the first import. Gemini CLI and Antigravity are separate sources.")
            }
            .font(PanelFont.note)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
    }
}
