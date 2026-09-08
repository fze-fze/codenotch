import XCTest
@testable import Codenotch

/// The project page shows two groups, and the order inside the second one is a
/// decision rather than an accident.
///
/// It used to show three: "Active in this project" and "Available from Library"
/// were the same skills from the same place, split by which way each row's own
/// switch pointed — so turning one on made it vanish from under the pointer and
/// reappear in another section. These assert the merged shape, and in
/// particular that a conflict cannot sink to the bottom of a long list.
final class ProjectSkillGroupsTests: XCTestCase {
    private func skill(_ name: String, isGlobal: Bool = false) -> StoredSkill {
        StoredSkill(name: name, url: URL(fileURLWithPath: "/tmp/\(name)"),
                    frontmatter: .empty, isGlobal: isGlobal, shadowed: false)
    }

    private func groups(
        _ skills: [StoredSkill],
        activeOnly: Bool = false,
        reach: @escaping (String) -> SkillManagerModel.ProjectReach
    ) -> ProjectSkillGroups {
        ProjectSkillGroups(skills: skills, activeOnly: activeOnly) { reach($0.name) }
    }

    func testGlobalIsItsOwnGroupAndNeverOfferedAsAChoice() {
        let all = [skill("a", isGlobal: true), skill("b")]
        let result = groups(all) { $0 == "a" ? .everywhere : .absent }

        XCTAssertEqual(result.global.map(\.name), ["a"])
        XCTAssertEqual(result.library.map(\.name), ["b"],
                       "a globally loaded skill has no switch to offer")
    }

    func testTheOnesThatAreOnComeFirst() {
        let all = [skill("a"), skill("b"), skill("c"), skill("d")]
        let result = groups(all) { $0 == "c" || $0 == "a" ? .linked : .absent }

        XCTAssertEqual(result.library.map(\.name), ["a", "c", "b", "d"])
    }

    /// Alphabetical order survives the partition. `sorted(by:)` would not
    /// guarantee this — it is not a stable sort — which is why the grouping
    /// filters instead.
    func testOrderIsPreservedWithinEachHalf() {
        let all = ["a", "b", "c", "d", "e", "f"].map { skill($0) }
        let result = groups(all) { ["b", "e"].contains($0) ? .linked : .absent }

        XCTAssertEqual(result.library.map(\.name), ["b", "e", "a", "c", "d", "f"])
    }

    /// A skill the project's own folder overrides reads as off but is not.
    /// It sits with the ones that are on, not at the end of everything
    /// available, because at the end of thirty rows nobody ever sees it.
    func testAConflictSitsNearTheTopRatherThanAmongTheAvailable() {
        let all = [skill("a"), skill("b"), skill("c")]
        let result = groups(all) {
            switch $0 {
            case "a": return .absent
            case "b": return .blocked(.conflict(.realItem))
            default:  return .linked
            }
        }

        XCTAssertEqual(result.library.map(\.name), ["c", "b", "a"])
    }

    /// "Active & local" drops what is merely on offer, and keeps conflicts:
    /// a project-owned folder winning over a library skill is part of what this
    /// project actually has.
    func testActiveOnlyHidesTheAvailableButKeepsConflicts() {
        let all = [skill("a"), skill("b"), skill("c")]
        let result = groups(all, activeOnly: true) {
            switch $0 {
            case "a": return .linked
            case "b": return .blocked(.conflict(.realItem))
            default:  return .absent
            }
        }

        XCTAssertEqual(result.library.map(\.name), ["a", "b"])
    }
}
