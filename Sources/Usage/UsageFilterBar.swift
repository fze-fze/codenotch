import SwiftUI

struct UsageFilterBar: View {
    @Bindable var model: UsageDashboardModel
    @State private var choosingAgents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Explore usage").font(.headline)
                Spacer()
                Picker("Time range", selection: $model.period) {
                    ForEach(UsagePeriod.allCases) { period in Text(period.rawValue).tag(period) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .help("Rolling 24 hours, 7 days, 30 days, or all recorded history")
            }
            HStack(spacing: 8) {
                Button(action: model.selectAll) {
                    Label("All agents", systemImage: model.allSelected ? "checkmark.circle.fill" : "circle")
                }
                .tint(model.allSelected ? Color.accentColor : Color.secondary)
                ForEach(UsageAgent.allCases.filter(\.supportsHistory)) { agent in
                    Button { model.selectedAgents = [agent] } label: {
                        Text(agent.title)
                    }
                    .tint(model.selectedAgents == [agent] ? Color.accentColor : Color.secondary)
                    .accessibilityValue(model.selectedAgents == [agent] ? "Selected" : "Not selected")
                    .help("Show only \(agent.title); use Choose agents to combine sources")
                }
                Button("Choose agents", systemImage: "line.3.horizontal.decrease") { choosingAgents = true }
                    .popover(isPresented: $choosingAgents) {
                        UsageAgentPicker(model: model)
                    }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text(model.selectionTitle + " · " + (model.period == .all ? "All recorded history" : "Last \(model.period.rawValue)"))
                .font(PanelFont.note)
                .foregroundStyle(.secondary)
        }
    }
}
