import SwiftUI
import XCTest
@testable import Codenotch

/// The project half of the Skill Manager.
///
/// The layout under test is not invented: marker skills were planted in every
/// candidate directory of a scratch project and each agent was asked what it
/// could see. Codex, Cursor and Antigravity read `<project>/.agents/skills`
/// themselves; Claude Code reads only `<project>/.claude/skills`, and follows
/// it through a symlink. These tests pin that arrangement.
final class SkillProjectTests: XCTestCase {
    private var home: URL!
    private var project: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        project = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock { [home, project] in
            try? FileManager.default.removeItem(at: home!)
            try? FileManager.default.removeItem(at: project!)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func makeSkill(_ name: String, in directory: URL,
                           description: String = "does a thing") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("""
        ---
        name: \(name)
        description: \(description)
        ---

        # \(name)
        """.utf8).write(to: url.appendingPathComponent("SKILL.md"))
        return url
    }

    private func store(origins: [URL] = []) -> SkillStore {
        SkillStore(home: home, origins: origins)
    }

    private func mount(origins: [URL] = []) -> SkillProjectMount {
        SkillProjectMount(project: project, store: store(origins: origins))
    }

    private var storeRoot: URL { home.appendingPathComponent(".codenotch/skills") }
    private var libraryRoot: URL { home.appendingPathComponent(".agents/skills") }

    // MARK: - Linking

    func testLinkingPutsTheSkillWhereThreeOfFourAgentsAlreadyLook() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("pdf", in: storeRoot)
        let skill = try XCTUnwrap(store().available().first)

        let mount = self.mount()
        XCTAssertEqual(mount.state(name: "pdf"), .notMounted)
        try mount.link(skill)

