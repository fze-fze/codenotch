import Foundation
import os

/// Gemini, as Antigravity sees it.
///
/// **What this can and cannot report, and why.** Antigravity talks to Google's
/// Cloud Code backend, and the only call that describes the account is
/// `:loadCodeAssist`. It answers with tiers — which plan you are on and which
/// you are not eligible for — and no numbers: no used, no limit, no reset. A
/// packet capture of a signed-in install showed exactly two RPCs, and neither
/// carries a quota.
///
/// So this provider reports the account honestly and says there is nothing
/// metered, rather than inventing a ring. That is the same answer Cursor's free
/// plan gets, and for the same reason: a confident 0% is worse than an admitted
/// blank, especially in something people pay for.
actor AntigravityProvider: UsageProvider {
    nonisolated let id = "gemini"
    // The id stays `gemini`: it keys the archive and the user's connection
    // choice, and changing it would silently discard both.
    nonisolated let displayName = "Antigravity"
    nonisolated let glyph = ProviderGlyph.antigravity

    /// The production host. Antigravity itself also calls a `daily-` variant,
    /// which answers 403 to this token — so it is not a fallback, it is a
    /// different audience.
    private let endpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    /// The real usage figure — when the account is allowed to ask for it.
    private let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    private let session: URLSession
    /// A second session, trusting loopback only, for the local language server.
    private let localSession: URLSession
    /// Re-discovering the port and token means spawning `ps` and `lsof`, which
    /// is not something to do every minute. Cached until it stops working.
    private var bridge: AntigravityBridge.Endpoint?
    private let defaults: UserDefaults

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        self.localSession = URLSession(configuration: .ephemeral,
                                       delegate: LocalhostTrust(),
                                       delegateQueue: nil)
    }

    /// When the language server last answered.
    ///
    /// Persisted, because it is a fact about the account and not about this
    /// run of the app. Held in memory alone it was forgotten by every
    /// relaunch — and a relaunch is not rare: `make run`, a restart, logging
    /// back in. The ring then went from a real percentage to "31" on the first
    /// refresh after launch, which is precisely the swap the flag exists to
    /// prevent. Same reasoning, and the same remedy, as the rate-limit
    /// back-off in `UsageArchive`.
    private var bridgedAt: Date? {
        get { defaults.object(forKey: Self.bridgedAtKey) as? Date }
        set {
            if let newValue { defaults.set(newValue, forKey: Self.bridgedAtKey) }
            else { defaults.removeObject(forKey: Self.bridgedAtKey) }
        }
    }

    private static let bridgedAtKey = "antigravityBridgedAt"

    /// Whether the language server has answered recently enough that its
    /// silence means Antigravity is *closed* rather than *gone*.
    ///
    /// Once it has, a failure is Antigravity being closed or restarted — its
    /// port changes every launch — not an account that cannot be read. Falling
    /// back to the request count then *replaces* a percentage with a plain
    /// number, and a ring that reads 8% one minute and 31 the next looks broken
    /// rather than degraded.
    ///
    /// Bounded rather than forever, at one whole reset cycle. An Antigravity
    /// that has been uninstalled should not hold a percentage on screen until
    /// the end of time; after a week with no answer, the count we can honestly
    /// take ourselves is the better of the two.
    private var everBridged: Bool { Self.hasBridged(at: bridgedAt, now: Date()) }

    static let bridgeMemory: TimeInterval = 7 * 24 * 60 * 60

    /// Split out so the window can be tested without a language server.
    static func hasBridged(at date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < bridgeMemory
    }

    nonisolated var signInRoute: SignInRoute {
        .openApp(bundleID: "com.google.antigravity", name: "Antigravity")
    }

    nonisolated func forgetCachedCredential() { AntigravityCredentials.forgetCached() }

    nonisolated func account() -> ProviderAccount? {
        guard let credentials = try? AntigravityCredentials.load() else { return nil }
        return ProviderAccount(
            label: nil,   // the token carries no address
            plan: credentials.authMethod == "consumer" ? "Personal" : credentials.authMethod,
            source: "Antigravity",
            manageURL: URL(string: "https://antigravity.google")
        )
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // Antigravity's own language server comes first, and deliberately
        // *before* the keychain. It holds the client identity Google insists
        // on, it answers with the same figure Antigravity's own usage panel
        // shows, and it wants nothing from us — no token, so no keychain read.
        //
        // That ordering is the whole fix for the hourly password prompt.
        // Reading Antigravity's keychain item is what put one on screen: the
        // item belongs to Google's team, Codenotch's signature is not on its
        // partition list, and "Always Allow" cannot add it there. Google
        // rotates the token about once an hour, the cached copy expires with
        // it, and the next refresh walked into the same locked door — roughly
        // one prompt an hour, for a credential that was never needed while
        // Antigravity was running.
        if let windows = await localQuota(), !windows.isEmpty {
            bridgedAt = Date()
            return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                    fidelity: .official, status: .ok, windows: windows,
                                    // The five-hour window, not the week: it is
                                    // the limit that actually stops work, and
                                    // the ring should lead with the one you hit.
                                    headlineID: "gemini-5h")
        }

        // Antigravity has answered before and is not answering now: keep the
        // last percentage, dimmed and dated, rather than swapping in a count.
        // `credentialExpired` is the store's word for "still true, just old".
        // Checked before the keychain for the same reason as above — there is
        // nothing this credential could tell us that would change the answer.
        if everBridged { throw UsageProviderError.credentialExpired }

        let credentials = try AntigravityCredentials.load()
        // Expired is not signed out: Antigravity refreshes this on its own the
        // next time it runs, and the last reading is still true, just old.
        if credentials.isExpired { throw UsageProviderError.credentialExpired }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // `GEMINI` and not `ANTIGRAVITY`: the latter is rejected outright with
        // "Invalid value at 'metadata.plugin_type'". The wire name lags the
        // product name.
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["metadata": ["pluginType": "GEMINI"]]
        )
        request.timeoutInterval = 15

        // The body is discarded: this call is here for what its *status* says
        // about the account, and nothing on screen shows the plan's name any
        // more. `tier(in:)` stays for the shape it pins in the tests.
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 {
            // Same reasoning as Claude's: rejected but unexpired means the
            // account underneath has changed.
            AntigravityCredentials.forgetCached()
            throw UsageProviderError.needsAuth
        }
        if status == 403 { throw UsageProviderError.needsAuth }
        if status == 429 {
            let retry = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageProviderError.rateLimited(retryAfter: retry ?? 0)
        }
        guard status == 200 else { throw UsageProviderError.badResponse(status: status) }

        // Google directly, which answers for a licensed account.
        if let windows = try await quota(token: credentials.accessToken), !windows.isEmpty {
            return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                    fidelity: .official, status: .ok, windows: windows)
        }

        // Not licensed, so Google will not say how much of what. Our own count
        // is the only number left — reported as a *count*, with no
        // `usedFraction`, which is a case the model already knows: the cell
        // prints the number and the ring draws its track with no arc, because
        // there is no limit to be a fraction of.
        //
        // Better than the dash it showed before, which read as broken rather
        // than as "Google will not answer for this account".
        let activity = AntigravityActivity.read()
        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            // Ours, not Google's. The tooltip prefixes a `~` on the strength of
            // this, which is exactly the claim being made.
            fidelity: .derived,
            status: .ok,
            windows: [
                LimitWindow(id: "requests",
                            label: "Requests today · no limit published",
                            used: activity.requestsToday)
            ]
        )
    }

    /// Ask Antigravity's language server, if it is running.
    ///
    /// Returns nil rather than throwing when it is not: Antigravity being
    /// closed is the ordinary case, not a fault, and the caller has an honest
    /// answer to fall back to.
    private func localQuota() async -> [LimitWindow]? {
        if let bridge, let windows = try? await AntigravityBridge.quota(
            from: bridge, session: localSession
        ), !windows.isEmpty {
            return windows
        }
        // Cached endpoint gone or never found: the port changes every time
        // Antigravity restarts, so a stale one is expected, not exceptional.
        guard let fresh = AntigravityBridge.discover() else {
            bridge = nil
            return nil
        }
        bridge = fresh
        return try? await AntigravityBridge.quota(from: fresh, session: localSession)
    }

    /// Ask for the account's quota, returning nil when it is not allowed to.
    ///
    /// A free or personal account answers 403 #3501, "You do not have a valid
    /// license of this product" — the endpoint exists and the request is well
    /// formed, the entitlement is what is missing. That is not an error worth
    /// alarming anyone about, so it returns nil and the caller falls back.
    private func quota(token: String) async throws -> [LimitWindow]? {
        var request = URLRequest(url: quotaEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Empty on purpose. The request message carries no fields — sending
        // `metadata` or `quotaId` is rejected outright with "Unknown name".
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.windows(in: data)
    }

    /// Turns a quota summary into limit windows.
    ///
    /// Written from the message names in Antigravity's own binary
    /// (`QuotaSummaryGroup`, `QuotaSummaryBucket`, `QuotaLimit`) because no
    /// licensed account was available to answer with a real body. So it is
    /// deliberately suspicious of itself: anything without a positive limit, or
    /// claiming more used than the limit allows, is dropped rather than shown.
    /// An empty result sends the caller to the honest fallback, which is the
    /// right outcome for a shape that turns out to differ.
    static func windows(in data: Data) -> [LimitWindow] {
        struct Response: Decodable {
            struct Bucket: Decodable {
                let name: String?
                let displayName: String?
                let used: Double?
                let limit: Double?
                let resetTime: String?
            }
            struct Group: Decodable {
                let displayName: String?
                let buckets: [Bucket]?
            }
            let quotaGroups: [Group]?
            let buckets: [Bucket]?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        // Paired with the group it came from rather than flattened away. The
        // group names the models and the bucket names the window, and a row
        // labelled with one of the two is ambiguous the moment there is more
        // than one of the other — which is exactly what went wrong on the
        // bridge path. Ungrouped buckets carry no models, and say so by
        // passing nil.
        let grouped = (decoded.quotaGroups ?? []).flatMap { group in
            (group.buckets ?? []).map { (models: group.displayName, bucket: $0) }
        } + (decoded.buckets ?? []).map { (models: String?.none, bucket: $0) }

        return grouped.compactMap { models, bucket in
            guard let limit = bucket.limit, limit > 0,
                  let used = bucket.used, used >= 0, used <= limit * 1.5
            else { return nil }
            return LimitWindow(
                id: bucket.name ?? bucket.displayName ?? "quota",
                label: AntigravityBridge.label(models: models,
                                               bucketId: bucket.name,
                                               window: nil,
                                               bucketName: bucket.displayName),
                usedFraction: used / limit,
                resetsAt: bucket.resetTime.flatMap(AntigravityCredentials.parse))
        }
    }

    /// The plan's display name, for the message the cell shows.
    static func tier(in data: Data) -> String {
        struct Response: Decodable {
            struct Tier: Decodable {
                let id: String?
                let name: String?
                let isDefault: Bool?
            }
            let allowedTiers: [Tier]?
            let currentTier: Tier?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return "Gemini"
        }
        // `currentTier` appears once a tier has been chosen; before that the
        // default among the allowed ones is what you are on.
        let tier = decoded.currentTier
            ?? decoded.allowedTiers?.first(where: { $0.isDefault == true })
            ?? decoded.allowedTiers?.first
        return tier?.name ?? "Gemini"
    }
}
