import SwiftUI

/// Tags a skill carries, and the ones you gave it.
///
/// Two sources, deliberately. A `SKILL.md` may declare its own `tags:` and
/// those are the author's word for what it is; anything you add on top is
/// yours, kept here rather than written into somebody else's file. A skill in a
/// cloned repository must not come back from `git pull` with your filing
/// scribbled over it.
struct SkillTags: Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let key = "skillTags"

    /// Your tags, by skill folder name.
    var byName: [String: [String]] {
        defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
    }

    func own(_ name: String) -> [String] { byName[name] ?? [] }

    /// The author's plus yours, in that order, with duplicates dropped.
    func all(for name: String, declared: [String]) -> [String] {
        var seen = Set<String>()
        return (declared + own(name)).filter { seen.insert($0).inserted }
    }

    func add(_ tag: String, to name: String) {
        let tag = Self.normalise(tag)
        guard !tag.isEmpty else { return }
        var stored = byName
        var tags = stored[name] ?? []
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        stored[name] = tags
        defaults.set(stored, forKey: Self.key)
    }

    func remove(_ tag: String, from name: String) {
        var stored = byName
        let tags = (stored[name] ?? []).filter { $0 != tag }
        if tags.isEmpty { stored[name] = nil } else { stored[name] = tags }
        defaults.set(stored, forKey: Self.key)
    }

    /// Lower-cased, single-word, no punctuation to lead with. A tag is a thing
    /// to group by, and `Web` filtering to a different pile than `web` would be
    /// a bug the user can see and cannot explain.
    static func normalise(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#,;"))
            .lowercased()
    }

    /// A stable colour per tag.
    ///
    /// Derived from the text rather than stored, so a tag looks the same
    /// wherever it appears and a new one needs no decision. Hashed by hand:
    /// `hashValue` is seeded per process, so the same tag would change colour
    /// on every launch.
    static func colour(for tag: String) -> Color {
        var hash: UInt64 = 5381
        for byte in tag.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    private static let palette: [Color] = [
        .blue, .teal, .green, .orange, .pink, .purple, .indigo, .brown
    ]
}

