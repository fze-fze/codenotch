import SwiftUI
import XCTest
@testable import Codenotch

@MainActor
final class UsageRenderTests: XCTestCase {
    func testDashboardFitsMinimumWindowWidthInBothAppearances() throws {
        let now = Date(timeIntervalSince1970: 1_788_864_000)
        let records = (0..<7).flatMap { day in
            ["gpt-6-astra", "claude-opus-5", "gemini-2.5-flash"].enumerated().map { index, name in
                TokenUsageRecord(id: "\(day)-\(name)", agent: [.codex, .claudeCode, .gemini][index],
                    session: "\(day)-\(index)", timestamp: now.addingTimeInterval(Double(-day) * 86_400),
                    model: name, tokens: TokenCounts(input: Int64(10_000 + day * 6_000),
                        cached: 80_000, cacheWrite: index == 1 ? 10_000 : 0, output: 5_000))
            }
        }
        let summary = UsageSummary(records: records, prices: UsagePricing.defaults)
        for (scheme, grouping) in [(ColorScheme.light, UsageGrouping.model), (.dark, .model), (.light, .agent), (.dark, .agent)] {
            let content = VStack(alignment: .leading, spacing: 22) {
                Text("Usage").font(PanelFont.title)
                HStack(spacing: 14) {
                    UsageMetricCard(title: "Lifetime tokens", value: summary.tokens.total.formatted(),
                                    subtitle: "All agents · All recorded history", symbol: "number")
                    UsageMetricCard(title: "Lifetime cost (USD)", value: summary.costLabel,
                                    subtitle: "API estimate · 7 unpriced records", symbol: "dollarsign.circle")
                }
                UsageOverviewView(activity: UsageActivity(days: summary.days, now: now), scope: "All agents")
                Text("Explore usage · Codex + Claude Code + Gemini · Last 7d").font(.headline)
                UsageDetailsView(summary: summary, series: UsageSeries(records: records,
                    grouping: grouping, period: .week, now: now, prices: UsagePricing.defaults,
                    domain: records.map { grouping.key(for: $0) }.sorted().reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }), grouping: .constant(grouping))
            }
            .font(PanelFont.row)
            .padding(20)
            .frame(width: 820)
            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 820)
            XCTAssertGreaterThan(image.size.height, 500)
            XCTAssertLessThan(image.size.height, 1700)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/codenotch-usage-\(scheme == .dark ? "dark" : "light")-\(grouping.rawValue.lowercased()).png"))
        }
    }
}
