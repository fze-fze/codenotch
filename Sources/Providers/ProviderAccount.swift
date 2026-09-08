import Foundation

/// Whose readings these are.
///
/// Worth showing plainly, because Codenotch never signs in — it borrows a
/// credential the owning tool already holds, and there is nothing stopping that
/// credential belonging to a different account than the one you are sitting in
/// front of. It happened during development: a browser sign-in created a second,
/// empty Cursor account, and the notch spent an afternoon faithfully reporting
/// somebody else's zero. A visible email would have caught it in seconds.
struct ProviderAccount: Equatable {
    /// Email or display name, where the credential carries one.
    let label: String?
    /// The plan, named the way the provider names it.
    let plan: String?
    /// The provider's own usage page, for checking this against the source.
    let manageURL: URL?

    /// One line for the settings row. Which tool the credential is borrowed
    /// from used to be tacked on the end — "· via Cursor" on the Cursor row,
    /// on every row — and the row already says it.
    var summary: String {
        [label, plan.map(Self.titled)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Capitalises a wire token, and leaves a display name alone.
    ///
    /// Cursor hands over `"pro"`, which has to be title-cased before it can sit
    /// on a row. Grok hands over `"SuperGrok Heavy"` — already the form Grok
    /// itself prints — and `capitalized` lowercases the inner capitals of every
    /// word, so the unconditional call turned a brand into "Supergrok Heavy".
    /// A plan that already carries a capital has been written for reading.
    static func titled(_ plan: String) -> String {
        plan.contains(where: \.isUppercase) ? plan : plan.capitalized
    }
}

/// Where to go when a provider has no usable credential.
///
/// Codenotch cannot sign anyone in — it reads a credential the owning tool
/// holds — so the most it can honestly do is open that tool, or say what to do
/// when there is nothing to open.
enum SignInRoute: Equatable {
    /// The provider owns the session and can present its own sign-in window.
    /// The only case where Codenotch genuinely signs anyone in or out.
    case modal(name: String)
    /// Launch the app that owns the credential.
    case openApp(bundleID: String, name: String)
    /// Nothing to launch; Claude Code is a command, not an application.
    case guidance(String)

    var explanation: String {
        switch self {
        case .modal(let name):      return "Sign in to \(name) to read this account"
        case .openApp(_, let name): return "Sign in with \(name) to read this account"
        case .guidance(let text):   return text
        }
    }
}

extension UsageProvider {
    /// Providers that borrow no credential have no account to show.
    ///
    /// A default for a requirement *declared in the protocol* is fine — the
    /// requirement keeps dispatch dynamic, so an implementation still wins. It
    /// is declaring a method only in an extension that quietly breaks.
    func account() -> ProviderAccount? { nil }

    var signInRoute: SignInRoute {
        .guidance("Sign in with the tool that owns this account.")
    }

    /// Nothing of our own to discard, by default.
    func signOut() async {}

    /// No modal of our own to show, by default — `UsageStore.signIn` falls back
    /// to the route.
    func presentSignIn() {}

    /// Providers that hold nothing in memory have nothing to drop.
    func forgetCachedCredential() {}
}

/// A provider as the settings sheet needs it.
struct ProviderSummary: Identifiable, Equatable {
    /// Whether this provider's credential lives in the keychain, and so can be
    /// refused. Cursor and Codex read ordinary files and never prompt, so
    /// offering them an "allow access" button would be offering a cure for an
    /// illness they cannot catch.
    var usesKeychain: Bool { id == "claude" || id == "gemini" }

    let id: String
    let name: String
    let glyph: ProviderGlyph
    let account: ProviderAccount?
    let signIn: SignInRoute
}
