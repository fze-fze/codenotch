import SwiftUI

struct UsageModelBreakdown: View {
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By model").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Model")
                    Text("Input")
                    Text("Cache¹")
                    Text("Output")
                    Text("Total")
                    Text("Est. USD")
                }
                .font(PanelFont.note)
                .foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(summary.models) { row in
                    GridRow(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.id).font(PanelFont.monoRow).textSelection(.enabled)
                            Text(row.agents).font(PanelFont.note).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.tokens.input.formatted(.number.notation(.compactName)))
                        Text((row.tokens.cached + row.tokens.cacheWrite + row.tokens.cacheWriteLong).formatted(.number.notation(.compactName)))
                        Text(row.tokens.output.formatted(.number.notation(.compactName)))
                        Text(row.tokens.total.formatted(.number.notation(.compactName))).fontWeight(.semibold)
                        Text(row.unpriced == row.records ? "—" : row.cost.formatted(.currency(code: "USD")) + (row.unpriced > 0 ? "+" : ""))
                    }
                    .monospacedDigit()
                    .help("\(row.tokens.total.formatted()) tokens · \(row.records.formatted()) usage records · \(row.unpriced) unpriced")
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
            }
            Text("¹ Cache includes reads and writes. Output includes reasoning. + indicates a partial cost; — indicates missing prices.")
                .font(PanelFont.note).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background, in: .rect(cornerRadius: 12))
    }
}