        XCTAssertEqual(mount.state(name: "pdf"), .mounted)
        let linked = project.appendingPathComponent(".agents/skills/pdf")
        let raw = try FileManager.default.destinationOfSymbolicLink(atPath: linked.path)
        XCTAssertTrue(raw.hasPrefix("/"),
                      "Absolute: the target is outside the project, and a relative "
                      + "path out of a project depends on where the project sits")
        // Both sides resolved: `/var` is a symlink to `/private/var`, so the
        // path a test builds and the path the filesystem hands back differ by
        // a prefix that means nothing here.
        XCTAssertEqual(URL(fileURLWithPath: raw).resolvingSymlinksInPath().path,
                       storeRoot.appendingPathComponent("pdf").resolvingSymlinksInPath().path)
    }

    /// Linking is what a project does most often, so doing it twice must be
    /// the same as doing it once.
    func testLinkingTwiceIsTheSameAsLinkingOnce() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("pdf", in: storeRoot)
        let skill = try XCTUnwrap(store().available().first)
        let mount = self.mount()

        try mount.link(skill)
        try mount.link(skill)
        XCTAssertEqual(mount.state(name: "pdf"), .mounted)
        XCTAssertEqual(mount.installed().count, 1)
    }

    func testUnlinkingRemovesOnlyTheLink() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let real = try makeSkill("pdf", in: storeRoot)
        let skill = try XCTUnwrap(store().available().first)
        let mount = self.mount()

        try mount.link(skill)
        try mount.unlink(name: "pdf")

        XCTAssertEqual(mount.state(name: "pdf"), .notMounted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.path),
                      "The real folder is in the store and is never touched")
    }

    /// A real folder in `.agents/skills` is the project's own skill, written
    /// for it and committed with it. It is listed, and it is never linked over
    /// or deleted.
    func testAProjectsOwnSkillIsListedAndLeftAlone() throws {
        let skillsDir = project.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try makeSkill("house-style", in: skillsDir)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("house-style", in: storeRoot)
        let skill = try XCTUnwrap(store().available().first)

        let mount = self.mount()
        let listed = mount.installed()
        XCTAssertEqual(listed.map(\.name), ["house-style"])
        XCTAssertTrue(listed[0].isOwn)

        XCTAssertThrowsError(try mount.link(skill))
        XCTAssertThrowsError(try mount.unlink(name: "house-style"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: skillsDir.appendingPathComponent("house-style/SKILL.md").path))
    }

    /// A link into a folder that is gone is debris, not an arrangement: there
    /// is no content behind it to lose, and the agent is looking at a broken
    /// skill until it is replaced.
    func testABrokenLinkIsReplacedRatherThanRefused() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("pdf", in: storeRoot)
        let skill = try XCTUnwrap(store().available().first)

        let skillsDir = project.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: skillsDir.appendingPathComponent("pdf").path,
            withDestinationPath: "/nowhere/at/all/pdf")

        let mount = self.mount()
        XCTAssertTrue(mount.state(name: "pdf").isBrokenLink)
        try mount.link(skill)
        XCTAssertEqual(mount.state(name: "pdf"), .mounted)
    }

    /// Somebody else's link, pointing at something that exists, is their
    /// arrangement — reported and never overwritten.
    func testAForeignLinkIsReported() throws {
        let elsewhere = home.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try makeSkill("pdf", in: elsewhere)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("pdf", in: storeRoot)
        let skill = try XCTUnwrap(store().available().first)

        let skillsDir = project.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skillsDir.appendingPathComponent("pdf"),
            withDestinationURL: elsewhere.appendingPathComponent("pdf"))

        let mount = self.mount()
        guard case .conflict(.foreignLink) = mount.state(name: "pdf") else {
            return XCTFail("expected a foreign link, got \(mount.state(name: "pdf"))")
        }
        XCTAssertThrowsError(try mount.link(skill))
    }

    /// A registered origin is a root like any other, so a link into a cloned
    /// repository is ours to manage rather than somebody else's arrangement.
    func testALinkIntoARegisteredOriginIsOurs() throws {
        let repo = home.appendingPathComponent("GitHub/some-skills/skills")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try makeSkill("comic", in: repo)

        let mount = self.mount(origins: [repo])
        let skill = try XCTUnwrap(store(origins: [repo]).available().first)
        try mount.link(skill)
        XCTAssertEqual(mount.state(name: "comic"), .mounted)

        // The same link, with the origin forgotten, is not ours to touch.
        XCTAssertNotEqual(self.mount().state(name: "comic"), .mounted)
    }

    // MARK: - The Claude bridge

    func testTheBridgeIsRelativeSoItSurvivesBeingCloned() throws {
        let mount = self.mount()
        XCTAssertEqual(mount.claudeBridge, .absent)
        try mount.mountClaudeBridge()

        XCTAssertEqual(mount.claudeBridge, .linked)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: project.appendingPathComponent(".claude/skills").path),
            "../.agents/skills",
            "Relative: this link never leaves the project, and a relative one is "
            + "true wherever the project is checked out — so it can be committed"
        )
    }

    func testBridgingTwiceIsTheSameAsBridgingOnce() throws {
        let mount = self.mount()
        try mount.mountClaudeBridge()
        try mount.mountClaudeBridge()
        XCTAssertEqual(mount.claudeBridge, .linked)
    }

    /// A project that keeps real Claude-only skills of its own has a real
    /// `.claude/skills`. Replacing it with a link would delete them.
    func testARealClaudeDirectoryIsNeverReplaced() throws {
        let claudeDir = project.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try makeSkill("claude-only", in: claudeDir)

        let mount = self.mount()
        XCTAssertEqual(mount.claudeBridge, .ownDirectory)
        XCTAssertThrowsError(try mount.mountClaudeBridge())
        XCTAssertThrowsError(try mount.removeClaudeBridge())
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: claudeDir.appendingPathComponent("claude-only/SKILL.md").path))
    }

    /// Adding a project sets it up. A project that arrives already warning
    /// about a step nobody has been offered is a project that looks broken on
    /// arrival.
    func testPreparingAProjectMakesBothLinks() throws {
        try Data("# Project\n".utf8).write(to: project.appendingPathComponent("AGENTS.md"))

        let mount = self.mount()
        mount.prepare()

        XCTAssertEqual(mount.claudeBridge, .linked)
        XCTAssertEqual(mount.instructions, .linked)
        XCTAssertTrue(mount.isPrepared)
    }

    /// With nothing to point CLAUDE.md at, only the skills bridge is made —
    /// and no AGENTS.md is invented.
    func testPreparingWithNoInstructionsLeavesThemAlone() {
        let mount = self.mount()
        mount.prepare()

        XCTAssertEqual(mount.claudeBridge, .linked)
        XCTAssertEqual(mount.instructions, .none)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: project.appendingPathComponent("AGENTS.md").path))
    }

    /// Preparing never replaces anything real. A project with its own
    /// `.claude/skills` and its own `CLAUDE.md` comes out untouched.
    func testPreparingNeverReplacesWhatIsAlreadyThere() throws {
        let claudeDir = project.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try makeSkill("claude-only", in: claudeDir)
        try Data("theirs\n".utf8).write(to: project.appendingPathComponent("CLAUDE.md"))

        let mount = self.mount()
        mount.prepare()

        XCTAssertEqual(mount.claudeBridge, .ownDirectory)
        XCTAssertEqual(mount.instructions, .claudeOnly)
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("CLAUDE.md"),
                                  encoding: .utf8), "theirs\n")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: claudeDir.appendingPathComponent("claude-only/SKILL.md").path))
    }

    // MARK: - The instructions bridge

    private func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: project.appendingPathComponent(name))
    }

    /// The probe this encodes: with only `AGENTS.md` present and every tool
    /// disabled, Claude Code could not answer a question the file answers —
    /// it tried to `Read` the file instead. With the link in place and tools
    /// still disabled it answered at once. The link is the difference between
    /// "it might go and look" and "it already knows".
    func testBridgingPointsClaudeAtTheSharedInstructions() throws {
        try write("# Project\n\nUse tabs.\n", to: "AGENTS.md")
        let mount = self.mount()
        XCTAssertEqual(mount.instructions, .absent)

        try mount.bridgeInstructions()

        XCTAssertEqual(mount.instructions, .linked)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: project.appendingPathComponent("CLAUDE.md").path),
            "AGENTS.md",
            "Relative, so it is true wherever the project is checked out — this "
            + "one belongs in the repository"
        )
        XCTAssertEqual(
            try String(contentsOf: project.appendingPathComponent("CLAUDE.md"),
                       encoding: .utf8),
            "# Project\n\nUse tabs.\n"
        )
    }

    func testBridgingTwiceIsTheSameAsBridgingOnceForInstructions() throws {
        try write("x", to: "AGENTS.md")
        let mount = self.mount()
        try mount.bridgeInstructions()
        try mount.bridgeInstructions()
        XCTAssertEqual(mount.instructions, .linked)
    }

    /// Instructions are prose somebody has to mean. With nothing to point at,
    /// the answer is to say so — not to write a file nobody asked for.
    func testWithNoInstructionsThereIsNothingToBridge() {
        let mount = self.mount()
        XCTAssertEqual(mount.instructions, .none)
        XCTAssertFalse(mount.instructions.canBridge)
        XCTAssertThrowsError(try mount.bridgeInstructions())
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: project.appendingPathComponent("CLAUDE.md").path))
    }

    /// Instructions written for Claude Code alone are almost never *about*
    /// Claude Code. Renaming them is what lets the other three read what they
    /// were always meant to read.
    func testClaudeOnlyInstructionsCanBeAdopted() throws {
        try write("# House style\n", to: "CLAUDE.md")
        let mount = self.mount()
        XCTAssertEqual(mount.instructions, .claudeOnly)

        try mount.adoptClaudeInstructions()

        XCTAssertEqual(mount.instructions, .linked)
        XCTAssertEqual(
            try String(contentsOf: project.appendingPathComponent("AGENTS.md"),
                       encoding: .utf8),
            "# House style\n",
            "Renamed, not copied — one file, four readers"
        )
    }

    /// Two real files may disagree, and which one is right is not a thing to
    /// guess at. Reported, and nothing is touched.
    func testTwoRealInstructionFilesAreReportedAndLeftAlone() throws {
        try write("shared\n", to: "AGENTS.md")
        try write("claude only\n", to: "CLAUDE.md")
        let mount = self.mount()

        XCTAssertEqual(mount.instructions, .divergent)
        XCTAssertThrowsError(try mount.bridgeInstructions())
        XCTAssertThrowsError(try mount.adoptClaudeInstructions())
        XCTAssertThrowsError(try mount.removeInstructionsBridge())
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("CLAUDE.md"),
                                  encoding: .utf8), "claude only\n")
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("AGENTS.md"),
                                  encoding: .utf8), "shared\n")
    }

    func testAClaudeFileLinkedElsewhereIsLeftAlone() throws {
        try write("shared\n", to: "AGENTS.md")
        try write("somebody else's\n", to: "OTHER.md")
        try FileManager.default.createSymbolicLink(
            atPath: project.appendingPathComponent("CLAUDE.md").path,
            withDestinationPath: "OTHER.md")

        let mount = self.mount()
        guard case .foreignLink = mount.instructions else {
            return XCTFail("expected a foreign link, got \(mount.instructions)")
        }
        XCTAssertThrowsError(try mount.bridgeInstructions())
    }

    func testABridgePointingSomewhereElseIsLeftAlone() throws {
        let claudeParent = project.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: claudeParent.appendingPathComponent("skills").path,
            withDestinationPath: "../somewhere-else")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("somewhere-else"),
            withIntermediateDirectories: true)

        let mount = self.mount()
        guard case .foreignLink = mount.claudeBridge else {
            return XCTFail("expected a foreign link, got \(mount.claudeBridge)")
        }
        XCTAssertThrowsError(try mount.mountClaudeBridge())
    }
}

