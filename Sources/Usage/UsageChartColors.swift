import SwiftUI

enum UsageChartColors {
    static let palette: [Color] = [
        Color(red: 0.25, green: 0.59, blue: 0.47),
        Color(red: 0.39, green: 0.52, blue: 0.68),
        Color(red: 0.68, green: 0.52, blue: 0.65),
        Color(red: 0.77, green: 0.61, blue: 0.35),
        Color(red: 0.74, green: 0.44, blue: 0.40),
        Color(red: 0.47, green: 0.48, blue: 0.68),
        Color(red: 0.57, green: 0.66, blue: 0.47),
        Color(red: 0.62, green: 0.52, blue: 0.42),
        Color(red: 0.40, green: 0.65, blue: 0.68),
        Color(red: 0.72, green: 0.42, blue: 0.51)
    ]
    static func color(_ key: String, in domain: [String]) -> Color {
        palette[(domain.firstIndex(of: key) ?? 0) % palette.count]
    }
}
