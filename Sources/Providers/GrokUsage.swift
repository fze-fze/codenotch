import Foundation

/// Parses the credits payload the Grok CLI's `/usage` reads:
///
/// `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`
/// ```json
/// { "config": {
///     "currentPeriod": { "type": "USAGE_PERIOD_TYPE_WEEKLY",
///                        "start": "2026-09-05T08:21:18.802818+00:00",
///                        "end":   "2026-09-12T08:21:18.802818+00:00" },
///     "creditUsagePercent": 8.0,
///     "productUsage": [{ "product": "GrokBuild", "usagePercent": 8.0 }],
///     "isUnifiedBillingUser": true,
///     "billingPeriodStart": "2026-09-05T08:21:18.802818+00:00",
///     "billingPeriodEnd":   "2026-09-12T08:21:18.802818+00:00" } }
/// ```
///
/// The X Subscription is one bill. Grok, Grok Bot and Cursor draw on one
/// included pool, and `creditUsagePercent` is how full that pool is.
/// `productUsage` says which surface spent it — chat, build, the bot, Cursor —
/// and is not another allowance, so it is not another window. The card stays
/// the one Claude already draws: one limit, how much of it is spent, and when
/// it resets.
///
/// Which limit it is comes from `currentPeriod.type`. The published plan
/// refreshes weekly (`USAGE_PERIOD_TYPE_WEEKLY`). A period the endpoint marks
/// monthly is a monthly limit. `billingPeriodEnd` with no `currentPeriod` is
/// a usage ledger, not a cycle, and is not turned into one.
///
/// An account that has not moved onto that pool still reports a Grok Build
/// allowance, and that remains the window.
enum GrokUsage {
    static func windows(creditsJSON: String) throws -> [LimitWindow] {
        guard let credits = object(creditsJSON)?["config"] as? [String: Any] else {
            throw UsageProviderError.badResponse(status: 0)
        }

        let currentPeriod = period(credits["currentPeriod"])
        let currentEnd = date(currentPeriod?["end"])
        let creditsReset = currentEnd ?? date(credits["billingPeriodEnd"])
        let start = currentEnd == nil
            ? date(credits["billingPeriodStart"]) : date(currentPeriod?["start"])
        let duration = start.flatMap { start in creditsReset.map { $0.timeIntervalSince(start) } }
        let kind = periodKind(currentPeriod?["type"] as? String)

        if isSharedPool(credits, kind: kind),
           let window = sharedWindow(credits, kind: kind, resetsAt: creditsReset, duration: duration) {
            return [window]
        }

        var windows: [LimitWindow] = []

        if let fraction = percent(credits["creditUsagePercent"]) {
            windows.append(LimitWindow(
                id: "credits",
                label: productLabel(credits) ?? L10n.t("Grok Build"),
                usedFraction: fraction,
                resetsAt: creditsReset,
                duration: duration
            ))
        } else if let products = credits["productUsage"] as? [[String: Any]] {
            for product in products {
                guard let fraction = percent(product["usagePercent"]) else { continue }
                let name = (product["product"] as? String).map(humanize) ?? L10n.t("Usage")
                // The ring is declared as `headlineID: "credits"`. Using the
                // wire product name here left a valid bar in the tooltip and
                // a dash on the cell.
                windows.append(LimitWindow(
                    id: windows.isEmpty ? "credits" : ((product["product"] as? String) ?? name),
                    label: name,
                    usedFraction: fraction,
                    resetsAt: creditsReset,
                    duration: duration
                ))
            }
        }

        // A weekly plan pool states its window in `currentPeriod` and omits
        // `creditUsagePercent`/`productUsage` until usage lands, so the
        // branches above find nothing on a fresh period. Grok's own `/usage`
        // still shows this as a "Weekly limit" bar at 0% with the period end
        // as the reset, so mirror it rather than reporting the account as
        // unmetered. A monthly period is the shared pool, handled above.
        if windows.isEmpty, kind == .weekly {
            windows.append(LimitWindow(
                id: "credits",
                label: L10n.t("Weekly limit"),
                usedFraction: 0,
                resetsAt: date(currentPeriod?["end"]) ?? creditsReset,
                duration: duration
            ))
        }

        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered(L10n.t("Grok has nothing metered on this account yet"))
        }
        return windows
    }

    /// One included pool: the unified bill, a monthly cycle, or a breakdown
    /// across more than one surface. A single Grok Build row on an account
    /// that has not been moved is still that product's own allowance.
    private static func isSharedPool(_ credits: [String: Any], kind: PeriodKind) -> Bool {
        if (credits["isUnifiedBillingUser"] as? Bool) == true { return true }
        if kind == .monthly { return true }
        let products = credits["productUsage"] as? [[String: Any]] ?? []
        return products.count > 1
    }

    /// The pool's own percent. Several product rows without that percent are
    /// a breakdown of a number the endpoint did not state, and are not added
    /// up into one — nor replaced with 0%, which would hide them.
    private static func sharedWindow(
        _ credits: [String: Any], kind: PeriodKind, resetsAt: Date?, duration: TimeInterval?
    ) -> LimitWindow? {
        let stated = percent(credits["creditUsagePercent"]) ?? soleProductPercent(credits)
        let fraction: Double?
        if let stated {
            fraction = stated
        } else if productPercents(credits).isEmpty, kind == .weekly || kind == .monthly {
            fraction = 0
        } else {
            fraction = nil
        }
        guard let fraction else { return nil }
        return LimitWindow(
            id: "credits",
            label: poolLabel(kind),
            usedFraction: fraction,
            resetsAt: resetsAt,
            duration: duration
        )
    }

    private static func productPercents(_ credits: [String: Any]) -> [Double] {
        guard let products = credits["productUsage"] as? [[String: Any]] else { return [] }
        return products.compactMap { percent($0["usagePercent"]) }
    }

    private static func soleProductPercent(_ credits: [String: Any]) -> Double? {
        guard let products = credits["productUsage"] as? [[String: Any]], products.count == 1
        else { return nil }
        return percent(products[0]["usagePercent"])
    }

    private static func poolLabel(_ kind: PeriodKind) -> String {
        switch kind {
        case .weekly: return L10n.t("Weekly limit")
        case .monthly: return L10n.t("Monthly limit")
        case .unspecified: return L10n.t("Included usage")
        }
    }

    private enum PeriodKind { case weekly, monthly, unspecified }

    private static func periodKind(_ type: String?) -> PeriodKind {
        guard let type else { return .unspecified }
        if type.contains("MONTH") { return .monthly }
        if type.contains("WEEK") { return .weekly }
        return .unspecified
    }

    private static func productLabel(_ credits: [String: Any]) -> String? {
        guard let products = credits["productUsage"] as? [[String: Any]],
              let name = products.first?["product"] as? String
        else { return nil }
        return humanize(name)
    }

    /// "GrokBuild" → "Grok Build". The wire name is one word; the usage modal
    /// writes two.
    static func humanize(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result
    }

    private static func percent(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        return number.doubleValue / 100
    }

    private static func period(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    private static func object(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func date(_ any: Any?) -> Date? {
        GrokCredentials.date(any)
    }
}
