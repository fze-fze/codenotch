import XCTest
@testable import Codenotch

final class UsagePricingTests: XCTestCase {
    private func record(model: String, tokens: TokenCounts) -> TokenUsageRecord {
        TokenUsageRecord(id: model, agent: .claudeCode, session: "s",
                         timestamp: Date(timeIntervalSince1970: 1_788_600_000),
                         model: model, tokens: tokens)
    }

    /// Claude Code writes to every cache bucket, so a rate that covered only
    /// input and output would misprice most of a real conversation.
    func testClaudePricesEveryBucketItIsBilledFor() throws {
        let price = try XCTUnwrap(UsagePricing.defaults["claude-opus-5"])
        XCTAssertEqual(price.input, 5)
        XCTAssertEqual(price.cached, 0.5)
        XCTAssertEqual(price.output, 25)
        XCTAssertEqual(price.cacheWrite, 6.25)
        XCTAssertEqual(price.cacheWriteLong, 10)

        let million = TokenCounts(input: 1_000_000, cached: 1_000_000, cacheWrite: 1_000_000,
                                  cacheWriteLong: 1_000_000, output: 1_000_000)
        let summary = UsageSummary(records: [record(model: "claude-opus-5", tokens: million)],
                                   prices: UsagePricing.defaults)
        XCTAssertEqual(summary.cost, 46.75, accuracy: 0.0001)
        XCTAssertEqual(summary.unpriced, 0)
    }

    /// The five-minute write is 1.25x base input and the one-hour write 2x, so
    /// a transposed pair would still look plausible in isolation.
    func testCacheWriteRatesFollowThePublishedMultipliers() throws {
        for id in ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5", "claude-fable-5"] {
            let price = try XCTUnwrap(UsagePricing.defaults[id], id)
            XCTAssertEqual(price.cacheWrite, price.input * 1.25, accuracy: 0.0001, id)
            XCTAssertEqual(price.cacheWriteLong, price.input * 2, accuracy: 0.0001, id)
            XCTAssertLessThan(price.cached, price.input, id)
            XCTAssertGreaterThan(price.output, price.input, id)
        }
    }

    /// Every model this Mac's agents can actually name should price, so a real
    /// dashboard is not mostly "Not priced".
    func testModelsTheLocalAgentsUseArePriced() throws {
        for id in ["claude-opus-5", "claude-opus-4-8", "claude-fable-5", "claude-sonnet-5",
                   "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
                   "gemini-3.8-flash", "gemini-3.7-flash", "gemini-2.5-pro"] {
            let price = try XCTUnwrap(UsagePricing.defaults[id], "\(id) has no reference price")
            XCTAssertTrue(price.isValid, id)
            XCTAssertGreaterThan(price.input, 0, id)
            XCTAssertGreaterThan(price.output, 0, id)
        }
    }

    /// A model with no published rate must stay unpriced rather than inherit a
    /// sibling's: Codex's internal review model is billed to no public table.
    func testUnpublishedModelsStayUnpriced() {
        XCTAssertNil(UsagePricing.defaults["codex-auto-review"])
        XCTAssertNil(UsagePricing.defaults["grok-4.6"])
        XCTAssertNil(UsagePricing.defaults["composer-2.5"])
        XCTAssertNil(UsagePricing.defaults["Unknown model"])
        let summary = UsageSummary(records: [record(model: "codex-auto-review",
                                                    tokens: TokenCounts(input: 100, output: 10))],
                                   prices: UsagePricing.defaults)
        XCTAssertEqual(summary.costLabel, "Not priced")
        XCTAssertEqual(summary.unpriced, 1)
        XCTAssertEqual(summary.tokens.total, 110, "tokens stay counted even when the rate is unknown")
    }

    func testTheThreeSourceTablesDoNotCollide() {
        let counts = UsagePricing.claude.count + UsagePricing.openAI.count + UsagePricing.google.count
        XCTAssertEqual(UsagePricing.defaults.count, counts, "a model id is priced by one source only")
        XCTAssertTrue(UsagePricing.defaults.values.allSatisfy(\.isValid))
    }
}
