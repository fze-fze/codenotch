import Foundation

/// Parses Grok CLI's billing endpoints, recorded from a live session:
///
/// `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`
/// ```json
/// { "config": {
///     "currentPeriod": { "type": "USAGE_PERIOD_TYPE_WEEKLY",
///                        "start": "2026-09-05T08:54:33.321058+00:00",
///                        "end":   "2026-09-12T08:54:33.321058+00:00" },
///     "creditUsagePercent": 25.0,
///     "productUsage": [{ "product": "GrokBuild", "usagePercent": 13.0 },
///                      { "product": "GrokChat",  "usagePercent": 12.0 }],
///     "billingPeriodStart": "2026-09-05T08:54:33.321058+00:00",
///     "billingPeriodEnd":   "2026-09-12T08:54:33.321058+00:00" } }
/// ```
///
/// The credits payload is the ring: a weekly allowance. Grok's own account
/// charge date is not in this response — the unformatted `/billing` payload's
/// `billingPeriodEnd` is a calendar-month usage ledger, not a bill, and nothing
/// here says which day of the month an account is actually charged. Showing one
/// would mean guessing at a fact this endpoint does not state.
///
/// There is **one allowance here, not one per product**. `creditUsagePercent`
/// is how much of the weekly limit is gone, and each `productUsage` entry is
/// the slice of that same limit a product ate: 25% spent, of which Grok Build
/// 13 and Grok Chat 12. They sum to the total because they are parts of it.
///
/// Two things follow, and the first version of this got both wrong. The total
/// cannot be named after `productUsage.first` — that put "Grok Build" on a
/// number nearly twice Grok Build's. And a product row cannot be an ordinary
/// window, because the tooltip would print "13% Used · 87% left" and no such
/// 87% exists: what is left is 75%, and it belongs to the whole limit rather
/// than to Grok Build. So the products are marked `shareOf` the total, which
/// is what makes them say "13% of limit" instead.
enum GrokUsage {
    static func windows(creditsJSON: String) throws -> [LimitWindow] {
        guard let credits = object(creditsJSON)?["config"] as? [String: Any] else {
            throw UsageProviderError.badResponse(status: 0)
        }

        var windows: [LimitWindow] = []

        let creditsReset = date(period(credits["currentPeriod"])?["end"])
            ?? date(credits["billingPeriodEnd"])
        let products = credits["productUsage"] as? [[String: Any]] ?? []

        if let fraction = percent(credits["creditUsagePercent"]) {
            // The ring, and the only window here that owns an allowance. Its id
            // is declared as `headlineID: "credits"`, so it has to be this one
            // whatever it ends up called.
            windows.append(LimitWindow(
                id: "credits",
                label: limitLabel(credits),
                usedFraction: fraction,
                resetsAt: creditsReset
            ))
            // Only worth breaking out when there is more than one: a lone
            // product's share is the total, restated on the row below it.
            if products.count > 1 {
                windows.append(contentsOf: productWindows(products, resetsAt: creditsReset))
            }
        } else if products.count == 1 {
            // No total stated, and one product spending it: that product *is*
            // the allowance, so it owns its percentage and carries the headline
            // id. Using the wire product name as the id here left a valid bar
            // in the tooltip and a dash on the cell.
            let only = productWindows(products, resetsAt: creditsReset)
            windows.append(contentsOf: only.map {
                LimitWindow(id: "credits", label: $0.label,
                            usedFraction: $0.usedFraction, resetsAt: $0.resetsAt)
            })
        } else {
            // Several products and no total to be shares of. Promoting one of
            // them to wear the ring is the mistake this whole file is written
            // around, and adding them up would be stating a figure the endpoint
            // did not — so the card shows the breakdown and the cell shows a
            // dash, which is the honest pair.
            windows.append(contentsOf: productWindows(products, resetsAt: creditsReset))
        }

        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered("Grok has nothing metered on this account yet")
        }
        return windows
    }

    /// What the allowance is called, in Grok's own words: its usage modal
    /// heads this bar "Weekly limit" and reads the period from the same field.
    /// Named for the *limit* rather than for whichever product happens to be
    /// spending it, because that is what the percentage is a percentage of.
    static func limitLabel(_ credits: [String: Any]) -> String {
        switch period(credits["currentPeriod"])?["type"] as? String {
        case "USAGE_PERIOD_TYPE_WEEKLY":  return "Weekly limit"
        case "USAGE_PERIOD_TYPE_MONTHLY": return "Monthly limit"
        default:                          return "Credits"
        }
    }

    /// One row per product, each a slice of the allowance above rather than an
    /// allowance of its own — see `shareOf`.
    private static func productWindows(_ products: [[String: Any]],
                                       resetsAt: Date?) -> [LimitWindow] {
        products.compactMap { product in
            guard let fraction = percent(product["usagePercent"]) else { return nil }
            let wire = product["product"] as? String
            return LimitWindow(
                id: wire ?? "product",
                label: wire.map(humanize) ?? "Usage",
                usedFraction: fraction,
                resetsAt: resetsAt,
                shareOf: "credits"
            )
        }
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
