import XCTest
@testable import Codenotch

/// The model's write path, end to end, on a layout shaped like the real one:
/// a skill in `~/.agents/skills` with a link to it from `~/.claude/skills`.
///
/// Written because the unit tests all passed and the switch in the window did
/// nothing — which meant the gap was between the two, not inside either.
@MainActor
final class SkillModelIntegrationTests: XCTestCase {
    private var home: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        suite = "model-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { [home, suite] in
            UserDefaults.standard.removePersistentDomain(forName: suite!)
            try? FileManager.default.removeItem(at: home!)
        }
    }

    private var libraryRoot: URL { home.appendingPathComponent(".agents/skills") }
    private var storeRoot: URL { home.appendingPathComponent(".codenotch/skills") }
    private var claudeSkills: URL { home.appendingPathComponent(".claude/skills") }

    private func makeSkill(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: d\n---\n".utf8)
            .write(to: url.appendingPathComponent("SKILL.md"))
        return url
    }

    /// The model's work runs on a detached task, so the assertion has to wait
    /// for it rather than read the filesystem on the same turn.
    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 5,
                           _ condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTFail("timed out waiting for \(description)")
    }

    func testSwitchingOffUnlinksEverywhereAndTakesTheSkillIn() throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeSkills, withIntermediateDirectories: true)
        let real = try makeSkill("swiftui-pro", in: libraryRoot)
        try FileManager.default.createSymbolicLink(
            at: claudeSkills.appendingPathComponent("swiftui-pro"), withDestinationURL: real)

        let model = SkillManagerModel(home: home, defaults: defaults)
        model.refresh()
        waitUntil("the skill to be listed") { model.storeSkills.count == 1 }
        XCTAssertEqual(model.storeSkills.first?.isGlobal, true)

        model.setGlobal(false, skill: "swiftui-pro")

        waitUntil("the folder to be taken in") {
            FileManager.default.fileExists(
                atPath: self.storeRoot.appendingPathComponent("swiftui-pro/SKILL.md").path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: real.path),
                       "nothing is left in the global root")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: claudeSkills.appendingPathComponent("swiftui-pro").path),
            "the mount went first, so no link is left pointing at a moved folder")
        XCTAssertNil(model.problem)
        waitUntil("the row to stop being global") { model.storeSkills.first?.isGlobal == false }
    }

    /// Switching back on writes a link and mounts the two agents that do not
    /// read the global folder. The real folder stays exactly where it is.
    func testSwitchingOnLinksWithoutMovingAnything() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let real = try makeSkill("agently-mail", in: storeRoot)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"),
                                                withIntermediateDirectories: true)

        let model = SkillManagerModel(home: home, defaults: defaults)
        model.refresh()
        waitUntil("the skill to be listed") { model.storeSkills.count == 1 }
        XCTAssertEqual(model.storeSkills.first?.isGlobal, false)

        model.setGlobal(true, skill: "agently-mail")

        waitUntil("the global link") {
            FileManager.default.fileExists(
                atPath: self.libraryRoot.appendingPathComponent("agently-mail/SKILL.md").path)
        }
        waitUntil("Claude Code to be mounted") {
            FileManager.default.fileExists(
                atPath: self.claudeSkills.appendingPathComponent("agently-mail").path)
        }
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: libraryRoot.appendingPathComponent("agently-mail").path),
            real.path)
        XCTAssertNil(model.problem)
        waitUntil("one row, marked global") {
            model.storeSkills.count == 1 && model.storeSkills.first?.isGlobal == true
        }
    }

    /// A global skill is in every project — that is what global means. The
    /// project page showed its switch *off*, which was the page saying a
    /// project did not have something it plainly had, and flipping it on would
    /// have written a link that changes nothing.
    func testAGlobalSkillReachesEveryProjectWithoutALink() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        _ = try makeSkill("agently-mail", in: storeRoot)
        let folder = home.appendingPathComponent("a-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let model = SkillManagerModel(home: home, defaults: defaults)
        model.addProject(folder)
        waitUntil("the project and skill to be listed") {
            model.projects.count == 1 && model.storeSkills.count == 1
        }

        let project = model.projects[0]
        XCTAssertEqual(model.reach(of: model.storeSkills[0], in: project), .absent)

        model.setGlobal(true, skill: "agently-mail")
        waitUntil("it to go global") { model.storeSkills.first?.isGlobal == true }

        let reach = model.reach(of: model.storeSkills[0], in: project)
        XCTAssertEqual(reach, .everywhere)
        XCTAssertTrue(reach.isReachable)
        XCTAssertFalse(reach.isChoosable,
                       "the project's own switch decides nothing while it is global")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(".agents/skills/agently-mail").path),
            "and no redundant link was written")
    }

    /// A real folder of that name in the project outranks everything: it is
    /// what the project's agents actually read.
    func testARealFolderInTheProjectOutranksBeingGlobal() throws {
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        _ = try makeSkill("pdf", in: storeRoot)
        let folder = home.appendingPathComponent("a-project")
        let projectSkills = folder.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: projectSkills, withIntermediateDirectories: true)
        _ = try makeSkill("pdf", in: projectSkills)

        let model = SkillManagerModel(home: home, defaults: defaults)
        model.addProject(folder)
        model.setGlobal(true, skill: "pdf")
        waitUntil("both to settle") {
            model.projects.count == 1 && model.storeSkills.first?.isGlobal == true
        }

        guard case .blocked = model.reach(of: model.storeSkills[0], in: model.projects[0]) else {
            return XCTFail("expected blocked, got \(model.reach(of: model.storeSkills[0], in: model.projects[0]))")
        }
    }
}