/// The quiet store, and the move that makes project-only skills possible.
final class SkillStoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { [home] in try? FileManager.default.removeItem(at: home!) }
    }

    @discardableResult
    private func makeSkill(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: d\n---\n".utf8)
            .write(to: url.appendingPathComponent("SKILL.md"))
        return url
    }

    private var storeRoot: URL { home.appendingPathComponent(".codenotch/skills") }
    private var libraryRoot: URL { home.appendingPathComponent(".agents/skills") }

    /// Being loaded everywhere is a *link*, not a second home. Codex was
    /// probed and follows one: it listed a skill whose only real copy was in
    /// `~/.codenotch/skills`.
    func testGoingGlobalWritesALinkAndLeavesTheFolderAlone() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let real = try makeSkill("agently-mail", in: storeRoot)

        let store = SkillStore(home: home)
        XCTAssertFalse(store.isGlobal(name: "agently-mail"))
        try store.setGlobal(true, name: "agently-mail")

        XCTAssertTrue(store.isGlobal(name: "agently-mail"))
        XCTAssertTrue(store.isOurGlobalLink(name: "agently-mail"))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: libraryRoot.appendingPathComponent("agently-mail").path),
            real.path,
            "The link points at the real folder, which has not moved"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: real.appendingPathComponent("SKILL.md").path))
    }

    /// Switching off removes the link and nothing else — the reason the real
    /// folder lives in the store rather than moving between two homes.
    func testComingBackOutRemovesOnlyTheLink() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let real = try makeSkill("agently-mail", in: storeRoot)

        let store = SkillStore(home: home)
        try store.setGlobal(true, name: "agently-mail")
        try store.setGlobal(false, name: "agently-mail")

        XCTAssertFalse(store.isGlobal(name: "agently-mail"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: real.appendingPathComponent("SKILL.md").path),
            "The skill itself is untouched")
    }

    func testSwitchingOnTwiceIsTheSameAsOnce() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("agently-mail", in: storeRoot)

        let store = SkillStore(home: home)
        try store.setGlobal(true, name: "agently-mail")
        try store.setGlobal(true, name: "agently-mail")
        XCTAssertTrue(store.isOurGlobalLink(name: "agently-mail"))
    }

    /// The one move left, and it happens once: a skill that was a real folder
    /// in `~/.agents/skills` before any of this existed is taken into the
    /// store the moment it is switched off. Leaving it there is exactly the
    /// state being switched off.
    func testARealFolderInTheGlobalRootIsTakenInWhenSwitchedOff() throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try makeSkill("ui-ux-pro-max", in: libraryRoot)

        let store = SkillStore(home: home)
        XCTAssertTrue(store.isGlobal(name: "ui-ux-pro-max"))
        XCTAssertFalse(store.isOurGlobalLink(name: "ui-ux-pro-max"),
                       "A real folder, not a link we wrote")

        try store.setGlobal(false, name: "ui-ux-pro-max")

        XCTAssertFalse(store.isGlobal(name: "ui-ux-pro-max"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: storeRoot.appendingPathComponent("ui-ux-pro-max/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: libraryRoot.appendingPathComponent("ui-ux-pro-max").path))

        // And from then on it is a link like any other.
        try store.setGlobal(true, name: "ui-ux-pro-max")
        XCTAssertTrue(store.isOurGlobalLink(name: "ui-ux-pro-max"))
    }

    /// A skill reached by a link must not also be offered as a skill of its
    /// own — one folder, one row.
    func testALinkedSkillIsListedOnceAndMarkedGlobal() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try makeSkill("agently-mail", in: storeRoot)
        let store = SkillStore(home: home)
        try store.setGlobal(true, name: "agently-mail")

        let available = store.available()
        XCTAssertEqual(available.map(\.name), ["agently-mail"])
        XCTAssertTrue(available[0].isGlobal)
        XCTAssertTrue(available[0].isTakenIn)
        XCTAssertEqual(available[0].url.resolvingSymlinksInPath().path,
                       storeRoot.appendingPathComponent("agently-mail").resolvingSymlinksInPath().path,
                       "The row points at the real folder, not at the link")
    }

    /// Somebody else's link in the global root is not ours to remove.
    func testAForeignLinkInTheGlobalRootIsRefused() throws {
        let elsewhere = home.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try makeSkill("pdf", in: elsewhere)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: libraryRoot.appendingPathComponent("pdf"),
            withDestinationURL: elsewhere.appendingPathComponent("pdf"))

        let store = SkillStore(home: home)
        XCTAssertFalse(store.isOurGlobalLink(name: "pdf"))
        XCTAssertThrowsError(try store.setGlobal(false, name: "pdf"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: libraryRoot.appendingPathComponent("pdf").path))
    }

    /// Taking a skill in must not take it *away*: a Codex-only skill moved
    /// into the store with nothing left behind is a skill Codex has lost.
    func testTakingInLeavesALinkWhereTheSkillWas() throws {
        let codexSkills = home.appendingPathComponent(".codex/skills")
        try FileManager.default.createDirectory(at: codexSkills, withIntermediateDirectories: true)
        let original = try makeSkill("keep-codex-fast", in: codexSkills)

        let store = SkillStore(home: home)
        let taken = try store.takeIn(original)

        XCTAssertEqual(taken.url.resolvingSymlinksInPath().path,
                       storeRoot.appendingPathComponent("keep-codex-fast").resolvingSymlinksInPath().path)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: original.path),
            taken.url.path,
            "Codex still reaches it, through a link")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: original.appendingPathComponent("SKILL.md").path),
            "and the content still resolves from the old path")
        XCTAssertFalse(taken.isGlobal,
                       "Taking a skill in is not switching it on everywhere")
    }

    /// A skill that *is* a repository moves freely: the checkout travels with
    /// it and `git pull` works just as well from the store. Refusing this was
    /// a bug, and the common case — a skill cloned straight into
    /// `~/.codex/skills/<name>` is its own repo by construction.
    func testASkillThatIsItselfARepositoryIsMovedWithItsCheckout() throws {
        let codexSkills = home.appendingPathComponent(".codex/skills")
        try FileManager.default.createDirectory(at: codexSkills, withIntermediateDirectories: true)
        let skill = try makeSkill("orange-line-illustration", in: codexSkills)
        try FileManager.default.createDirectory(at: skill.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)

        XCTAssertNil(SkillStore.enclosingRepository(of: skill),
                     "It is the repository, not a folder inside one")

        let taken = try SkillStore(home: home).takeIn(skill)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: taken.url.appendingPathComponent(".git").path),
            "the checkout came along, so git pull still works")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: skill.path),
            taken.url.path,
            "and Codex still reaches it")
    }

    /// A skill inside a checkout has an upstream. Moving it out of the repo
    /// detaches it from `git pull`, so the next version silently never arrives.
    func testASkillInsideAGitRepositoryIsNeverMoved() throws {
        let repo = home.appendingPathComponent("GitHub/some-skills")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        let skills = repo.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        let skill = try makeSkill("comic", in: skills)

        XCTAssertThrowsError(try SkillStore(home: home).take(skill)) { error in
            guard case SkillStoreError.insideRepository = error else {
                return XCTFail("expected insideRepository, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: skill.appendingPathComponent("SKILL.md").path))
    }

    /// A worktree and a submodule both write a `.git` *file* rather than a
    /// directory, and both are just as much somebody's checkout.
    func testAGitFileCountsAsARepositoryToo() throws {
        let repo = home.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Data("gitdir: /elsewhere/.git/worktrees/x\n".utf8)
            .write(to: repo.appendingPathComponent(".git"))
        let skill = try makeSkill("comic", in: repo)

        XCTAssertNotNil(SkillStore.gitWorkingTree(containing: skill))
        XCTAssertNotNil(SkillStore.enclosingRepository(of: skill))
        XCTAssertThrowsError(try SkillStore(home: home).take(skill))
    }

    /// Two roots offering the same folder name is a collision: a link can only
    /// point at one of them. The nearer root wins and the row says so.
    func testTheNearestRootWinsAndTheCollisionIsReported() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try makeSkill("pdf", in: storeRoot)
        try makeSkill("pdf", in: libraryRoot)

        let available = SkillStore(home: home).available()
        XCTAssertEqual(available.map(\.name), ["pdf"])
        XCTAssertEqual(available[0].url.resolvingSymlinksInPath().path,
                       storeRoot.appendingPathComponent("pdf").resolvingSymlinksInPath().path)
        XCTAssertEqual(available[0].shadowedBy.count, 1)
    }

    /// Anything reachable from `~/.agents/skills` is loaded into every session
    /// of every project, so the row has to say which ones those are — whether
    /// it got there as a link or was always a real folder.
    func testGlobalSkillsAreMarkedAsSuch() throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try makeSkill("agently-mail", in: libraryRoot)

        let available = SkillStore(home: home).available()
        XCTAssertEqual(available.map(\.isGlobal), [true])
        XCTAssertEqual(available.map(\.isTakenIn), [false],
                       "Never taken in — its real folder is still in the global root")
    }
}

