import Foundation

/// Disjoint token buckets. Reasoning is already part of output, never added twice.
struct TokenCounts: Codable, Equatable, Sendable {
    var input: Int64 = 0
    var cached: Int64 = 0
    var cacheWrite: Int64 = 0
    var cacheWriteLong: Int64 = 0
    var output: Int64 = 0
    var other: Int64 = 0
    var total: Int64 { input + cached + cacheWrite + cacheWriteLong + output + other }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, cached: lhs.cached + rhs.cached,
             cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
             cacheWriteLong: lhs.cacheWriteLong + rhs.cacheWriteLong,
             output: lhs.output + rhs.output, other: lhs.other + rhs.other)
    }

    func subtracting(_ previous: Self) -> Self {
        Self(input: max(0, input - previous.input), cached: max(0, cached - previous.cached),
             cacheWrite: max(0, cacheWrite - previous.cacheWrite),
             cacheWriteLong: max(0, cacheWriteLong - previous.cacheWriteLong),
             output: max(0, output - previous.output), other: max(0, other - previous.other))
    }

    func merging(_ other: Self) -> Self {
        Self(input: max(input, other.input), cached: max(cached, other.cached),
             cacheWrite: max(cacheWrite, other.cacheWrite),
             cacheWriteLong: max(cacheWriteLong, other.cacheWriteLong),
             output: max(output, other.output), other: max(self.other, other.other))
    }
}
