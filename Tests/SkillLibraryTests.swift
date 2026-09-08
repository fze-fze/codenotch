import XCTest
@testable import Codenotch

/// The library at `~/.agents/skills`, and adopting into it.
final class SkillLibraryTests: SkillFixture {
    func testItListsSkillsWithTheirDescriptions() throws {
        try writeSkill("beta", at: library.root, description: "second")
        try writeSkill("alpha", at: library.root, description: "first")

        let skills = library.list()
        // Alphabetical rather than whatever order the filesystem hands back:
        // `contentsOfDirectory` promises no order, and a list that reshuffles
        // under the pointer between refreshes is its own bug.
        XCTAssertEqual(skills.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(skills.first?.summary, "first")
    }

    /// The library is shared with the rest of the ecosystem, so it holds things
    /// that are not skills. A folder without a `SKILL.md` is not one.
    func testAFolderWithoutAManifestIsNotASkill() throws {
        try FileManager.default.createDirectory(
            at: library.root.appendingPathComponent("notes"), withIntermediateDirectories: true
        )
        XCTAssertTrue(library.list().isEmpty)
    }

    func testAMissingLibraryIsEmptyRatherThanAnError() {
        XCTAssertTrue(library.list().isEmpty)
    }

    /// Adopting is a move, not a copy: the point is that there is **one** real
    /// folder afterwards, in the library, and everything else links to it.
    func testAdoptingMovesTheFolderIntoTheLibrary() throws {
        try install(.claudeCode)
        let original = try writeSkill("review",
                                      at: SkillAgent.claudeCode.ownSkillsDir(home: home))

        let adopted = try library.adopt(from: original)

        XCTAssertEqual(adopted.name, "review")
        XCTAssertEqual(adopted.summary, "does a thing")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: library.root.appendingPathComponent("review/SKILL.md").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path),
                       "the original was left behind, so there are now two copies to edit")
    }

    /// Two agents with a `review` skill each are two folders that may hold
    /// different text. Silently overwriting one with the other would lose work.
    func testANameAlreadyTakenIsRefusedRatherThanOverwritten() throws {
        try writeSkill("review", at: library.root, description: "the library's")
        let other = try writeSkill("review", at: home.appendingPathComponent("elsewhere"),
                                   description: "somebody else's")

        XCTAssertThrowsError(try library.adopt(from: other))
        XCTAssertEqual(library.list().first?.summary, "the library's")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path),
                      "the source was consumed by a refused adoption")
    }

    /// Adopting something that is already a link into the library — which is
    /// what a mounted skill looks like — must not move the library's own copy
    /// into itself.
    func testAdoptingAnAlreadyMountedSkillIsANoOp() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try mount.mount(name: "review", into: .claudeCode)

        let adopted = try library.adopt(
            from: mount.destination(name: "review", for: .claudeCode)
        )

        XCTAssertEqual(adopted.name, "review")
        XCTAssertEqual(library.list().count, 1)
        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .mounted)
    }

    /// The folder is prose someone wrote and there is no other copy once the
    /// mounts are gone. The Trash is an undo that already exists on every Mac.
    func testRemovingSendsItToTheTrashRatherThanDeletingIt() throws {
        try writeLibrarySkill("review")
        let source = library.root.appendingPathComponent("review")

        try library.remove(name: "review")

        XCTAssertTrue(library.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testRemovingSomethingAbsentIsNotAnError() {
        XCTAssertNoThrow(try library.remove(name: "ghost"))
    }

    /// The frontmatter may name the skill more prettily than the folder does,
    /// but the folder is what an agent matches on — so both are kept.
    func testTheFolderNameIsTheIdentityAndTheFrontmatterIsTheTitle() throws {
        let directory = library.root.appendingPathComponent("code-review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: Code Review\n---\n"
            .write(to: directory.appendingPathComponent("SKILL.md"),
                   atomically: true, encoding: .utf8)

        let skill = try XCTUnwrap(library.list().first)
        XCTAssertEqual(skill.name, "code-review")
        XCTAssertEqual(skill.displayName, "Code Review")
        XCTAssertEqual(skill.id, "code-review")
    }
}

/// Finding the skills each agent keeps to itself — the ones that reach only
/// that agent until they are promoted into the library.
final class SkillScanTests: SkillFixture {
    private var scan: SkillScan { SkillScan(home: home) }

    func testItFindsARealSkillInAnAgentsFolder() throws {
        try install(.claudeCode)
        try writeSkill("review", at: SkillAgent.claudeCode.ownSkillsDir(home: home))

        let found = scan.agentSkills()
        XCTAssertEqual(found.map(\.name), ["review"])
        XCTAssertEqual(found.first?.agent, .claudeCode)
        XCTAssertEqual(found.first?.summary, "does a thing")
    }

    /// A skill we already mounted is not something to adopt — offering it would
    /// be offering to move the library into itself.
    func testAManagedMountIsNotOfferedForAdoption() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try mount.mount(name: "review", into: .claudeCode)

        XCTAssertTrue(scan.agentSkills().isEmpty)
    }

    /// A link somewhere else is someone's deliberate arrangement, and copying
    /// the far end of it into the library would fork a file they expect to have
    /// one copy of.
    func testAForeignLinkIsLeftAlone() throws {
        try install(.claudeCode)
        let elsewhere = try writeSkill("review", at: home.appendingPathComponent("elsewhere"))
        let directory = SkillAgent.claudeCode.ownSkillsDir(home: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("review"), withDestinationURL: elsewhere
        )

        XCTAssertTrue(scan.agentSkills().isEmpty)
    }

    func testAFolderWithoutAManifestIsNotOffered() throws {
        try install(.claudeCode)
        try FileManager.default.createDirectory(
            at: SkillAgent.claudeCode.ownSkillsDir(home: home).appendingPathComponent("notes"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(scan.agentSkills().isEmpty)
    }

    /// A library skill is global, not Codex's own, however many agents read it.
    func testALibrarySkillIsNotReportedAsAnAgentsOwn() throws {
        try install(.codex)
        try writeLibrarySkill("review")
        XCTAssertTrue(scan.agentSkills().isEmpty)
    }

    /// The bug this whole revision exists to fix.
    ///
    /// Codex reads `~/.agents/skills` *and* keeps fifteen skills of its own in
    /// `~/.codex/skills`. The first version pointed Codex's only directory at
    /// the library and so never looked in its own folder — every one of those
    /// fifteen was invisible, and the window showed nothing to adopt.
    func testAnAgentThatAlsoReadsTheLibraryStillHasItsOwnFolderScanned() throws {
        try install(.codex)
        try writeSkill("codex-only", at: SkillAgent.codex.ownSkillsDir(home: home))

        let found = scan.agentSkills()
        XCTAssertEqual(found.map(\.name), ["codex-only"])
        XCTAssertEqual(found.first?.agent, .codex)
    }

    /// The vendors ship some fifty skills between them. They are read-only and
    /// they are not yours, so there is nothing to be done to one — listing them
    /// would be fifty inert rows between you and your own.
    func testVendorBundledSkillsAreNeverListed() throws {
        try install(.codex)
        try install(.cursor)
        try install(.grok)
        // Codex hides its own inside the folder that *is* scanned.
        try writeSkill("skill-creator",
                       at: home.appendingPathComponent(".codex/skills/.system"))
        try writeSkill("review", at: home.appendingPathComponent(".cursor/skills-cursor"))
        try writeSkill("commit", at: home.appendingPathComponent(".grok/bundled/skills"))

        XCTAssertTrue(scan.agentSkills().isEmpty)
    }

    /// The common case on a fresh install: the agent has been run, but has no
    /// skills folder yet. Nothing to offer, and nothing to fall over on.
    func testAnAgentWithNoSkillsFolderYieldsNothing() throws {
        try install(.claudeCode)
        XCTAssertTrue(scan.agentSkills().isEmpty)
    }

    /// Still listed — it is genuinely a skill that agent has — but flagged, so
    /// the UI can disable Promote and say why instead of letting the user press
    /// a button that can only fail.
    func testANameTheLibraryAlreadyHasIsListedButFlagged() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try writeSkill("review", at: SkillAgent.claudeCode.ownSkillsDir(home: home))

        let found = try XCTUnwrap(scan.agentSkills().first)
        XCTAssertEqual(found.name, "review")
        XCTAssertTrue(found.collidesWithLibrary)
    }

    func testANameNobodyElseHasIsNotFlagged() throws {
        try install(.claudeCode)
        try writeSkill("review", at: SkillAgent.claudeCode.ownSkillsDir(home: home))
        XCTAssertFalse(try XCTUnwrap(scan.agentSkills().first).collidesWithLibrary)
    }

    /// Two agents holding a `review` each are two folders that may hold
    /// different text. They get a row apiece: merging them would hide that, and
    /// the sidebar groups by agent precisely so you can see who has what.
    func testTheSameNameUnderTwoAgentsIsTwoRows() throws {
        try install(.claudeCode)
        try install(.antigravity)
        try writeSkill("review", at: SkillAgent.claudeCode.ownSkillsDir(home: home))
        try writeSkill("review", at: SkillAgent.antigravity.ownSkillsDir(home: home))

        let found = scan.agentSkills()
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Set(found.map(\.agent)), [.claudeCode, .antigravity])
        // Distinct ids, or the sidebar's selection would jump between them.
        XCTAssertEqual(Set(found.map(\.id)).count, 2)
    }
}
