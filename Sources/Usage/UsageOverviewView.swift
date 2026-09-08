import SwiftUI

struct UsageOverviewView: View {
    let activity: UsageActivity
    let scope: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overview").font(.headline)
                    Text(activity.tokens.formatted(.number.notation(.compactName)))
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("tokens in the last 365 days").font(PanelFont.note).foregroundStyle(.secondary)
                }
                Spacer()
                Text(scope).font(PanelFont.note).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 280, alignment: .trailing)
            }
            UsageHeatmapView(activity: activity)
            Divider()
            HStack(alignment: .top, spacing: 20) {
                UsageOverviewStat(title: "Most active month", value: activity.bestMonth?.formatted(.dateTime.month(.wide).year()) ?? "—")
                UsageOverviewStat(title: "Most active day", value: activity.bestDay?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "—")
                UsageOverviewStat(title: "Longest streak", value: "\(activity.longestStreak)d")
                UsageOverviewStat(title: "Current streak", value: "\(activity.currentStreak)d")
            }
            .help("Statistics cover the last 365 days. Current streak may end today or yesterday.")
            HStack(spacing: 6) {
                Text("Less")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level == 0 ? Color.primary.opacity(0.07) : Color.green.opacity(Double(level) / 4))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                Text("More")
            }
            .font(PanelFont.note).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
    }
}

private struct UsageOverviewStat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(PanelFont.note).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
