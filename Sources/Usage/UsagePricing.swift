import Foundation

enum UsagePricing {
    /// Reference rates checked 2026-09-08. Deliberately exact model IDs: no guessed family pricing.
    /// Standard short-context text rates; premiums, tools, storage, and subscription fees are excluded.
    static let defaults: [String: ModelTokenPrice] = [
        "gpt-6-astra": .init(input: 10, cached: 1, output: 50, cacheWrite: 12.5),
        "gpt-5.6-sol": .init(input: 4, cached: 0.4, output: 20, cacheWrite: 5),
        "gpt-5.6-terra": .init(input: 2, cached: 0.2, output: 12, cacheWrite: 2.5),
        "gpt-5.6-luna": .init(input: 0.2, cached: 0.02, output: 1.2, cacheWrite: 0.25),
        "gpt-5.3-codex": .init(input: 1.75, cached: 0.175, output: 14),
        "gemini-2.5-pro": .init(input: 1.25, cached: 0.125, output: 10),
        "gemini-2.5-flash": .init(input: 0.3, cached: 0.03, output: 2.5)
    ]
    static let defaultsKey = "tokenUsagePriceOverrides.v1"
}
