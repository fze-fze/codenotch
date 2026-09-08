import Foundation

/// Parsing an ISO-8601 timestamp, once, for everybody.
///
/// Providers disagree about fractional seconds — Claude and Cursor send them,
/// Codex sometimes does not — so a parser here has to try both spellings. Five
/// files had grown their own copy of exactly that, and each copy built its two
/// `ISO8601DateFormatter`s *inside* the function.
///
/// Building them is the expensive half. A formatter wraps a `CFDateFormatter`
/// and costs orders of magnitude more to create than a parse costs to run, and
/// `AntigravityActivity` was calling one of these copies once per line of every
/// transcript on disk — two formatters built and thrown away per line.
///
/// Held as `static let` rather than rebuilt: `ISO8601DateFormatter` is
/// documented as thread-safe so long as nothing mutates it after setup, and
/// nothing here does.
enum ISO8601Stamp {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Fractional first, because the stamps that carry them are the common
    /// case and a formatter that demands them rejects a whole-second value.
    static func date(from text: String) -> Date? {
        withFraction.date(from: text) ?? plain.date(from: text)
    }

    /// The same, for values coming out of an untyped JSON dictionary.
    static func date(_ any: Any?) -> Date? {
        guard let text = any as? String else { return nil }
        return date(from: text)
    }
}
