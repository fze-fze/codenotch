import Foundation
import SQLite3

/// Reads live account limits using the session owned and refreshed by Codex.
actor CodexLocalProvider: UsageProvider {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let glyph = ProviderGlyph.openai
    nonisolated let profile: CodexProfile

    private let session: URLSession
    nonisolated private let authURL: URL
    private let archive: UsageArchive
    private var retryNoEarlierThan: Date?

    init(profile: CodexProfile = .default(),
         session: URLSession = .shared,
         authURL: URL? = nil,
         archive: UsageArchive = UsageArchive()) {
        self.profile = profile
        self.id = profile.id
        self.displayName = profile.displayName
        self.session = session
        self.authURL = authURL ?? profile.authURL
        self.archive = archive
        // Recreating the provider or relaunching must not bypass the server's retry deadline.
        self.retryNoEarlierThan = archive.loadBackoffUntil(providerID: profile.id)
    }

    nonisolated var signInRoute: SignInRoute {
        guard profile.slug != nil else { return .openApp(bundleID: "com.openai.codex", name: "Codex") }
        return .command(profile.signInCommand, name: displayName,
                        install: URL(string: "https://developers.openai.com/codex/cli"))
    }

    nonisolated func account() -> ProviderAccount? {
        CodexCredentials.account(from: authURL, source: profile.sourceName)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let now = Date()
        if let retryNoEarlierThan, retryNoEarlierThan > now {
            throw UsageProviderError.rateLimited(retryAfter: retryNoEarlierThan.timeIntervalSince(now))
        }

        // Codex can rotate its token between polls; this app never refreshes or writes it.
        let credential = try CodexCredentials.load(from: authURL)
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 || status == 403 { throw UsageProviderError.needsAuth }
        if status == 429 {
            let receivedAt = Date()
            let delay = max(60, Self.retryAfter(from: http, now: receivedAt) ?? 0)
            retryNoEarlierThan = receivedAt.addingTimeInterval(delay)
            archive.saveBackoffUntil(retryNoEarlierThan, providerID: id)
            throw UsageProviderError.rateLimited(retryAfter: delay)
        }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }

        // Unused resets are a separate endpoint from the extra Spark / code-review
        // windows. Start that fetch before parsing extras so a slow or empty
        // extras payload cannot skip the credits row.
        async let resetCredits = Self.fetchResetCredits(session: session, credential: credential)

        let windows = try CodexUsage.windows(
            from: data,
            includeExtras: Preferences.storedShowCodexExtraLimits()
        )

        retryNoEarlierThan = nil
        archive.saveBackoffUntil(nil, providerID: id)
        return ProviderSnapshot(
            id: id, displayName: displayName, glyph: glyph,
            fidelity: .official, status: .ok, windows: windows,
            // Named, not positional. `windows.first` would let Spark take the
            // ring whenever primary is missing — extras are appended after the
            // main pair, but a Spark-only payload still leads with spark.
            headlineID: "primary",
            // The weekly ring is the account weekly, never Spark's own weekly.
            weeklyID: "secondary",
            plan: CodexUsage.plan(from: data) ?? account()?.plan?.nonEmptyPlan,
            resetCredits: await resetCredits
        )
    }

    /// Unused rate-limit resets on this Codex account, listed by the same
    /// backend as usage.
    private static func fetchResetCredits(
        session: URLSession,
        credential: CodexCredentials.Credential
    ) async -> UsageResetCredits? {
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return nil }
            return try CodexUsage.resetCredits(from: data)
        } catch {
            return nil
        }
    }

    private static func retryAfter(from response: HTTPURLResponse?, now: Date) -> TimeInterval? {
        guard let header = response?.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        if let seconds = TimeInterval(header), seconds.isFinite { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}
