import SwiftUI

struct UsageDetailsView: View {
    let summary: UsageSummary
    let series: UsageSeries
    @Binding var grouping: UsageGrouping

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                UsageMetricCard(title: "Total tokens", value: summary.tokens.total.formatted(.number.notation(.compactName)),
                    subtitle: "\(summary.sessions.formatted()) sessions · \(summary.activeDays) active days", symbol: "number")
                    .help("\(summary.tokens.total.formatted()) tokens")
                UsageMetricCard(title: "Estimated cost", value: summary.costLabel,
                    subtitle: summary.unpriced > 0 ? "USD · \(summary.unpriced.formatted()) unpriced records" : "USD · API equivalent", symbol: "dollarsign.circle")
                UsageMetricCard(title: "Cache hit rate", value: summary.cacheShare.formatted(.percent.precision(.fractionLength(1))),
                    subtitle: "\(summary.tokens.cached.formatted(.number.notation(.compactName))) cached input tokens", symbol: "arrow.trianglehead.2.clockwise.rotate.90")
            }
            UsageTrendView(series: series, grouping: $grouping)
            DisclosureGroup("Token details by model") {
                UsageModelBreakdown(summary: summary).padding(.top, 12)
                if summary.tokens.other > 0 {
                    Text("Other reported tokens: \(summary.tokens.other.formatted()). Included in totals; cost unavailable for affected records.")
                        .font(PanelFont.note).foregroundStyle(.secondary)
                }
            }
        }
    }
}
