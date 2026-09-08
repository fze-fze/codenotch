import XCTest
@testable import Codenotch

/// A fake home directory, so nothing here can reach the real `~/.claude`.
class SkillFixture: XCTestCase {
    var home: URL!
    var library: SkillLibrary!
    var mount: SkillMount!

    override func setUpWithError() throws {
        // Resolved on the way in: `NSTemporaryDirectory()` hands back a path
        // under `/var`, which is itself a symlink to `/private/var`. Left
        // unresolved, a mount's destination compares unequal to the library it
        // actually points at, and every managed link reads as foreign.
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .resolvingSymlinksInPath()
            .appendingPathComponent("skills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        library = SkillLibrary(home: home)
        mount = SkillMount(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Make an agent look installed.
    func install(_ agent: SkillAgent) throws {
        try FileManager.default.createDirectory(
            at: agent.detectPaths(home: home)[0], withIntermediateDirectories: true
        )
    }

    /// Put a real skill folder at `url`.
    @discardableResult
    func writeSkill(_ name: String, at url: URL, description: String = "does a thing") throws -> URL {
        let directory = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: \(description)
        ---

        # \(name)
        """.write(to: directory.appendingPathComponent("SKILL.md"),
                  atomically: true, encoding: .utf8)
        return directory
    }

    /// Put a skill in the library.
    @discardableResult
    func writeLibrarySkill(_ name: String) throws -> URL {
        try writeSkill(name, at: library.root)
    }
}

/// The mount rules. Every one of these is really the same rule seen from a
/// different side: **a mount is a symlink into the library, and nothing else is
/// ever removed.**
final class SkillMountTests: SkillFixture {
    func testMountingMakesALinkIntoTheLibrary() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")

        try mount.mount(name: "review", into: .claudeCode)

        let target = mount.destination(name: "review", for: .claudeCode)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
        XCTAssertEqual(URL(fileURLWithPath: destination).standardizedFileURL,
                       library.root.appendingPathComponent("review").standardizedFileURL)
        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .mounted)
    }

    /// The skill has to be readable *through* the link — a link that resolves to
    /// nothing is not a distributed skill, it is a broken one.
    func testTheAgentCanReadTheSkillThroughTheLink() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try mount.mount(name: "review", into: .claudeCode)

        let manifest = mount.destination(name: "review", for: .claudeCode)
            .appendingPathComponent("SKILL.md")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        XCTAssertTrue(text.contains("name: review"))
    }

    func testUnmountingRemovesTheLinkAndLeavesTheLibraryAlone() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try mount.mount(name: "review", into: .claudeCode)

        try mount.unmount(name: "review", from: .claudeCode)

        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .notMounted)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: library.root.appendingPathComponent("review/SKILL.md").path
        ), "unmounting took the library's copy with it")
    }

    /// The whole reason this app can be trusted with someone's `~/.claude`.
    /// A real folder there is theirs, and no amount of wanting to mount over it
    /// makes it ours to delete.
    func testARealFolderInTheWayIsNeverTouched() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        let theirs = try writeSkill("review", at: SkillAgent.claudeCode.ownSkillsDir(home: home),
                                    description: "the one they wrote by hand")

        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .conflict(.realItem))
        XCTAssertThrowsError(try mount.mount(name: "review", into: .claudeCode))
        XCTAssertThrowsError(try mount.unmount(name: "review", from: .claudeCode))

        let text = try String(contentsOf: theirs.appendingPathComponent("SKILL.md"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("the one they wrote by hand"),
                      "someone else's skill was overwritten")
    }

    /// A link into somewhere else is a deliberate arrangement — very likely
    /// another skills manager's. Removing it would silently break their setup.
    func testALinkPointingElsewhereIsAConflictRatherThanOurs() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")

        let elsewhere = try writeSkill("review", at: home.appendingPathComponent("elsewhere"))
        let target = mount.destination(name: "review", for: .claudeCode)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: elsewhere)

        guard case .conflict(.foreignLink) = mount.state(name: "review", for: .claudeCode) else {
            return XCTFail("a foreign link read as ours")
        }
        XCTAssertThrowsError(try mount.unmount(name: "review", from: .claudeCode))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path),
                      "another tool's link was removed")
    }

    /// A link into a folder that has since been deleted is not somebody's
    /// arrangement, it is debris — and calling it "not ours to remove" left
    /// three broken skills in `~/.claude/skills` with no way to fix them from
    /// here. There is no content behind it to lose, so it is replaceable.
    func testABrokenLinkIsToldApartFromALiveOne() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")

        let gone = home.appendingPathComponent("deleted/review")
        let target = mount.destination(name: "review", for: .claudeCode)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: gone)

        guard case .conflict(.brokenLink(let destination)) =
                mount.state(name: "review", for: .claudeCode) else {
            return XCTFail("a link to nothing read as a live foreign link")
        }
        XCTAssertEqual(destination, gone.path)
        XCTAssertTrue(mount.state(name: "review", for: .claudeCode).isToggleable,
                      "there was no way to repair it")
    }

    func testMountingReplacesABrokenLink() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        let target = mount.destination(name: "review", for: .claudeCode)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: target, withDestinationURL: home.appendingPathComponent("deleted/review")
        )

        try mount.mount(name: "review", into: .claudeCode)

        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .mounted)
        let text = try String(contentsOf: target.appendingPathComponent("SKILL.md"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("name: review"))
    }

    /// A link to something that is genuinely there stays untouchable, however
    /// much we would like the name. That distinction is the whole point.
    func testALinkToSomethingRealIsStillRefused() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        let elsewhere = try writeSkill("review", at: home.appendingPathComponent("elsewhere"))
        let target = mount.destination(name: "review", for: .claudeCode)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: elsewhere)

        XCTAssertThrowsError(try mount.mount(name: "review", into: .claudeCode))
        XCTAssertFalse(mount.state(name: "review", for: .claudeCode).isToggleable)
    }

    /// Distributing over a half-distributed skill must not unlink and relink the
    /// half that was already fine — a window where the skill is missing is a
    /// window an agent can start a session in.
    func testMountingWhatIsAlreadyMountedIsANoOp() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try mount.mount(name: "review", into: .claudeCode)

        XCTAssertNoThrow(try mount.mount(name: "review", into: .claudeCode))
        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .mounted)
    }

    func testUnmountingWhatWasNeverMountedIsANoOp() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        XCTAssertNoThrow(try mount.unmount(name: "review", from: .claudeCode))
    }

    /// The three that read `~/.agents/skills` themselves get nothing written
    /// anywhere. A second copy under `~/.codex/skills` would be the same skill
    /// twice, and Codex would have to pick one.
    func testAgentsThatReadTheLibraryAreLeftAlone() throws {
        for agent in [SkillAgent.codex, .cursor, .grok] {
            try install(agent)
            try writeLibrarySkill("shared-\(agent.rawValue)")

            XCTAssertEqual(mount.state(name: "shared-\(agent.rawValue)", for: agent), .shared)
            try mount.mount(name: "shared-\(agent.rawValue)", into: agent)

            let own = home.appendingPathComponent(".\(agent.rawValue)/skills")
            XCTAssertFalse(FileManager.default.fileExists(atPath: own.path),
                           "\(agent.displayName) got a copy it did not need")
        }
    }

    /// An agent that has never run here has no directory to write into, and
    /// creating one would make Codenotch look like it installed the agent.
    func testAnUninstalledAgentIsNotWrittenTo() throws {
        try writeLibrarySkill("review")
        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .notInstalled)

        try mount.mount(name: "review", into: .claudeCode)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: SkillAgent.claudeCode.ownSkillsDir(home: home).path
        ))
    }

    func testMountingSomethingNotInTheLibraryFails() throws {
        try install(.claudeCode)
        XCTAssertThrowsError(try mount.mount(name: "ghost", into: .claudeCode))
    }

    /// One obstructed agent must not stop the others — the point of "Distribute
    /// to all" is that it does as much as it can.
    func testDistributingReportsFailuresWithoutAbandoningTheRest() throws {
        try install(.claudeCode)
        try install(.antigravity)
        try writeLibrarySkill("review")
        try writeSkill("review", at: SkillAgent.claudeCode.ownSkillsDir(home: home))

        let failures = mount.mountEverywhere(name: "review")

        XCTAssertEqual(Array(failures.keys), [.claudeCode])
        XCTAssertEqual(mount.state(name: "review", for: .antigravity), .mounted,
                       "one conflict stopped every other agent")
    }

    /// A library entry deleted by hand leaves a link to nothing. It is ours by
    /// intent, so a later mount should replace it rather than fail on it.
    func testADanglingLinkOfOursIsReplacedRatherThanFatal() throws {
        try install(.claudeCode)
        try writeLibrarySkill("review")
        try mount.mount(name: "review", into: .claudeCode)
        try FileManager.default.removeItem(at: library.root.appendingPathComponent("review"))

        try writeLibrarySkill("review")
        XCTAssertNoThrow(try mount.mount(name: "review", into: .claudeCode))
        XCTAssertEqual(mount.state(name: "review", for: .claudeCode), .mounted)
    }

    /// Antigravity reads `~/.gemini/config/skills` and not
    /// `~/.gemini/antigravity/skills`: the first is the path all three of its
    /// surfaces read, and the second has a known bug where symlinked skills are
    /// never discovered — which is precisely what we put there.
    func testAntigravityUsesTheSharedConfigPath() {
        XCTAssertEqual(SkillAgent.antigravity.ownSkillsDir(home: home).path,
                       home.appendingPathComponent(".gemini/config/skills").path)
    }
}

/// Which folder's existence proves an agent has been run here.
final class SkillAgentTests: SkillFixture {
    func testAnAgentIsInstalledWhenItsFolderExists() throws {
        XCTAssertFalse(SkillAgent.cursor.isInstalled(home: home))
        try install(.cursor)
        XCTAssertTrue(SkillAgent.cursor.isInstalled(home: home))
    }

    /// Antigravity writes under `~/.gemini` on a fresh install and kept
    /// `~/.antigravity` from older ones. Either is proof enough.
    func testAntigravityIsFoundUnderEitherOfItsHomes() throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".antigravity"), withIntermediateDirectories: true
        )
        XCTAssertTrue(SkillAgent.antigravity.isInstalled(home: home))
    }

    func testOnlyInstalledAgentsAreListed() throws {
        try install(.codex)
        try install(.grok)
        XCTAssertEqual(SkillAgent.installed(home: home), [.codex, .grok])
    }

    /// Three read the shared library and two do not, and the whole distribution
    /// model rests on that split being right.
    func testTheSplitBetweenSharedAndLinkedAgents() {
        XCTAssertEqual(SkillAgent.allCases.filter(\.readsSharedLibrary),
                       [.codex, .cursor, .grok])
        XCTAssertEqual(SkillAgent.allCases.filter { !$0.readsSharedLibrary },
                       [.claudeCode, .antigravity])
    }

    /// Reading the library and having a folder of your own are different
    /// things, and the first version conflated them: it gave the three
    /// shared-library agents *no* own-folder, which is why the fifteen skills
    /// in `~/.codex/skills` were never seen.
    func testEveryAgentHasItsOwnFolderEvenWhenItReadsTheLibrary() {
        for agent in SkillAgent.allCases {
            XCTAssertNotEqual(agent.ownSkillsDir(home: home).path,
                              SkillAgent.sharedLibrary(home: home).path,
                              "\(agent.displayName)'s own folder is the library")
        }
        XCTAssertEqual(SkillAgent.codex.ownSkillsDir(home: home).path,
                       home.appendingPathComponent(".codex/skills").path)
    }

    /// Only the two that cannot see the library get a link written for them.
    func testOnlyTheLinkedAgentsHaveAMountTarget() {
        for agent in SkillAgent.allCases {
            XCTAssertEqual(agent.mountDir(home: home) == nil, agent.readsSharedLibrary,
                           "\(agent.displayName) has the wrong mount target")
        }
    }

    /// Grok is the one this fork added — the reference project detects forty
    /// agents and not this one.
    func testGrokIsDetectedAndHasAMark() throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".grok"), withIntermediateDirectories: true
        )
        XCTAssertTrue(SkillAgent.grok.isInstalled(home: home))
        XCTAssertEqual(SkillAgent.grok.glyph, .grok)
        XCTAssertFalse(ProviderGlyph.grok.outline.isEmpty, "Grok has nothing to draw")
    }
}
