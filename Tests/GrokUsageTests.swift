import XCTest
@testable import Codenotch

/// Pinned to a response recorded from a live SuperGrok CLI session, on an
/// account spending its weekly limit on one product.
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

    /// The ring is the weekly limit, named for the limit rather than for a
    /// product — the percentage is a percentage *of* the limit.
    func testTheRingIsTheCreditsPercentage() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        XCTAssertEqual(credits.label, "Weekly limit")
        XCTAssertEqual(credits.usedFraction ?? -1, 0.08, accuracy: 0.0001)
    }

    /// It owns its allowance, so it is the one row that can talk about what is
    /// left.
    func testTheLimitRowStatesBothEnds() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        XCTAssertFalse(credits.isShare)
        XCTAssertEqual(credits.summary, "8% Used · 92% left")
    }

    /// A single product's share *is* the total, so it is not restated on a row
    /// underneath the number it equals.
    func testALoneProductIsNotRestatedUnderTheTotal() throws {
        XCTAssertEqual(try windows().map(\.label), ["Weekly limit"])
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

    /// `creditUsagePercent` is absent and one product is spending the limit, so
    /// that product *is* the allowance: it lends the total its name, owns its
    /// percentage, and still carries `headlineID: "credits"`.
    func testProductOnlyCreditsStillUseTheHeadlineID() throws {
        let productOnly = """
        {"config":{"productUsage":[{"product":"GrokBuild","usagePercent":33.0}],\
        "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
        """
        let w = try GrokUsage.windows(creditsJSON: productOnly)
        let credits = try XCTUnwrap(w.first { $0.id == "credits" })
        XCTAssertEqual(credits.label, "Grok Build")
        XCTAssertFalse(credits.isShare)
        XCTAssertEqual(credits.usedFraction ?? -1, 0.33, accuracy: 0.0001)
        let snap = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok,
            fidelity: .official, status: .ok, windows: w, headlineID: "credits"
        )
        XCTAssertEqual(snap.headline?.id, "credits")
        XCTAssertEqual(snap.usedFraction ?? -1, 0.33, accuracy: 0.0001)
    }

    func testGarbageIsABadResponseRatherThanAGuess() {
        XCTAssertThrowsError(try GrokUsage.windows(creditsJSON: "not json")) { error in
            guard case UsageProviderError.badResponse = error else {
                return XCTFail("expected badResponse, got \(error)")
            }
        }
    }

    func testHumanizesTheProductNameTheWayTheModalWritesIt() {
        XCTAssertEqual(GrokUsage.humanize("GrokBuild"), "Grok Build")
    }

    /// Grok's own usage modal heads this bar "Weekly limit" and reads the
    /// period from the same field.
    func testTheLimitIsNamedForItsPeriod() {
        XCTAssertEqual(
            GrokUsage.limitLabel(["currentPeriod": ["type": "USAGE_PERIOD_TYPE_WEEKLY"]]),
            "Weekly limit")
        XCTAssertEqual(
            GrokUsage.limitLabel(["currentPeriod": ["type": "USAGE_PERIOD_TYPE_MONTHLY"]]),
            "Monthly limit")
        XCTAssertEqual(GrokUsage.limitLabel([:]), "Credits")
    }
}

/// The same endpoint on an account spending its weekly limit on more than one
/// product. This is the shape that showed what the numbers mean: there is one
/// allowance, and `productUsage` says which products ate it.
final class GrokMultiProductUsageTests: XCTestCase {
    private let credits = """
    {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
    "start":"2026-09-05T08:54:33.321058+00:00",\
    "end":"2026-09-12T08:54:33.321058+00:00"},\
    "creditUsagePercent":25.0,\
    "onDemandCap":{"val":0},"onDemandUsed":{"val":0},\
    "productUsage":[{"product":"GrokBuild","usagePercent":13.0},\
    {"product":"GrokChat","usagePercent":12.0}],\
    "isUnifiedBillingUser":true,"prepaidBalance":{"val":0},\
    "billingPeriodStart":"2026-09-05T08:54:33.321058+00:00",\
    "billingPeriodEnd":"2026-09-12T08:54:33.321058+00:00"}}
    """

    private func windows() throws -> [LimitWindow] {
        try GrokUsage.windows(creditsJSON: credits)
    }

    /// The ring is the total, and it must not be wearing one product's name:
    /// 25% is nearly twice Grok Build's 13%.
    func testTheTotalIsNotNamedAfterOneProduct() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        XCTAssertEqual(credits.usedFraction ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(credits.label, "Weekly limit")
    }

    /// Every product gets a row of its own, the way the other providers break
    /// their windows out in the tooltip.
    func testEachProductGetsItsOwnRow() throws {
        let rows = try windows()
        XCTAssertEqual(rows.map(\.label), ["Weekly limit", "Grok Build", "Grok Chat"])
        let build = try XCTUnwrap(rows.first { $0.id == "GrokBuild" })
        let chat = try XCTUnwrap(rows.first { $0.id == "GrokChat" })
        XCTAssertEqual(build.usedFraction ?? -1, 0.13, accuracy: 0.0001)
        XCTAssertEqual(chat.usedFraction ?? -1, 0.12, accuracy: 0.0001)
    }

    /// The correction this suite exists for. A product's percentage is the
    /// slice of the weekly limit it ate, not a limit of its own — so its row
    /// must not offer a remainder. There is no 87% left to Grok Build; there is
    /// 75% left to the account, and the row above is the one that says so.
    func testAProductRowStatesItsShareAndNoRemainder() throws {
        let build = try XCTUnwrap(windows().first { $0.id == "GrokBuild" })
        XCTAssertTrue(build.isShare)
        XCTAssertEqual(build.shareOf, "credits")
        XCTAssertEqual(build.summary, "13% of limit")
        XCTAssertFalse(build.summary.contains("left"),
                       "a share of somebody else's allowance has no remainder")
    }

