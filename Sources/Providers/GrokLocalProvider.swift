import Foundation
import os

/// Reads Grok Build usage from the same billing endpoint the CLI's `/usage` uses.
///
/// The credential is Grok's own `~/.grok/auth.json` session — the CLI's job to
/// refresh, not this app's. Credits (`?format=credits`) is the weekly
/// allowance, and the only usage number this endpoint actually states.
actor GrokLocalProvider: UsageProvider {
    nonisolated let id = "grok"
    nonisolated let displayName = "Grok"
    nonisolated let glyph = ProviderGlyph.grok

    private let creditsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private let settingsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!
    private let session: URLSession
    private let authURL: URL
    private let defaults: UserDefaults

    init(session: URLSession = .shared,
         authURL: URL = GrokCredentials.authURL,
         defaults: UserDefaults = .standard) {
        self.session = session
        self.authURL = authURL
        self.defaults = defaults
    }

    nonisolated var signInRoute: SignInRoute {
        .guidance("Run grok login — it signs in and refreshes the token this reads.")
    }

    nonisolated func account() -> ProviderAccount? {
        GrokCredentials.account(plan: Self.storedPlan(from: defaults)?.name)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let credentials = try GrokCredentials.load(from: authURL)
        if credentials.isExpired { throw UsageProviderError.credentialExpired }

        let credits = try await body(from: creditsURL, token: credentials.accessToken)
        Log.usage.debug("grok credits -> \(credits.prefix(400), privacy: .public)")

        // After the reading, and never in front of it: the plan is a nicety on
        // the settings row, and a settings endpoint having a bad day must not
        // be what stops a ring being drawn.
        await refreshStoredPlan(token: credentials.accessToken)

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: try GrokUsage.windows(creditsJSON: credits),
            headlineID: "credits"
        )
    }

    // MARK: - Plan

    /// The plan's name, and when it was read.
    ///
    /// Persisted because it is a fact about the account rather than about this
    /// run of the app, and because the settings sheet asks for the account
    /// *synchronously* while the only endpoint that states a plan is a network
    /// call away. Same bargain, and same shape, as Antigravity's stored account.
    struct StoredPlan: Codable, Equatable {
        var name: String
        var at: Date
    }

    private static let planKey = "grokPlan"

    /// How long a stored plan is trusted before it is asked for again. A tier
    /// does not change hourly, and this rides along with a reading that already
    /// happens every 60 seconds.
    static let planRefreshInterval: TimeInterval = 6 * 60 * 60

    /// How long a stored plan outlives the last successful read, after which a
    /// signed-out account stops naming a plan it may no longer be on.
    static let planMemory: TimeInterval = 7 * 24 * 60 * 60

    /// Split out so the window can be tested without an endpoint.
    static func isFresh(_ stored: StoredPlan?, now: Date) -> Bool {
        guard let stored else { return false }
        return now.timeIntervalSince(stored.at) < planMemory
    }

    /// The read half, reachable from `nonisolated` code.
    nonisolated static func storedPlan(from defaults: UserDefaults) -> StoredPlan? {
        guard let data = defaults.data(forKey: planKey),
              let stored = try? JSONDecoder().decode(StoredPlan.self, from: data),
              isFresh(stored, now: Date())
        else { return nil }
        return stored
    }

    /// Asks Grok what this account's plan is called, at most every few hours.
    /// Failure is silent: the plan is worth an answer, not a broken reading.
    private func refreshStoredPlan(token: String) async {
        let stored = Self.storedPlan(from: defaults)
        if let stored, Date().timeIntervalSince(stored.at) < Self.planRefreshInterval { return }
        guard let settings = try? await body(from: settingsURL, token: token),
              let name = GrokSettings.tier(settingsJSON: settings)
        else { return }
        if let data = try? JSONEncoder().encode(StoredPlan(name: name, at: Date())) {
            defaults.set(data, forKey: Self.planKey)
        }
    }

    // MARK: - Transport

    private func body(from url: URL, token: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw UsageProviderError.needsAuth }
        if status == 429 {
            throw UsageProviderError.rateLimited(retryAfter: 60)
        }
        guard (200..<300).contains(status),
              let text = String(data: data, encoding: .utf8)
        else { throw UsageProviderError.badResponse(status: status) }
        return text
    }
}
