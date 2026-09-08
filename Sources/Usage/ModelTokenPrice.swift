import Foundation

/// USD per million tokens, standard API equivalent, not a subscription bill.
struct ModelTokenPrice: Codable, Equatable, Sendable {
    var input: Double
    var cached: Double
    var output: Double
    var cacheWrite: Double
    var cacheWriteLong: Double

    init(input: Double = 0, cached: Double = 0, output: Double = 0,
         cacheWrite: Double = 0, cacheWriteLong: Double = 0) {
        self.input = input
        self.cached = cached
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheWriteLong = cacheWriteLong
    }

    var isValid: Bool {
        [input, cached, output, cacheWrite, cacheWriteLong].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }
    }
    func cost(_ tokens: TokenCounts) -> Double? {
        guard isValid, tokens.other == 0 else { return nil }
        return (Double(tokens.input) * input + Double(tokens.cached) * cached
            + Double(tokens.output) * output + Double(tokens.cacheWrite) * cacheWrite
            + Double(tokens.cacheWriteLong) * cacheWriteLong) / 1_000_000
    }
}
