import SwiftUI

/// The same key/color mapping is used for the chart and the detailed legend.
struct UsageCategoryLegend: View {
    let series: UsageSeries
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Category").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tokens").frame(width: 100, alignment: .trailing)
                Text("Share").frame(width: 65, alignment: .trailing)
                Text("Est. USD").frame(width: 95, alignment: .trailing)
            }
            .font(PanelFont.note).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(series.categories) { category in
                Divider()
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UsageChartColors.color(category.id, in: series.domain))
                        .frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(category.id).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Text(category.tokens.formatted(.number.notation(.compactName)))
                        .frame(width: 100, alignment: .trailing)
                        .help(category.tokens.formatted())
                    Text((Double(category.tokens) / Double(max(1, series.categories.reduce(Int64(0)) { $0 + $1.tokens }))).formatted(.percent.precision(.fractionLength(1))))
                        .frame(width: 65, alignment: .trailing)
                    Text(category.unpriced == category.count ? "—" : category.cost.formatted(.currency(code: "USD")) + (category.unpriced > 0 ? "+" : ""))
                        .frame(width: 95, alignment: .trailing)
                }
                .font(PanelFont.note).monospacedDigit().padding(.vertical, 10)
            }
        }
    }
}
