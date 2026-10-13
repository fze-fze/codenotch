import XCTest
@testable import Codenotch

/// Pinned to a response recorded from a live SuperGrok CLI session. On the
/// unified bill, `creditUsagePercent` is the included pool shared by Grok,
/// Grok Bot and Cursor — not a Grok Build allowance of its own.
final class GrokUsageTests: XCTestCase {
    private let credits = """
    {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
    "start":"2026-09-05T08:21:18.802818+00:00",\
    "end":"2026-09-12T08:21:18.802818+00:00"},\
    "creditUsagePercent":8.0,\
    "onDemandCap":{"val":0},"onDemandUsed":{"val":0},\
    "productUsage":[{"product":"GrokBuild","usagePercent":8.0}],\
    "isUnifiedBillingUser":true,"prepaidBalance":{"val":0},\
    "topUpMethod":"TOP_UP_METHOD_SAVED_PAYMENT_METHOD",\
    "billingPeriodStart":"2026-09-05T08:21:18.802818+00:00",\
    "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
    """

    private func windows() throws -> [LimitWindow] {
        try GrokUsage.windows(creditsJSON: credits)
    }

    func testTheRingIsTheCreditsPercentage() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        XCTAssertEqual(credits.duration, 7 * 86400)
        XCTAssertEqual(credits.label, "Weekly limit")
        XCTAssertEqual(credits.usedFraction ?? -1, 0.08, accuracy: 0.0001)
        XCTAssertEqual(try windows().map(\.id), ["credits"])
    }

    func testWeeklyCreditsHaveTheirOwnReset() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        let reset = try XCTUnwrap(credits.resetsAt)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.month, from: reset), 9)
        XCTAssertEqual(utc.component(.day, from: reset), 12)
    }

    /// An empty config has nothing to draw a ring from — not a reading of
    /// zero, an absence of one.
    func testAnEmptyConfigIsNotASuccessfulReading() {
        XCTAssertThrowsError(try GrokUsage.windows(
            creditsJSON: #"{"config":{}}"#
        )) { error in
            guard case UsageProviderError.nothingMetered = error else {
                return XCTFail("expected nothingMetered, got \(error)")
            }
        }
    }

    /// `creditUsagePercent` is absent; the product array is the reading. The
    /// ring is still declared as both the headline and weekly allowance.
    func testProductOnlyCreditsStillUseTheHeadlineID() throws {
        let productOnly = """
        {"config":{"productUsage":[{"product":"GrokBuild","usagePercent":33.0}],\
        "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
        """
        let w = try GrokUsage.windows(creditsJSON: productOnly)
        let credits = try XCTUnwrap(w.first { $0.id == "credits" })
        XCTAssertNil(credits.duration)
        XCTAssertEqual(credits.label, "Grok Build")
        XCTAssertEqual(credits.usedFraction ?? -1, 0.33, accuracy: 0.0001)
        let snap = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok,
            fidelity: .official, status: .ok, windows: w,
            headlineID: "credits", weeklyID: "credits"
        )
        XCTAssertEqual(snap.headline?.id, "credits")
        XCTAssertEqual(snap.weeklyLimitWindow?.id, "credits")
        XCTAssertEqual(snap.usedFraction ?? -1, 0.33, accuracy: 0.0001)
    }

    /// An X Premium+ / SuperGrok weekly pool states its window in
    /// `currentPeriod` but carries no `creditUsagePercent` or `productUsage`
    /// until usage lands. Grok's own `/usage` draws a "Weekly limit" bar at 0%
    /// here, so this is a zero reading, not an absent one.
    func testWeeklyPoolWithoutAPercentIsAZeroRing() throws {
        let weeklyOnly = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
        "start":"2026-09-07T20:59:12+00:00",\
        "end":"2026-09-14T20:59:12+00:00"},\
        "onDemandCap":{"val":0},"onDemandUsed":{"val":0},\
        "isUnifiedBillingUser":true,"prepaidBalance":{"val":0}}}
        """
        let w = try GrokUsage.windows(creditsJSON: weeklyOnly)
        let credits = try XCTUnwrap(w.first { $0.id == "credits" })
        XCTAssertEqual(credits.label, "Weekly limit")
        XCTAssertEqual(credits.usedFraction ?? -1, 0, accuracy: 0.0001)
        let reset = try XCTUnwrap(credits.resetsAt)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.month, from: reset), 9)
        XCTAssertEqual(utc.component(.day, from: reset), 14)
    }

    func testGarbageIsABadResponseRatherThanAGuess() {
        XCTAssertThrowsError(try GrokUsage.windows(creditsJSON: "not json")) { error in
            guard case UsageProviderError.badResponse = error else {
                return XCTFail("expected badResponse, got \(error)")
            }
        }
    }

    /// The same percent covers Grok, Grok Bot and Cursor. Their rows are a
    /// breakdown of that one pool, so the card stays a single limit window
    /// and the products follow it as text-only rows.
    func testTheSharedPoolIsOneLimit() throws {
        let shared = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY",\
        "start":"2026-10-01T00:00:00+00:00",\
        "end":"2026-11-01T00:00:00+00:00"},\
        "creditUsagePercent":12.0,"isUnifiedBillingUser":true,\
        "productUsage":[{"product":"Grok","usagePercent":4.0},\
        {"product":"GrokBot","usagePercent":5.0},\
        {"product":"Cursor","usagePercent":3.0}]}}
        """
        let w = try GrokUsage.windows(creditsJSON: shared)
        XCTAssertEqual(w.map(\.id), ["credits", "product:Grok", "product:GrokBot", "product:Cursor"])
        XCTAssertEqual(w.filter { $0.usedFraction != nil }.map(\.id), ["credits"])
        XCTAssertEqual(w[0].label, "Monthly limit")
        XCTAssertEqual(w[0].usedFraction ?? -1, 0.12, accuracy: 0.0001)
        XCTAssertEqual(w[0].duration, 31 * 86400)
    }

    /// A fresh monthly cycle states the window and no percent yet. That is 0%
    /// of the shared pool, not an account with nothing to meter.
    func testAFreshMonthlyPoolReadsAsZero() throws {
        let monthly = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY",\
        "start":"2026-10-01T00:00:00+00:00",\
        "end":"2026-11-01T00:00:00+00:00"}}}
        """
        let w = try GrokUsage.windows(creditsJSON: monthly)
        let credits = try XCTUnwrap(w.first { $0.id == "credits" })
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(credits.label, "Monthly limit")
        XCTAssertEqual(credits.usedFraction ?? -1, 0, accuracy: 0.0001)
    }

    /// The combined percent can be omitted and left on the only product row.
    /// On the shared pool that row is still the pool, not a Grok Build quota.
    func testAUnifiedProductPercentIsThePool() throws {
        let onlyProduct = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
        "end":"2026-09-12T08:21:18+00:00"},\
        "isUnifiedBillingUser":true,\
        "productUsage":[{"product":"GrokBuild","usagePercent":33.0}]}}
        """
        let w = try GrokUsage.windows(creditsJSON: onlyProduct)
        XCTAssertEqual(w.map(\.id), ["credits"])
        XCTAssertEqual(w[0].label, "Weekly limit")
        XCTAssertEqual(w[0].usedFraction ?? -1, 0.33, accuracy: 0.0001)
    }

    /// Before the shared pool, the credits percent is the Grok Build allowance
    /// and keeps that name.
    func testALegacyBuildAllowanceKeepsItsProductName() throws {
        let legacy = """
        {"config":{"creditUsagePercent":8.0,\
        "productUsage":[{"product":"GrokBuild","usagePercent":8.0}],\
        "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
        """
        let w = try GrokUsage.windows(creditsJSON: legacy)
        XCTAssertEqual(w.map(\.label), ["Grok Build"])
        XCTAssertEqual(w[0].usedFraction ?? -1, 0.08, accuracy: 0.0001)
    }

    func testHumanizesTheProductNameTheWayTheModalWritesIt() {
        XCTAssertEqual(GrokUsage.humanize("GrokBuild"), "Grok Build")
    }

    /// The issuer is compared whole: a host that merely begins with
    /// `auth.x.ai` is someone else's, and its token must not be sent to xAI.
    func testALookalikeIssuerIsNotTrusted() {
        XCTAssertFalse(GrokCredentials.isTrusted(key: "https://auth.x.ai.example.com::cli", entry: [:]))
        XCTAssertFalse(GrokCredentials.isTrusted(key: "https://auth.x.aix::cli", entry: [:]))
        XCTAssertTrue(GrokCredentials.isTrusted(key: "https://auth.x.ai::cli", entry: [:]))
        XCTAssertTrue(GrokCredentials.isTrusted(key: "https://auth.x.ai", entry: [:]))
    }

    /// Recorded from a live SuperGrok account on the bundled plan. The first
    /// row has no product name; it is Cursor's.
    func testTheLiveBreakdownFollowsThePool() throws {
        let previous = L10n.testLocale
        L10n.testLocale = Locale(identifier: "en_US")
        defer { L10n.testLocale = previous }

        let live = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
        "start":"2026-10-13T04:35:13.277+00:00","end":"2026-10-20T04:35:13.277+00:00"},\
        "creditUsagePercent":14.0,"productUsage":[{"usagePercent":6.0},\
        {"product":"GrokVoice","usagePercent":4.0},{"product":"GrokBuild","usagePercent":2.0},\
        {"product":"GrokBot","usagePercent":1.0},{"product":"GrokChat","usagePercent":1.0}],\
        "isUnifiedBillingUser":true,"prepaidBalance":{"val":0},\
        "topUpMethod":"TOP_UP_METHOD_SAVED_PAYMENT_METHOD",\
        "billingPeriodStart":"2026-10-13T04:35:13.277+00:00",\
        "billingPeriodEnd":"2026-10-20T04:35:13.277+00:00"}}
        """
        let w = try GrokUsage.windows(creditsJSON: live)
        XCTAssertEqual(w[0].id, "credits")
        XCTAssertEqual(w[0].label, "Weekly limit")
        XCTAssertEqual(w[0].usedFraction ?? -1, 0.14, accuracy: 0.0001)

        let rows = Array(w.dropFirst())
        XCTAssertEqual(rows.map(\.label), ["Cursor", "Grok Voice", "Grok Build", "Grok Bot", "Grok Chat"])
        XCTAssertEqual(rows.map(\.detail), ["6%", "4%", "2%", "1%", "1%"])
        XCTAssertTrue(rows.allSatisfy { $0.group == "By product" && $0.usedFraction == nil })
        XCTAssertEqual(rows.first?.id, "product:0")
    }

    func testThePlanComesFromTheSettingsResponse() {
        XCTAssertEqual(
            GrokUsage.plan(settingsJSON: #"{"subscription_tier":null,"subscription_tier_display":"SuperGrok"}"#),
            "SuperGrok"
        )
        XCTAssertNil(GrokUsage.plan(settingsJSON: #"{"subscription_tier_display":"  "}"#))
        XCTAssertNil(GrokUsage.plan(settingsJSON: "not json"))
    }

    /// The CLI's cache wraps the same response in a string under `payload`.
    func testThePlanComesFromTheCLICache() throws {
        let inner = #"{"settings":{"subscription_tier_display":"SuperGrok"}}"#
        let cache = String(data: try JSONSerialization.data(withJSONObject: ["payload": inner]),
                           encoding: .utf8)!
        XCTAssertEqual(GrokUsage.plan(settingsJSON: cache), "SuperGrok")
    }
}
