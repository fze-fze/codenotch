import SwiftUI
import Charts

struct UsageTrendView: View {
    let series: UsageSeries
    @Binding var grouping: UsageGrouping

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your usage").font(.headline)
                    Text("Cumulative tokens across the selected period")
                        .font(PanelFont.note).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Group by", selection: $grouping) {
                    ForEach(UsageGrouping.allCases) { group in Text(group.rawValue).tag(group) }
                }
                .frame(width: 190)
            }
            Chart(series.points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Cumulative tokens", point.total), stacking: .standard)
                    .foregroundStyle(by: .value("Category", point.group))
                    .interpolationMethod(.linear)
                    .opacity(0.65)
                    .accessibilityLabel("\(point.group), through \(point.date.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityValue("\(point.total.formatted()) tokens")
            }
            .chartForegroundStyleScale(domain: series.domain, range: series.domain.map { UsageChartColors.color($0, in: series.domain) })
            .chartLegend(.hidden)
            .chartXScale(domain: series.start...series.end)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int64.self) { Text(tokens.formatted(.number.notation(.compactName))) }
                    }
                }
            }
            .frame(height: 220)
            UsageCategoryLegend(series: series)
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
    }
}
