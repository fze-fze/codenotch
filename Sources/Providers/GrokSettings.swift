import Foundation

/// The one thing Codenotch wants from Grok CLI's `GET /v1/settings`: the name
/// of the plan the account is on.
///
/// The billing endpoints state percentages and say nothing about the tier —
/// `?format=credits` carries `productUsage` and periods, the unformatted one a
/// calendar ledger — so a Grok row showed an address and a blank where every
/// other row names a plan. The CLI reads its own tier from here; the field is
/// already the display form, which is why it is taken verbatim rather than
/// prettified. Recorded from a live session:
///
/// ```json
/// { "subscription_tier_display": "X Premium",
///   "release_channel": "stable", … }
/// ```
///
/// The wire vocabulary behind it is `supergrok_lite`, `supergrok`,
/// `supergrok_plus`, `supergrok_heavy`, `x_premium`, `x_premium_plus` — none
/// of which is what the CLI prints, so mapping those ourselves would mean
/// maintaining a second, worse copy of a list Grok already renders.
enum GrokSettings {
    static func tier(settingsJSON: String) -> String? {
        guard let data = settingsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tier = root["subscription_tier_display"] as? String,
              !tier.isEmpty
        else { return nil }
        return tier
    }
}