/// Projects are remembered, not discovered — walking the disk for `.git` and
/// guessing which results are "projects" is how a sidebar fills with
/// `node_modules`.
/// Tags a skill carries, and the ones you gave it.
final class SkillTagTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "tags-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        addTeardownBlock { [suite] in
            UserDefaults.standard.removePersistentDomain(forName: suite!)
        }
    }

    /// A skill in a cloned repository must not come back from `git pull` with
    /// your filing scribbled over it, so your tags are kept here and the
    /// author's are read from their file.
    func testYourTagsAndTheAuthorsAreShownTogetherAndKeptApart() {
        let tags = SkillTags(defaults: defaults)
        tags.add("Mine", to: "pdf")

        XCTAssertEqual(tags.own("pdf"), ["mine"], "normalised on the way in")
        XCTAssertEqual(tags.all(for: "pdf", declared: ["docs"]), ["docs", "mine"],
                       "the author's first, then yours")
    }

    func testTheSameTagIsNotAddedTwice() {
        let tags = SkillTags(defaults: defaults)
        tags.add("web", to: "pdf")
        tags.add(" WEB ", to: "pdf")
        XCTAssertEqual(tags.own("pdf"), ["web"])
    }

    func testADeclaredTagIsNotDuplicatedByYours() {
        let tags = SkillTags(defaults: defaults)
        tags.add("docs", to: "pdf")
        XCTAssertEqual(tags.all(for: "pdf", declared: ["docs"]), ["docs"])
    }

    func testRemovingTakesOnlyYours() {
        let tags = SkillTags(defaults: defaults)
        tags.add("mine", to: "pdf")
        tags.remove("mine", from: "pdf")
        XCTAssertTrue(tags.own("pdf").isEmpty)
        XCTAssertEqual(tags.all(for: "pdf", declared: ["docs"]), ["docs"],
                       "the author's survives — it is in their file, not ours")
    }

    /// Hashed by hand, because `hashValue` is seeded per process and a tag that
    /// changed colour on every launch would be worse than no colour at all.
    func testATagsColourIsTheSameEveryTime() {
        XCTAssertEqual(SkillTags.colour(for: "web"), SkillTags.colour(for: "web"))
        XCTAssertNotEqual(SkillTags.colour(for: "web"), SkillTags.colour(for: "genai"))
    }

    func testEmptyAndPunctuationOnlyTagsAreRefused() {
        let tags = SkillTags(defaults: defaults)
        tags.add("   ", to: "pdf")
        tags.add("#", to: "pdf")
        XCTAssertTrue(tags.own("pdf").isEmpty)
    }
}

