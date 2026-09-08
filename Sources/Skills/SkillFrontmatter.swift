import Foundation

/// The `name` and `description` at the top of a `SKILL.md`.
///
/// Hand-rolled rather than a YAML library, because this project has no package
/// dependencies and adding one to read two strings would be the tail wagging the
/// dog. What it understands is exactly what the Agent Skills format asks for —
/// a leading `---` block of `key: value` lines — and everything richer (nested
/// maps, block scalars, anchors) is ignored rather than mis-parsed.
///
/// Nothing here throws. A skill with unreadable frontmatter is still a skill;
/// it just shows its folder name and no description, which is a better outcome
/// than refusing to list it.
struct SkillFrontmatter: Equatable, Sendable {
    var name: String?
    var description: String?
    /// Whatever the file calls its own subject — `tags`, `keywords` or
    /// `category`. Three spellings because the format does not settle it and
    /// the skills on this machine use all three; they mean the same thing to a
    /// person scanning a wall of cards.
    var tags: [String] = []

    static let empty = SkillFrontmatter(name: nil, description: nil)

    /// Reads the frontmatter out of a `SKILL.md`'s text.
    static func parse(_ text: String) -> SkillFrontmatter {
        // Split on any of the three line endings a file written on another
        // platform might carry.
        var lines = text.components(separatedBy: .newlines)

        // A leading BOM survives `String(contentsOf:)` and would stop the first
        // line matching `---`, which throws the whole block away.
        if let first = lines.first, first.hasPrefix("\u{FEFF}") {
            lines[0] = String(first.dropFirst())
        }

        // Skip blank lines before the opening fence — some editors leave one.
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        guard index < lines.count,
              lines[index].trimmingCharacters(in: .whitespaces) == "---"
        else { return .empty }
        index += 1

        var found = SkillFrontmatter.empty
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // `...` closes a YAML document too, and a file that never closes
            // its fence at all should not swallow the entire body as keys.
            if trimmed == "---" || trimmed == "..." { break }
            index += 1

            // Indented lines belong to a nested structure this does not read —
            // a `metadata:` block's children must not be mistaken for keys of
            // their own.
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            guard !isIndented, !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }

            let key = String(trimmed[trimmed.startIndex..<colon])
                .trimmingCharacters(in: .whitespaces).lowercased()
            let raw = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // A key with nothing after the colon may be a block *sequence* —
            // the `- item` lines below it. Read before the block-scalar check,
            // which would take the same empty value and find no text.
            if raw.isEmpty, Self.tagKeys.contains(key) {
                let items = Self.readSequence(from: lines, at: &index)
                if !items.isEmpty { found.tags += items }
                continue
            }

            let value: String
            if let fold = BlockScalar(indicator: raw) {
                // A block scalar: the text is on the *following* indented lines
                // and this line only says how to read them. Taken as an ordinary
                // value it yields ">", which is exactly what four of the skills
                // on this machine displayed as their entire description.
                value = Self.readBlock(fold, from: lines, at: &index)
            } else {
                value = unquote(raw)
            }
            guard !value.isEmpty else { continue }

            switch key {
            case "name":        found.name = value
            case "description": found.description = value
            case _ where Self.tagKeys.contains(key):
                found.tags += Self.splitTags(value)
            default:            break
            }
        }
        return found
    }

    private static let tagKeys: Set<String> = ["tags", "keywords", "category", "categories"]

    /// `[a, b]`, `a, b` and `a b` all mean the same list of words.
    ///
    /// Lower-cased and de-duplicated, because a tag is something to group by:
    /// `Web` and `web` filtering to two different piles would be a bug the user
    /// could see and not explain.
    static func splitTags(_ value: String) -> [String] {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("["), text.hasSuffix("]") {
            text = String(text.dropFirst().dropLast())
        }
        let separators = CharacterSet(charactersIn: ",;")
        var seen = Set<String>()
        return text.components(separatedBy: separators)
            .flatMap { $0.components(separatedBy: .whitespaces) }
            .map { unquote($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    /// The `- item` lines under a key, consumed from `index`.
    private static func readSequence(from lines: [String], at index: inout Int) -> [String] {
        var items: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed == "-" else { break }
            index += 1
            let item = unquote(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                .lowercased()
            if !item.isEmpty { items.append(item) }
        }
        return items
    }

    /// Reads a skill directory's `SKILL.md`. Absent or unreadable is empty, not
    /// an error — see the type comment.
    static func read(skillDirectory: URL) -> SkillFrontmatter {
        let file = skillDirectory.appendingPathComponent(SkillFrontmatter.manifestName)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return .empty }
        return parse(text)
    }

    /// The one file that makes a folder a skill.
    static let manifestName = "SKILL.md"

    /// Whether this directory is a skill at all.
    static func isSkill(directory: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(
            atPath: directory.appendingPathComponent(manifestName).path
        )
    }

    /// How a `>` or `|` block joins its lines.
    ///
    /// The two that matter: **folded** wraps, so its newlines are really spaces
    /// and a description written across eight lines is one sentence; **literal**
    /// keeps them. The chomping suffixes (`-`, `+`) only govern trailing
    /// newlines, which a trimmed one-line summary never shows, so they are
    /// accepted and otherwise ignored.
    private enum BlockScalar {
        case folded
        case literal

        init?(indicator: String) {
            guard let first = indicator.first, first == ">" || first == "|" else { return nil }
            // Anything after the indicator must be a chomping or indentation
            // modifier — never text. `description: > see below` is not a block
            // scalar at all, and reading it as one would swallow the next key.
            let rest = indicator.dropFirst()
            guard rest.allSatisfy({ $0 == "-" || $0 == "+" || $0.isNumber }) else { return nil }
            self = first == ">" ? .folded : .literal
        }
    }

    /// Consume the indented lines belonging to a block scalar.
    ///
    /// `index` is left on the first line that is *not* part of the block, so
    /// the caller's loop reads the next key as usual.
    private static func readBlock(_ kind: BlockScalar,
                                  from lines: [String],
                                  at index: inout Int) -> String {
        var collected: [String] = []
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // A blank line is inside the block if the block continues after it,
            // so it is kept for now and trimmed off the end below.
            if trimmed.isEmpty {
                collected.append("")
                index += 1
                continue
            }
            guard line.hasPrefix(" ") || line.hasPrefix("\t") else { break }
            collected.append(trimmed)
            index += 1
        }

        while collected.last?.isEmpty == true { collected.removeLast() }

        switch kind {
        case .literal:
            return collected.joined(separator: "\n")
        case .folded:
            // Folded really does mean folded: a blank line is a paragraph break
            // and survives as a newline, everything else becomes one space.
            var paragraphs: [String] = []
            var current: [String] = []
            for line in collected {
                if line.isEmpty {
                    if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
                    current = []
                } else {
                    current.append(line)
                }
            }
            if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
            return paragraphs.joined(separator: "\n")
        }
    }

    private static func unquote(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2
            && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
