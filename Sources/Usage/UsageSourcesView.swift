import SwiftUI

struct UsageSourcesView: View {
    let model: UsageDashboardModel

    /// Before the first scan there is nothing to report, and rendering the
    /// empty statuses would briefly claim every agent is uninstalled.
    private var sources: [UsageSourceStatus] {
        model.sources.isEmpty ? UsageAgent.allCases.map { UsageSourceStatus(agent: $0) } : model.sources
    }

    var body: some View {
        DisclosureGroup("Local history & coverage") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sources) { source in
                    row(source)
                }
                Divider()
                Text("Antigravity is read from its conversation databases, where Google's own per-generation accounting is stored. It is counted separately from Gemini CLI, which is a different program with its own logs — an empty Gemini CLI row does not mean Antigravity was missed.")
                Text("Imported token metadata is kept across log deletion and rotation. Prompts and responses are never saved by Usage. Lifetime covers all imported local history, across accounts on this Mac; it cannot recover logs deleted before the first import.")
            }
            .font(PanelFont.note)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func row(_ source: UsageSourceStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(source.agent.title)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.summary)
                    .foregroundStyle(source.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                if let detail = source.detail {
                    Text(detail)
                        .font(PanelFont.note.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
