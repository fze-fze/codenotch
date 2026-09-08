import Foundation

/// Presentation-only filtering, shared by the catalog and project lists.
struct SkillSearchQuery {
    var text = ""
    var tags: Set<String> = []

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty
    }

    func matches(name: String, displayName: String, summary: String?, tags available: [String]) -> Bool {
        let normalized = Set(available.map(SkillTags.normalise))
        guard Set(tags.map(SkillTags.normalise)).isSubset(of: normalized) else { return false }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.allSatisfy { word in
            if word.hasPrefix("#") {
                return normalized.contains(SkillTags.normalise(word))
            }
            return ([name, displayName, summary ?? ""] + available)
                .contains { $0.localizedStandardContains(word) }
        }
    }
}
