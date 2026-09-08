import SwiftUI

struct UsageHeatmapView: View {
    let activity: UsageActivity

    var body: some View {
        GeometryReader { geometry in
            let columns = activity.cells.count / 7
            let size = max(2, (geometry.size.width - 28) / CGFloat(max(1, columns)) - 3)
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    Color.clear.frame(height: 18)
                    ForEach(0..<7) { row in
                        Text(row == 1 ? "M" : row == 3 ? "W" : row == 5 ? "F" : "")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(width: 22, height: size)
                    }
                }
                ForEach(0..<columns, id: \.self) { column in
                    let first = activity.cells[column * 7]
                    VStack(spacing: 3) {
                        Text(Calendar.current.component(.day, from: first.date) <= 7
                             ? first.date.formatted(.dateTime.month(.abbreviated)) : "")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .fixedSize().frame(width: size, height: 18, alignment: .leading)
                        ForEach(activity.cells[(column * 7)..<(column * 7 + 7)]) { cell in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(cell))
                                .frame(width: size, height: size)
                                .help("\(cell.date.formatted(date: .abbreviated, time: .omitted)): \(cell.tokens.formatted()) tokens")
                                .accessibilityLabel(cell.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(cell.tokens.formatted()) tokens")
                                .accessibilityHidden(!cell.isInRange)
                        }
                    }
                }
            }
        }
        .aspectRatio(5.7, contentMode: .fit)
    }

    private func color(_ cell: UsageActivity.Cell) -> Color {
        guard cell.isInRange else { return .clear }
        guard cell.tokens > 0, activity.peak > 0 else { return .primary.opacity(0.07) }
        let level = max(1, ceil(Double(cell.tokens) / Double(activity.peak) * 4))
        return .green.opacity(level / 4)
    }
}
