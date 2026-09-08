import Foundation

/// The projects Codenotch has been shown, and the folders it may link from.
///
/// Remembered rather than discovered. Finding projects would mean walking the
/// disk for `.git` directories and guessing which of the results the user
/// thinks of as a project, and being wrong about that means a sidebar of
/// somebody's `node_modules`. A project appears here because it was added.
///
/// Both lists are stored as paths and re-resolved on read, so a project that
/// has been moved or deleted disappears from the window instead of showing a
/// row that acts on nothing.
struct SkillProjectRegistry: Sendable {
    let defaults: UserDefaults
    let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    private static let projectsKey = "skillProjects"
    private static let originsKey = "skillOrigins"
    private static let pinnedKey = "skillPinnedProjects"
    private static let marksKey = "skillProjectMarks"

    // MARK: - Projects

    /// Pinned first, then in the order they were added.
    ///
    /// Sorted here rather than in the view because the order is a stored fact
    /// about the list, not a way of drawing it — a pin that only held while
    /// one window was open would not be a pin.
    var projects: [SkillProject] {
        let pinned = self.pinned
        let marks = self.marks
        return paths(forKey: Self.projectsKey)
            .filter { isDirectory($0) }
            .map { url in
                let path = url.standardizedFileURL.path
                return SkillProject(url: url,
                                    isPinned: pinned.contains(path),
                                    mark: marks[path] ?? .fallback)
            }
            .sorted { a, b in
                a.isPinned == b.isPinned ? false : a.isPinned
            }
    }

    /// Each project's icon and colour, by path.
    ///
    /// Stored as two plain strings each — a symbol name and a palette name —
    /// so nothing here has to be migrated when the palette changes, and an
    /// unknown name falls back rather than failing to decode.
    var marks: [String: ProjectMark] {
        let stored = defaults.dictionary(forKey: Self.marksKey) as? [String: [String: String]] ?? [:]
        return stored.compactMapValues { entry in
            guard let symbol = entry["symbol"], let color = entry["color"] else { return nil }
            return ProjectMark(symbol: symbol, color: color)
        }
    }

    func setMark(_ mark: ProjectMark, project url: URL) {
        var stored = defaults.dictionary(forKey: Self.marksKey) as? [String: [String: String]] ?? [:]
        stored[url.standardizedFileURL.path] = ["symbol": mark.symbol, "color": mark.color]
        defaults.set(stored, forKey: Self.marksKey)
    }

    private func removeMark(project url: URL) {
        var stored = defaults.dictionary(forKey: Self.marksKey) as? [String: [String: String]] ?? [:]
        stored[url.standardizedFileURL.path] = nil
        defaults.set(stored, forKey: Self.marksKey)
    }

    /// The projects held at the top. A set of paths rather than a flag on each
    /// row: the list is stored as paths, and a second parallel array is a
    /// second thing to keep in step.
    var pinned: Set<String> {
        Set(defaults.array(forKey: Self.pinnedKey) as? [String] ?? [])
    }

    func setPinned(_ wanted: Bool, project url: URL) {
        let path = url.standardizedFileURL.path
        var stored = pinned
        if wanted { stored.insert(path) } else { stored.remove(path) }
        defaults.set(Array(stored).sorted(), forKey: Self.pinnedKey)
    }

    func add(project url: URL) {
        add(url, forKey: Self.projectsKey)
    }

    func remove(project url: URL) {
        remove(url, forKey: Self.projectsKey)
        setPinned(false, project: url)
        removeMark(project: url)
    }

    // MARK: - Origins

    /// Folders holding skills that are not to be moved — a cloned skills
    /// repository, most often. Registered so links into them read as ours
    /// rather than as somebody else's arrangement.
    ///
    /// An origin is the folder that *contains* skill folders, so
    /// `~/GitHub/some-skills/skills` and not `~/GitHub/some-skills`.
    var origins: [URL] {
        paths(forKey: Self.originsKey).filter { isDirectory($0) }
    }

    func add(origin url: URL) {
        add(url, forKey: Self.originsKey)
    }

    func remove(origin url: URL) {
        remove(url, forKey: Self.originsKey)
    }

    // MARK: - Plumbing

    private func paths(forKey key: String) -> [URL] {
        (defaults.array(forKey: key) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
    }

    /// Appended, and deduplicated on the standardised path so the same folder
    /// reached two ways is one row.
    private func add(_ url: URL, forKey key: String) {
        let path = url.standardizedFileURL.path
        var stored = defaults.array(forKey: key) as? [String] ?? []
        guard !stored.contains(path) else { return }
        stored.append(path)
        defaults.set(stored, forKey: key)
    }

    private func remove(_ url: URL, forKey key: String) {
        let path = url.standardizedFileURL.path
        let stored = (defaults.array(forKey: key) as? [String] ?? []).filter { $0 != path }
        defaults.set(stored, forKey: key)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
