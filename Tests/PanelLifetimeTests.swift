import AppKit
import XCTest
@testable import Codenotch

/// The panel has to *go away* when it is closed.
///
/// It is the largest thing the app ever builds — `TabView` realises all three
/// pages, so opening it once instantiates the settings form, the skill library
/// and the projects page together — and the notch, which is what the app is
/// for, needs none of it afterwards. Held open behind a closed window it was
/// most of the process's resident memory.
///
/// A leak here is invisible: the window is gone from the screen either way, and
/// nothing about the app misbehaves. Only a measurement finds it, which is
/// exactly the kind of regression a test has to hold.
@MainActor
final class PanelLifetimeTests: XCTestCase {
    private func makeController() -> PanelWindowController {
        PanelWindowController(preferences: Preferences(), providers: { [] })
    }

    /// Visible, and the last of them: a window that has been closed can linger
    /// in `NSApp.windows` until the pool drains, and picking that one up is how
    /// the reopen test first went looking for a live panel and found a corpse.
    private func panelWindow() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.last { $0.title == "Codenotch" && $0.isVisible },
                      "the panel did not put a window up")
    }

    func testClosingThePanelReleasesItsViewTree() throws {
        weak var hosting: NSViewController?

        try autoreleasepool {
            let controller = makeController()
            controller.show(.settings)
            let window = try panelWindow()
            hosting = window.contentViewController
            XCTAssertNotNil(hosting, "the window should be hosting the panel")
            window.close()
        }

        XCTAssertNil(hosting, "the panel's view tree outlived the window that held it")
    }

    /// Closing must not be a one-way door: the window is rebuilt on the way
    /// back in, and the tab it is asked for is the tab it opens on.
    func testItComesBackAfterBeingClosed() throws {
        let controller = makeController()
        controller.show(.settings)
        try panelWindow().close()

        controller.show(.skills)
        let reopened = try panelWindow()
        XCTAssertNotNil(reopened.contentViewController)
        reopened.close()
    }

    /// Opening with no page named lands on Skills.
    ///
    /// Settings is a form you set once; Skills is the page the app is for and
    /// the one whose contents move under you. Asserted rather than left to the
    /// default argument, because the landing page is a product decision and a
    /// default argument is very easy to change by accident.
    func testThePanelOpensOnSkillsByDefault() {
        XCTAssertEqual(PanelSelection().tab, .skills)
    }

    /// The default argument on `show` has to agree with that, or opening from
    /// Spotlight and opening from the menu land on different pages.
    func testShowingWithNoPageNamedLandsOnSkills() throws {
        let controller = makeController()
        controller.show()
        defer { try? panelWindow().close() }
        XCTAssertEqual(controller.selection.tab, .skills)
    }

    /// Naming a page still wins — the gear on the notch opens Settings, and it
    /// has to keep doing that.
    func testAskingForAPageStillGetsIt() throws {
        let controller = makeController()
        controller.show(.settings)
        defer { try? panelWindow().close() }
        XCTAssertEqual(controller.selection.tab, .settings)
    }

    /// The other half of the saving: what the pages were *showing* — every
    /// skill on the machine with its frontmatter, and every project's contents
    /// — is dropped too, and rebuilt from disk on the way back in.
    func testReleasingCachesEmptiesTheModel() throws {
        let model = SkillManagerModel()
        model.releaseCaches()

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.agents.isEmpty)
        XCTAssertTrue(model.agentSkills.isEmpty)
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertTrue(model.projectSkills.isEmpty)
        XCTAssertTrue(model.storeSkills.isEmpty)
        XCTAssertTrue(model.origins.isEmpty)
        XCTAssertTrue(model.allTags.isEmpty)
        XCTAssertFalse(model.isRefreshing)
    }
}
