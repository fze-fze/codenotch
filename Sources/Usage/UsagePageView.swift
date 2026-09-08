import SwiftUI

struct UsagePageView: View {
    @State private var model = UsageDashboardModel()
    @State private var showPrices = false
    @State private var refreshID = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage").font(PanelFont.title)
                    Text("Token activity on this Mac").font(PanelFont.note).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small).accessibilityLabel("Reading local history") }
                if let updated = model.updatedAt {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(PanelFont.note).foregroundStyle(.secondary)
                }
                Button("Model prices", systemImage: "dollarsign.circle") { showPrices = true }
                Button("Refresh usage", systemImage: "arrow.clockwise") { refreshID += 1 }
                    .labelStyle(.iconOnly).disabled(model.isRefreshing)
            }
            .controlSize(.small)
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 14) {
                        UsageMetricCard(title: "Lifetime tokens", value: model.loaded ? model.lifetime.tokens.total.formatted() : "—",
                            subtitle: "All agents · All recorded history", symbol: "number")
                        UsageMetricCard(title: "Lifetime cost (USD)", value: model.loaded ? model.lifetime.costLabel : "—",
                            subtitle: model.lifetime.unpriced > 0 ? "API estimate · \(model.lifetime.unpriced.formatted()) unpriced records" : "Estimated API equivalent · All agents", symbol: "dollarsign.circle")
                    }
                    if model.loaded {
                        UsageOverviewView(activity: model.activity, scope: model.selectionTitle)
                    }
                    UsageFilterBar(model: model)
                    Divider()
                    if !model.loaded {
                        ContentUnavailableView("Reading local history…", systemImage: "clock",
                            description: Text("The first import can take a moment. Later refreshes read only changed files."))
                    } else if model.filtered.recordCount == 0 {
                        ContentUnavailableView("No usage in this selection", systemImage: "chart.bar.xaxis",
                            description: Text("Choose other agents or a wider time range. Check local history coverage below for unavailable sources."))
                    } else {
                        UsageDetailsView(summary: model.filtered, series: model.series, grouping: $model.grouping)
                    }
                    ForEach(model.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(PanelFont.note).foregroundStyle(.secondary)
                    }
                    if let problem = model.pricingProblem {
                        Label(problem, systemImage: "exclamationmark.triangle").font(PanelFont.note)
                    }
                    Text("Costs are estimates at standard short-context text rates, not subscription charges. Unpriced records remain in token totals. Set custom rates in Model prices.")
                        .font(PanelFont.note).foregroundStyle(.secondary)
                    UsageSourcesView(model: model)
                }
                .padding(20)
            }
            .background(.quaternary.opacity(0.3))
        }
        .font(PanelFont.row)
        .sheet(isPresented: $showPrices) { UsagePricingSheet(model: model) }
        .task(id: refreshID) {
            repeat {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            } while !Task.isCancelled
        }
    }
}
