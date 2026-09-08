import AppKit

/// Light, dark, or whatever the Mac is doing.
///
/// An app-level override rather than a palette of its own. macOS already has
/// this switch and every other app follows it, so the only thing worth adding
/// is the ability to *not* follow it — for the one case the system setting
/// cannot express: a light Mac where this particular window is easier to read
/// dark, or the reverse.
enum AppAppearance: String, CaseIterable, Identifiable {
    /// Follow the Mac. The default, and what almost everyone should leave it on.
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// `nil` is not "no appearance" — it is *inherit*, which is exactly what
    /// following the system means.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// Applied to the application rather than to a window, so the panel, the
    /// notch and every menu agree — a dark panel over a light notch would be
    /// two apps.
    func apply(to app: NSApplication = .shared) {
        app.appearance = nsAppearance
    }
}