final class SkillProjectRegistryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var folder: URL!

    override func setUpWithError() throws {
        suite = "registry-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { [suite, folder] in
            UserDefaults.standard.removePersistentDomain(forName: suite!)
            try? FileManager.default.removeItem(at: folder!)
        }
    }

    func testProjectsRoundTrip() {
        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(project: folder)
        XCTAssertEqual(registry.projects.map(\.id), [folder.standardizedFileURL.path])

        registry.add(project: folder)
        XCTAssertEqual(registry.projects.count, 1, "The same folder is one row")

        registry.remove(project: folder)
        XCTAssertTrue(registry.projects.isEmpty)
    }

    /// A folder that has been deleted or moved is dropped rather than shown as
    /// a row whose every action would fail.
    func testAProjectThatIsGoneDoesNotAppear() throws {
        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(project: folder)
        try FileManager.default.removeItem(at: folder)
        XCTAssertTrue(registry.projects.isEmpty)
    }

    /// Pinned projects come first. Stored, because a pin that only held while
    /// one window was open would not be a pin.
    func testPinnedProjectsComeFirstAndSurvive() throws {
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: other) }

        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(project: folder)
        registry.add(project: other)
        XCTAssertEqual(registry.projects.map(\.name), [folder.lastPathComponent,
                                                       other.lastPathComponent])

        registry.setPinned(true, project: other)
        XCTAssertEqual(registry.projects.map(\.name), [other.lastPathComponent,
                                                       folder.lastPathComponent])
        XCTAssertEqual(registry.projects.map(\.isPinned), [true, false])

        // Read through a second registry over the same defaults: the pin is a
        // stored fact, not one this instance is holding.
        XCTAssertEqual(SkillProjectRegistry(defaults: defaults).pinned,
                       [other.standardizedFileURL.path])
    }

    /// Forgetting a project takes its pin with it, or the pin outlives the row
    /// and comes back when the folder is added again.
    func testForgettingAProjectDropsItsPin() {
        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(project: folder)
        registry.setPinned(true, project: folder)
        registry.remove(project: folder)

        XCTAssertTrue(registry.pinned.isEmpty)
        registry.add(project: folder)
        XCTAssertEqual(registry.projects.map(\.isPinned), [false])
    }

    /// The mark is stored as two names — a symbol and a palette entry — so an
    /// unknown one falls back rather than failing to decode.
    func testMarksRoundTripAndFallBack() {
        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(project: folder)
        XCTAssertEqual(registry.projects.first?.mark, .fallback)

        registry.setMark(ProjectMark(symbol: "hammer.fill", color: "teal"), project: folder)
        XCTAssertEqual(registry.projects.first?.mark,
                       ProjectMark(symbol: "hammer.fill", color: "teal"))
        XCTAssertEqual(SkillProjectRegistry(defaults: defaults).projects.first?.mark.color,
                       "teal", "stored, not held by one instance")

        registry.setMark(ProjectMark(symbol: "hammer.fill", color: "chartreuse"),
                         project: folder)
        XCTAssertEqual(registry.projects.first?.mark.swiftUIColor, Color.secondary,
                       "a palette name we no longer ship falls back")
    }

    /// Forgetting a project takes its mark with it, or a folder added again
    /// comes back wearing a colour nobody chose for it.
    func testForgettingAProjectDropsItsMark() {
        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(project: folder)
        registry.setMark(ProjectMark(symbol: "leaf.fill", color: "green"), project: folder)
        registry.remove(project: folder)
        registry.add(project: folder)

        XCTAssertEqual(registry.projects.first?.mark, .fallback)
    }

    func testOriginsRoundTripSeparatelyFromProjects() {
        let registry = SkillProjectRegistry(defaults: defaults)
        registry.add(origin: folder)
        XCTAssertEqual(registry.origins.map(\.path), [folder.path])
        XCTAssertTrue(registry.projects.isEmpty)
    }
}

/// Light, dark, or whatever the Mac is doing.
final class AppAppearanceTests: XCTestCase {
    /// `nil` is not "no appearance" — it is *inherit*, which is exactly what
    /// following the system means. Returning a concrete one here would pin the
    /// app to whatever the Mac happened to be on at launch.
    func testFollowingTheSystemMeansInheriting() {
        XCTAssertNil(AppAppearance.system.nsAppearance)
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }

    /// Stored by name, and an unknown one falls back rather than failing.
    func testItRoundTripsThroughItsRawValue() {
        for appearance in AppAppearance.allCases {
            XCTAssertEqual(AppAppearance(rawValue: appearance.rawValue), appearance)
        }
        XCTAssertNil(AppAppearance(rawValue: "sepia"))
    }
}
