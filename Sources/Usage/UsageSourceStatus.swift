import Foundation

/// Why an agent contributed what it did to Usage — including, and especially,
/// when it contributed nothing.
///
/// A dashboard that renders a zero and stops is not reporting, it is hiding.
/// Zero has several quite different causes — the agent is not installed, it is
/// installed but has never been used, its folder moved, its files could not be
/// read, or this app was never taught to look — and only one of them is the
/// user's to fix. So each source carries the folders that were actually
/// checked, which of them exist, and what was found inside, and the panel says
/// which case this is.
struct UsageSourceStatus: Identifiable, Sendable, Equatable {
    let agent: UsageAgent
    /// Roots that exist, tilde-abbreviated for display.
    var folders: [String] = []
    /// Roots that were looked for and are not there.
    var missingFolders: [String] = []
    var files = 0
    var records = 0
    /// Files that were found but could not be parsed.
    var unreadable = 0
    /// A folder existed but could not be enumerated — a permissions answer,
    /// not an empty one.
    var inaccessible = false

    var id: String { agent.rawValue }

    /// Whether the row should read as a problem rather than a fact.
    var isProblem: Bool {
        guard agent.supportsHistory else { return false }
        if inaccessible || unreadable > 0 { return true }
        return files > 0 && records == 0
    }

    /// The headline, which has to answer "why is this zero" on its own.
    var summary: String {
        guard agent.supportsHistory else {
            return "Not collected — \(agent.historyDescription)"
        }
        if folders.isEmpty {
            return missingFolders.isEmpty ? "No folder configured" : "Not installed on this Mac"
        }
        if inaccessible { return "Folder could not be read" }
        if files == 0 { return "Installed, but no \(agent.historyDescription) yet" }
        if records == 0 { return "\(files) file\(files == 1 ? "" : "s") read, no token metadata inside" }
        var line = "\(records) generation\(records == 1 ? "" : "s") from \(files) file\(files == 1 ? "" : "s")"
        if unreadable > 0 { line += " · \(unreadable) unreadable" }
        return line
    }

    /// The folders behind that headline. Shown for every source that has any,
    /// so a wrong-looking number can be checked against a real path.
    var detail: String? {
        if !folders.isEmpty { return folders.joined(separator: "\n") }
        if !missingFolders.isEmpty { return missingFolders.joined(separator: "\n") }
        return nil
    }

    /// `~`-relative, because the absolute form is mostly the user's own name
    /// repeated and the interesting part is what follows it.
    static func abbreviate(_ url: URL, home: URL) -> String {
        let path = url.path
        let base = home.path
        guard path == base || path.hasPrefix(base + "/") else { return path }
        return "~" + path.dropFirst(base.count)
    }
}
