import Foundation

/// The account's main rate-limit windows belong in the usage rings. Spark
/// (`additional_rate_limits`) and code review belong on the hover card, not
/// the rings.
enum CodexUsage {
    private struct Response: Decodable {
        let rate_limit: RateLimit?
        let plan_type: String?
        let additional_rate_limits: [AdditionalRateLimit]
        let code_review_rate_limit: RateLimit?
        /// Business and Team seats have no rolling windows; they draw on
        /// credits under a workspace spend control, which is the only
        /// allowance that account can show.
        let spend_control: SpendControl?

        private enum CodingKeys: String, CodingKey {
            case rate_limit
            case plan_type
            case additional_rate_limits
            case code_review_rate_limit
            case spend_control
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A bad main object must not discard Spark/code review, and a bad
            // extra must not discard a good main pair. `try` here used to
            // turn a single unreadable window into a failed fetch.
            rate_limit = try? container.decodeIfPresent(RateLimit.self, forKey: .rate_limit)
            plan_type = try? container.decodeIfPresent(String.self, forKey: .plan_type)
            let extras = (try? container.decodeIfPresent(
                [FailableAdditionalRateLimit].self, forKey: .additional_rate_limits
            )) ?? []
            additional_rate_limits = extras.compactMap(\.value)
            code_review_rate_limit = try? container.decodeIfPresent(
                RateLimit.self, forKey: .code_review_rate_limit
            )
            spend_control = try? container.decodeIfPresent(SpendControl.self, forKey: .spend_control)
        }
    }

    private struct SpendControl: Decodable {
        let individual_limit: CreditLimit?
    }

    /// Amounts arrive as decimal strings ("374.92"); percentages as numbers.
    private struct CreditLimit: Decodable {
        let limit: Double?
        let used: Double?
        let used_percent: Double?
        let reset_at: Double?

