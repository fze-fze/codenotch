import SwiftUI

struct UsageAgentPicker: View {
    @Bindable var model: UsageDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose any combination").font(.headline)
            ForEach(UsageAgent.allCases) { agent in
                HStack {
                    Toggle(agent.title, isOn: Binding(
                        get: { model.selectedAgents.contains(agent) },
                        set: { selected in
                            if selected { model.selectedAgents.insert(agent) }
                            else { model.selectedAgents.remove(agent) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    Spacer()
                    if !agent.supportsHistory { Text("Unavailable").foregroundStyle(.secondary) }
                }
            }
            Divider()
            HStack {
                Button("Select all", action: model.selectAll)
                Spacer()
                Button("Clear") { model.selectedAgents = [] }
            }
        }
        .font(PanelFont.row)
        .padding(18)
        .frame(width: 310)
    }
}
