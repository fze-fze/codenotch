import Foundation

/// The clock and calendar formats the app prints, built once each.
///
/// Every one of these used to be a `DateFormatter()` created inside the
/// function that printed with it. That reads harmlessly, but the call sites are
/// not harmless: `ResetCopy.text` is a computed property of a tooltip row, so
/// it ran on every render of every window of every provider, and
/// `UsageBlock.summary` is reached from `tooltipRect` — which the window
/// controller calls on **every mouse-moved event**. A `DateFormatter` wraps a
/// `CFDateFormatter` and is among the most expensive objects in Foundation to
/// create; making one to print six characters and dropping it again was the
/// single largest source of allocation churn while the pointer was over the
/// notch.
///
/// Cached per time zone and locale rather than globally, because the pattern
/// alone does not determine the output and the tests hand in a calendar that is
/// deliberately not the machine's.
enum DateStyle {
    /// "Sep 28" — a day far enough out that the time of day is noise.
    /// Localised from a template, so regions that write the month first do.
    case dayAndMonth
    /// "Thu 12:00 AM" — a day inside the coming week.
    case weekdayAndTime
    /// "4:13 PM" — today, where the weekday would say nothing.
    case timeOnly

    func string(_ date: Date, calendar: Calendar = .current) -> String {
        Self.formatter(for: self, calendar: calendar).string(from: date)
    }

    // MARK: - The cache

    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    private static func formatter(for style: DateStyle, calendar: Calendar) -> DateFormatter {
        let locale = Locale.current
        let key = "\(style)|\(calendar.timeZone.identifier)|\(locale.identifier)"

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        // The calendar carries a time zone, and the callers count days in it.
        // A formatter left on the system zone let the two disagree about the
        // same instant — sorted as "inside the week" by one zone, then printed
        // with the other's clock. In production both are the current zone and
        // nothing shows; hand in a different one, as the tests do, and a reset
        // at noon in Bangkok prints as 1:00 PM.
        formatter.timeZone = calendar.timeZone
        switch style {
        case .dayAndMonth:    formatter.setLocalizedDateFormatFromTemplate("MMM d")
        // Literal patterns rather than localised templates: the weekday and
        // AM/PM still come from the locale, but the separator stays a colon.
        // The template form yields "4.50 PM" in some regions, and both the
        // design frame and Claude's own usage panel write "4:50 PM".
        case .weekdayAndTime: formatter.dateFormat = "E h:mm a"
        case .timeOnly:       formatter.dateFormat = "h:mm a"
        }
        cache[key] = formatter
        return formatter
    }
}