        private enum CodingKeys: String, CodingKey { case limit, used, used_percent, reset_at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) -> Double? {
                if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
                if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
                return nil
            }
            limit = number(.limit); used = number(.used); used_percent = number(.used_percent); reset_at = number(.reset_at)
        }
    }

    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?

        private enum CodingKeys: String, CodingKey {
            case primary_window, secondary_window
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // One unreadable window must not take its sibling with it —
            // code review's weekly once vanished because the 5h object
            // could not decode.
            primary_window = try? container.decode(Window.self, forKey: .primary_window)
            secondary_window = try? container.decode(Window.self, forKey: .secondary_window)
        }
    }

    private struct AdditionalRateLimit: Decodable {
        let limit_name: String?
        let metered_feature: String?
        let rate_limit: RateLimit?
    }

    private struct FailableAdditionalRateLimit: Decodable {
        let value: AdditionalRateLimit?
        init(from decoder: Decoder) throws {
            value = try? AdditionalRateLimit(from: decoder)
        }
    }

    private struct Window: Decodable {
        let limit_window_seconds: Double?
        let used_percent: Double?
        let reset_at: Double?
        let reset_after_seconds: Double?

        private enum CodingKeys: String, CodingKey {
            case limit_window_seconds, used_percent, reset_at, reset_after_seconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Null or non-numeric `used_percent` used to fail the whole
            // RateLimit object, so a good weekly window never made it out.
            limit_window_seconds = Self.number(container, .limit_window_seconds)
            used_percent = Self.number(container, .used_percent)
            reset_at = Self.number(container, .reset_at)
            reset_after_seconds = Self.number(container, .reset_after_seconds)
        }

        private static func number(_ container: KeyedDecodingContainer<CodingKeys>,
                                   _ key: CodingKeys) -> Double? {
            try? container.decode(Double.self, forKey: key)
        }
    }

    private struct ResetCreditsResponse: Decodable {
        let credits: [ResetCredit]
        let availableCount: Int?

        private enum CodingKeys: String, CodingKey {
            case credits
            case available_count
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            availableCount = try? container.decode(Int.self, forKey: .available_count)
            // One unreadable credit must not discard the rest of a valid list.
            let items = (try? container.decode([FailableResetCredit].self, forKey: .credits)) ?? []
            credits = items.compactMap(\.value)
        }
    }

    private struct FailableResetCredit: Decodable {
        let value: ResetCredit?
        init(from decoder: Decoder) throws {
            value = try? ResetCredit(from: decoder)
        }
    }

    private struct ResetCredit: Decodable {
        let id: String
        let status: String
        let expiresAt: Date?

        private enum CodingKeys: String, CodingKey {
            case id
            case status
            case expires_at
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
            if let text = try? container.decode(String.self, forKey: .expires_at) {
                expiresAt = parseISO8601(text)
            } else {
                expiresAt = nil
            }
        }
    }

    static func windows(from data: Data, now: Date = Date(),
                        includeExtras: Bool = true) throws -> [LimitWindow] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UsageProviderError.badResponse(status: 0)
        }

        var windows: [LimitWindow] = []
        for (id, window) in [("primary", response.rate_limit?.primary_window),
                             ("secondary", response.rate_limit?.secondary_window)] {
            guard let window else { continue }
            // One malformed window must not discard the other: a null
            // `used_percent` on the 5h window once threw the whole fetch away,
            // hiding a perfectly good weekly window behind an error.
            if let item = limitWindow(id: id, from: window, fallback: id, now: now) {
                windows.append(item)
            }
        }
        // After the main pair so `windows.first` stays primary. Two Spark
        // extras (plain "Spark" and "GPT-5.3-Codex-Spark") must not emit the
        // same ids twice: the tooltip ForEach, the archive, and Phone Link
        // all key windows by id, and a duplicate 5h row is what reads as a
        // second session limit.
        if includeExtras {
            for extra in response.additional_rate_limits where isSpark(extra) {
                appendExtra(
                    extra.rate_limit,
                    primaryID: "spark",
                    secondaryID: "spark-secondary",
                    group: L10n.t("Spark"),
                    now: now,
                    to: &windows
                )
            }
            appendExtra(
                response.code_review_rate_limit,
                primaryID: "code-review",
                secondaryID: "code-review-secondary",
                group: L10n.t("Code review"),
                now: now,
                to: &windows
            )
        }
        // No rolling windows at all: a credit-based seat. Its cap is the ring.
        if windows.isEmpty, let credit = response.spend_control?.individual_limit,
           let pct = credit.used_percent {
            let resets = credit.reset_at.map { Date(timeIntervalSince1970: $0) }
            windows.append(LimitWindow(id: "credits", label: L10n.t("Credits"),
                                       usedFraction: min(max(pct / 100, 0), 1),
                                       remaining: credit.limit.flatMap { l in credit.used.map { Int((l - $0).rounded()) } },
                                       used: credit.used.map { Int($0.rounded()) },
                                       resetsAt: resets))
        }
        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered(L10n.t("Codex reported no usage windows"))
        }
        return windows
    }

    /// The account tier the usage payload names, when it names one.
    static func plan(from data: Data) -> String? {
        (try? JSONDecoder().decode(Response.self, from: data))?.plan_type?.nonEmptyPlan
    }

    /// Decode the ChatGPT backend list of unused rate-limit resets.
    ///
    /// Same credential as `/wham/usage`. `available_count` is trusted even when
    /// the `credits` array is truncated. Throws only when the body is not JSON
    /// at all, so an unfamiliar payload cannot fail the usage fetch.
    static func resetCredits(from data: Data) throws -> UsageResetCredits {
        let response: ResetCreditsResponse
        do {
            response = try JSONDecoder().decode(ResetCreditsResponse.self, from: data)
        } catch {
            if (try? JSONSerialization.jsonObject(with: data)) != nil {
                return UsageResetCredits(availableCount: 0, credits: [])
            }
            throw UsageProviderError.badResponse(status: 0)
        }

        let credits = response.credits.map {
            UsageResetCredits.Credit(id: $0.id, status: $0.status, expiresAt: $0.expiresAt)
        }
        let availableCount = response.availableCount
            ?? credits.filter { $0.status == "available" }.count
        return UsageResetCredits(availableCount: availableCount, credits: credits)
    }

    /// The backend mixes whole-second and fractional ISO-8601 stamps; each
    /// formatter rejects the other form.
    private static func parseISO8601(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func limitWindow(
        id: String,
        group: String? = nil,
        from window: Window,
        fallback: String,
        now: Date
    ) -> LimitWindow? {
        guard let percent = window.used_percent else { return nil }
        let resetsAt = window.reset_at.map { Date(timeIntervalSince1970: $0) }
            ?? window.reset_after_seconds.map { now.addingTimeInterval($0) }
        return LimitWindow(
            id: id,
            group: group,
            label: label(windowSeconds: window.limit_window_seconds ?? 0, fallback: fallback),
            usedFraction: percent / 100,
            resetsAt: resetsAt,
            duration: window.limit_window_seconds
        )
    }

    private static func appendExtra(
        _ rateLimit: RateLimit?,
        primaryID: String,
        secondaryID: String,
        group: String,
        now: Date,
        to windows: inout [LimitWindow]
    ) {
        appendUnique(id: primaryID, window: rateLimit?.primary_window,
                     group: group, fallback: "primary", now: now, to: &windows)
        appendUnique(id: secondaryID, window: rateLimit?.secondary_window,
                     group: group, fallback: "secondary", now: now, to: &windows)
    }

    private static func appendUnique(
        id: String,
        window: Window?,
        group: String,
        fallback: String,
        now: Date,
        to windows: inout [LimitWindow]
    ) {
        guard let window, !windows.contains(where: { $0.id == id }) else { return }
        guard let item = limitWindow(id: id, group: group, from: window,
                                     fallback: fallback, now: now) else { return }
        windows.append(item)
    }

    private static func isSpark(_ extra: AdditionalRateLimit) -> Bool {
        [extra.limit_name, extra.metered_feature].contains { name in
            name?.range(of: "spark", options: .caseInsensitive) != nil
        }
    }

    /// The plan an account is on decides what its primary window actually is
    /// — a free plan has shown a 30-day window here, not the 5-hour one a paid
    /// plan reports — so the label is derived from the length Codex actually
    /// sent rather than assumed from a fixed pair of durations. Getting this
    /// wrong doesn't mislabel the window, it drops it: an unrecognised length
    /// used to be silently skipped, which on a free account left both windows
    /// absent and the ring reporting nothing metered at all.
    static func label(windowSeconds: Double, fallback: String) -> String {
        guard windowSeconds > 0 else {
            return fallback == "primary" ? L10n.t("Current session") : L10n.t("Longer window")
        }
        let minutes = windowSeconds / 60
        if minutes < 60 { return L10n.t("\(Int(minutes))m limit") }
        if minutes < 60 * 24 { return L10n.t("\(Int(minutes / 60))h limit") }
        let days = Int((minutes / (60 * 24)).rounded())
        switch days {
        case 7:  return L10n.t("Weekly limit")
        case 30: return L10n.t("Monthly limit")
        default: return L10n.t("\(days)d limit")
        }
    }
}