    /// The shares are parts of the total, which is why they sum to it.
    func testTheSharesSumToTheTotal() throws {
        let rows = try windows()
        let total = try XCTUnwrap(rows.first { !$0.isShare }.flatMap(\.usedFraction))
        let shares = rows.filter(\.isShare).compactMap(\.usedFraction).reduce(0, +)
        XCTAssertEqual(shares, total, accuracy: 0.0001)
    }

    /// The ring still means the whole limit.
    func testTheRingIsTheTotalAndNotAShare() throws {
        let snap = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok, fidelity: .official,
            status: .ok, windows: try windows(), headlineID: "credits"
        )
        XCTAssertEqual(snap.usedFraction ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snap.headlineText, "25%")
    }

    /// Every window resets when the weekly period does.
    func testTheProductRowsShareTheWeeklyReset() throws {
        let resets = try windows().map(\.resetsAt)
        XCTAssertEqual(Set(resets.map { $0?.timeIntervalSince1970 }).count, 1)
        XCTAssertNotNil(resets.first ?? nil)
    }

    /// Several products and no total to be shares of. Adding them up would
    /// state a figure the endpoint did not, and promoting one to wear the ring
    /// is the mistake this suite is about — so the card shows the breakdown and
    /// the cell shows a dash.
    func testNoStatedTotalLeavesTheRingBlankRatherThanPromotingAShare() throws {
        let noTotal = """
        {"config":{"productUsage":[{"product":"GrokBuild","usagePercent":13.0},\
        {"product":"GrokChat","usagePercent":12.0}],\
        "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
        """
        let rows = try GrokUsage.windows(creditsJSON: noTotal)
        XCTAssertEqual(rows.map(\.label), ["Grok Build", "Grok Chat"])
        XCTAssertTrue(rows.allSatisfy(\.isShare))
        let snap = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok, fidelity: .official,
            status: .ok, windows: rows, headlineID: "credits"
        )
        XCTAssertNil(snap.usedFraction)
        XCTAssertEqual(snap.headlineText, "—")
    }
}

/// A window that owns no allowance is not the ordinary case, so the rule is
/// pinned where the rendering lives rather than only where Grok sets it.
final class LimitWindowShareTests: XCTestCase {
    func testAnOrdinaryWindowStillStatesBothEnds() {
        let window = LimitWindow(id: "w", label: "Weekly", usedFraction: 0.13)
        XCTAssertFalse(window.isShare)
        XCTAssertEqual(window.summary, "13% Used · 87% left")
    }

    func testAShareStatesOnlyItsOwnSize() {
        let window = LimitWindow(id: "w", label: "Grok Build",
                                 usedFraction: 0.13, shareOf: "credits")
        XCTAssertTrue(window.isShare)
        XCTAssertEqual(window.summary, "13% of limit")
    }

    /// Readings archived before shares existed still decode, and decode as
    /// windows that own their allowance.
    func testAReadingWrittenBeforeSharesExistedStillDecodes() throws {
        let old = Data(#"{"id":"credits","label":"Weekly limit","usedFraction":0.25}"#.utf8)
        let window = try JSONDecoder().decode(LimitWindow.self, from: old)
        XCTAssertFalse(window.isShare)
        XCTAssertEqual(window.summary, "25% Used · 75% left")
    }
}

/// The plan's name, which the billing endpoints do not carry. Without it the
/// Grok row showed an address and a blank where every other row names a plan.
final class GrokSettingsTests: XCTestCase {
    func testItReadsTheDisplayTier() {
        let json = #"{"release_channel":"stable","subscription_tier_display":"X Premium"}"#
        XCTAssertEqual(GrokSettings.tier(settingsJSON: json), "X Premium")
    }

    /// The field is optional and null on some accounts. No plan is a blank, not
    /// an empty string sitting after a separator.
    func testAMissingOrEmptyTierIsNoPlan() {
        XCTAssertNil(GrokSettings.tier(settingsJSON: #"{"subscription_tier_display":null}"#))
        XCTAssertNil(GrokSettings.tier(settingsJSON: #"{"subscription_tier_display":""}"#))
        XCTAssertNil(GrokSettings.tier(settingsJSON: #"{"release_channel":"stable"}"#))
        XCTAssertNil(GrokSettings.tier(settingsJSON: "not json"))
    }

    /// Grok already writes the tier for reading, and `capitalized` used to
    /// flatten it on the way to the row.
    func testTheRowKeepsGroksOwnCasing() {
        let account = ProviderAccount(label: "someone@example.com",
                                      plan: "SuperGrok Heavy", manageURL: nil)
        XCTAssertEqual(account.summary, "someone@example.com · SuperGrok Heavy")
    }

    /// Cursor's wire token still gets title-cased.
    func testALowercaseWireTokenIsStillCapitalised() {
        let account = ProviderAccount(label: "someone@example.com",
                                      plan: "pro", manageURL: nil)
        XCTAssertEqual(account.summary, "someone@example.com · Pro")
    }

    /// A plan read a week ago is no longer proof of the plan an account is on.
    func testAStalePlanIsForgotten() {
        let now = Date()
        let fresh = GrokLocalProvider.StoredPlan(name: "X Premium", at: now)
        XCTAssertTrue(GrokLocalProvider.isFresh(fresh, now: now))
        let stale = GrokLocalProvider.StoredPlan(
            name: "X Premium", at: now.addingTimeInterval(-GrokLocalProvider.planMemory - 1)
        )
        XCTAssertFalse(GrokLocalProvider.isFresh(stale, now: now))
        XCTAssertFalse(GrokLocalProvider.isFresh(nil, now: now))
    }
}
