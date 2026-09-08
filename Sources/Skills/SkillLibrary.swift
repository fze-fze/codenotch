import Foundation
import os

/// One skill in the library.
struct LibrarySkill: Identifiable, Equatable, Sendable {
    /// The folder name, which is what every agent calls the skill regardless of
    /// what the frontmatter says. It is the id for that reason: two skills whose
    /// frontmatter claims the same `name` are still two skills, but two folders
    /// of the same name cannot coexist in one directory.
    let name: String
    let url: URL
    let frontmatter: SkillFrontmatter

    var id: String { name }

    /// What to print as the title. The frontmatter's `name` is allowed to be
    /// prettier than the folder ("Code Review" for `code-review`), but the
    /// folder is what the agent matches on, so both are shown in the UI.
    var displayName: String { frontmatter.name ?? name }
    var summary: String? { frontmatter.description }
}

enum SkillLibraryError: LocalizedError {
    /// A skill of this name is already in the library and is not the same one.
    case nameTaken(name: String)

    var errorDescription: String? {
        switch self {
        case .nameTaken(let name):
            return "The library already has a different skill called \(name). "
                 + "Rename one of them and try again."
        }
    }
}

/// The one real copy of every managed skill, at `~/.agents/skills`.
///
/// Not a directory of Codenotch's own. `~/.agents/skills` is where the
/// ecosystem settled — Codex, Cursor and Grok read it with no configuration —
/// so choosing it means three of the five agents are served by the library
/// existing at all, and the other two by a symlink. A private
/// `~/.codenotch/skills` would have been tidier and would have required five
/// links instead of two, for no gain.
///
/// It follows that the library is **shared**, not owned: other tools write here
/// too. Nothing in this type assumes an entry was put there by us.
struct SkillLibrary: Sendable {
    let home: URL
    let fileManager: FileManager

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    var root: URL { SkillAgent.sharedLibrary(home: home) }

    /// Every skill in the library, by folder name.
    ///
    /// Sorted so the list does not reshuffle between refreshes — `contentsOf`
    /// makes no ordering promise, and a list that reorders under the pointer is
    /// its own bug.
    func list() -> [LibrarySkill] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { SkillFrontmatter.isSkill(directory: $0, fileManager: fileManager) }
            .map {
                LibrarySkill(name: $0.lastPathComponent, url: $0,
                             frontmatter: SkillFrontmatter.read(skillDirectory: $0))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func contains(name: String) -> Bool {
        fileManager.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    /// Take a skill that lives in some agent's own directory and make the
    /// library's copy the real one.
    ///
    /// Copy, then verify, then remove the original — in that order. The reverse
    /// would put a window between "the only copy is gone" and "the new copy
    /// exists" wide enough to lose a skill in if the process died, and a skill
    /// someone wrote by hand is not something to be casual with.
    ///
    /// The original is replaced by a link to the library, so the agent that had
    /// it keeps it — adopting is not taking it away.
    func adopt(from source: URL, name: String? = nil) throws -> LibrarySkill {
        let name = name ?? source.lastPathComponent
        let destination = root.appendingPathComponent(name)

        if fileManager.fileExists(atPath: destination.path) {
            // Already the same folder — someone adopted it twice, or what was
            // handed to us is a link into the library. Nothing to do.
            //
            // Compared on `.path` and not on the URLs: `resolvingSymlinksInPath`
            // puts a trailing slash on a real directory but *not* on one it
            // reached through a symlink, and URL equality is string equality —
            // so the two sides of exactly this comparison came back unequal and
            // adopting a mounted skill was refused as a name clash.
            guard destination.resolvingSymlinksInPath().path
                    != source.resolvingSymlinksInPath().path else {
                return LibrarySkill(name: name, url: destination,
                                    frontmatter: SkillFrontmatter.read(skillDirectory: destination))
            }
            throw SkillLibraryError.nameTaken(name: name)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)

        guard SkillFrontmatter.isSkill(directory: destination, fileManager: fileManager) else {
            // The copy is not a skill, so the original must not be touched.
            try? fileManager.removeItem(at: destination)
            throw SkillMountError.missingInLibrary(name: name)
        }

        // The original goes to the trash rather than being deleted — the same
        // rule the whole app follows about other people's files. What replaces
        // it is the caller's job: `SkillManagerModel` mounts straight after, so
        // the agent that had the skill has it again a moment later.
        try trash(source)
        Log.usage.debug("adopted skill \(name, privacy: .public) into the library")
        return LibrarySkill(name: name, url: destination,
                            frontmatter: SkillFrontmatter.read(skillDirectory: destination))
    }

    /// Remove a skill from the library.
    ///
    /// To the trash, never `rm`: this is a folder of prose someone wrote, there
    /// is no other copy once the mounts are gone, and an undo that already
    /// exists on every Mac is better than one we would have to build.
    func remove(name: String) throws {
        let target = root.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try trash(target)
        Log.usage.debug("removed skill \(name, privacy: .public) from the library")
    }

    /// Move something to the Trash, falling back to a folder of our own when
    /// macOS refuses — which it does for files on another volume.
    private func trash(_ url: URL) throws {
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        } catch {
            let fallback = home.appendingPathComponent(".codenotch/trash")
            try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            try fileManager.moveItem(
                at: url,
                to: fallback.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
            )
        }
    }
}
