import Foundation

enum UsagePricing {
    /// Reference rates checked 2026-09-08 against:
    ///
    /// - https://platform.claude.com/docs/en/build-with-claude/prompt-caching.md
    /// - https://developers.openai.com/api/docs/pricing
    /// - https://ai.google.dev/gemini-api/docs/pricing
    ///
    /// Deliberately exact model IDs: no guessed family pricing. Standard
    /// short-context text rates; premiums, tools, storage, and subscription fees
    /// are excluded. A model with no published cache rate is left at zero for
    /// that bucket, which is correct for models that cannot cache at all.
    static let defaults: [String: ModelTokenPrice] = claude.merging(openAI) { first, _ in first }
        .merging(google) { first, _ in first }

    /// Anthropic publishes every cache bucket per model: reads are a tenth of
    /// base input, five-minute writes 1.25x, and one-hour writes 2x. Claude Code
    /// leans on all of them, so an input-and-output-only estimate would be
    /// wrong for most of a real conversation.
    static let claude: [String: ModelTokenPrice] = [
        "claude-fable-5-1": .init(input: 10, cached: 0.25, output: 50, cacheWrite: 12.5, cacheWriteLong: 20),
        "claude-mythos-5-1": .init(input: 10, cached: 0.25, output: 50, cacheWrite: 12.5, cacheWriteLong: 20),
        "claude-fable-5": .init(input: 10, cached: 1, output: 50, cacheWrite: 12.5, cacheWriteLong: 20),
        "claude-mythos-5": .init(input: 10, cached: 1, output: 50, cacheWrite: 12.5, cacheWriteLong: 20),
        "claude-opus-5": .init(input: 5, cached: 0.5, output: 25, cacheWrite: 6.25, cacheWriteLong: 10),
        "claude-opus-4-8": .init(input: 5, cached: 0.5, output: 25, cacheWrite: 6.25, cacheWriteLong: 10),
        "claude-opus-4-7": .init(input: 5, cached: 0.5, output: 25, cacheWrite: 6.25, cacheWriteLong: 10),
        "claude-opus-4-6": .init(input: 5, cached: 0.5, output: 25, cacheWrite: 6.25, cacheWriteLong: 10),
        "claude-sonnet-5": .init(input: 2, cached: 0.2, output: 10, cacheWrite: 2.5, cacheWriteLong: 4),
        "claude-sonnet-4-6": .init(input: 3, cached: 0.3, output: 15, cacheWrite: 3.75, cacheWriteLong: 6),
        "claude-haiku-4-5": .init(input: 1, cached: 0.1, output: 5, cacheWrite: 1.25, cacheWriteLong: 2),
        "claude-haiku-4-5-20251001": .init(input: 1, cached: 0.1, output: 5, cacheWrite: 1.25, cacheWriteLong: 2)
    ]

    /// Cache writes are published only for the models that bill for them; the
    /// `pro` models publish no cached rate because they do not cache.
    static let openAI: [String: ModelTokenPrice] = [
        "gpt-6-astra": .init(input: 10, cached: 1, output: 50, cacheWrite: 12.5),
        "gpt-5.6-sol": .init(input: 4, cached: 0.4, output: 20, cacheWrite: 5),
        "gpt-5.6-terra": .init(input: 2, cached: 0.2, output: 12, cacheWrite: 2.5),
        "gpt-5.6-luna": .init(input: 0.2, cached: 0.02, output: 1.2, cacheWrite: 0.25),
        "gpt-5.5": .init(input: 5, cached: 0.5, output: 30),
        "gpt-5.5-pro": .init(input: 30, output: 180),
        "gpt-5.4": .init(input: 2.5, cached: 0.25, output: 15),
        "gpt-5.4-mini": .init(input: 0.75, cached: 0.075, output: 4.5),
        "gpt-5.4-nano": .init(input: 0.2, cached: 0.02, output: 1.25),
        "gpt-5.4-pro": .init(input: 30, output: 180),
        "gpt-5.3-codex": .init(input: 1.75, cached: 0.175, output: 14),
        "gpt-5.2": .init(input: 1.75, cached: 0.175, output: 14),
        "gpt-5.1": .init(input: 1.25, cached: 0.125, output: 10),
        "gpt-5": .init(input: 1.25, cached: 0.125, output: 10),
        "gpt-5-mini": .init(input: 0.25, cached: 0.025, output: 2),
        "gpt-5-nano": .init(input: 0.05, cached: 0.005, output: 0.4)
    ]

    /// Google's `cached` figure is the context-cache *read* rate. Cache storage
    /// is billed per hour rather than per token, so it has no per-token bucket
    /// here and is excluded along with the other non-text charges. The three
    /// current Flash models carry a promotional rate that expires 2026-12-31;
    /// the rate in effect on the day this table was checked is the one used.
    static let google: [String: ModelTokenPrice] = [
        "gemini-3.8-flash": .init(input: 0.75, cached: 0.075, output: 3.75),
        "gemini-3.7-flash": .init(input: 0.75, cached: 0.075, output: 3.75),
        "gemini-3.6-flash": .init(input: 0.75, cached: 0.075, output: 3.75),
        "gemini-3.5-flash": .init(input: 1.5, cached: 0.15, output: 9),
        "gemini-3.5-flash-lite": .init(input: 0.3, cached: 0.03, output: 2.5),
        "gemini-3.1-flash-lite": .init(input: 0.25, cached: 0.025, output: 1.5),
        "gemini-3.1-pro-preview": .init(input: 2, cached: 0.2, output: 12),
        "gemini-2.5-pro": .init(input: 1.25, cached: 0.125, output: 10),
        "gemini-2.5-flash": .init(input: 0.3, cached: 0.03, output: 2.5),
        "gemini-2.5-flash-lite": .init(input: 0.1, cached: 0.01, output: 0.4)
    ]

    static let defaultsKey = "tokenUsagePriceOverrides.v1"
}
