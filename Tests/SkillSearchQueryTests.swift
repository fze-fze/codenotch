import XCTest
@testable import Codenotch

final class SkillSearchQueryTests: XCTestCase {
    private func matches(_ query: SkillSearchQuery, tags: [String] = ["swift", "ui"], summary: String = "Build native interfaces") -> Bool {
        query.matches(name: "swiftui-pro", displayName: "SwiftUI Pro", summary: summary, tags: tags)
    }

    func testWhitespaceDoesNotHideSkills() {
        let query = SkillSearchQuery(text: "  \n ")
        XCTAssertTrue(query.isEmpty)
        XCTAssertTrue(matches(query))
    }

    func testSearchCombinesNameDescriptionAndTags() {
        XCTAssertTrue(matches(SkillSearchQuery(text: "SWIFTUI native #ui")))
        XCTAssertFalse(matches(SkillSearchQuery(text: "SwiftUI browser")))
    }

    func testHashRequiresAnExactTagRatherThanNameOrSubstring() {
        XCTAssertTrue(matches(SkillSearchQuery(text: "#SWIFT")))
        XCTAssertFalse(matches(SkillSearchQuery(text: "#swiftui")))
        XCTAssertFalse(matches(SkillSearchQuery(text: "#ui"), tags: ["swiftui"]))
    }

    func testSelectedTagsUseIntersectionAndCombineWithSearch() {
        XCTAssertTrue(matches(SkillSearchQuery(text: "native", tags: ["swift", "ui"])))
        XCTAssertFalse(matches(SkillSearchQuery(tags: ["swift", "web"])))
        XCTAssertFalse(matches(SkillSearchQuery(text: "browser", tags: ["swift"])))
    }

    func testSearchHandlesLocalizedTextAndMissingDescription() {
        XCTAssertTrue(matches(SkillSearchQuery(text: "界面"), summary: "原生界面设计"))
        XCTAssertTrue(SkillSearchQuery(text: "cafe").matches(name: "café", displayName: "Café", summary: nil, tags: []))
    }

    func testSpecificProjectUsesEffectiveReachRatherThanGlobalFlag() {
        let scope = SkillScopeFilter.project("overridden-project")
        XCTAssertFalse(scope.matches(isGlobal: true, linkedProjects: [], activeProjects: ["healthy-project"]))
        XCTAssertTrue(SkillScopeFilter.project("healthy-project").matches(isGlobal: true, linkedProjects: [], activeProjects: ["healthy-project"]))
    }

    func testProjectLinksRemainDiscoverableWhileGlobal() {
        XCTAssertTrue(SkillScopeFilter.projects.matches(isGlobal: true, linkedProjects: ["project"], activeProjects: ["project"]))
        XCTAssertFalse(SkillScopeFilter.projects.matches(isGlobal: true, linkedProjects: [], activeProjects: ["project"]))
    }

    func testUnassignedMeansNoGlobalOrProjectScope() {
        XCTAssertTrue(SkillScopeFilter.unassigned.matches(isGlobal: false, linkedProjects: [], activeProjects: []))
        XCTAssertFalse(SkillScopeFilter.unassigned.matches(isGlobal: true, linkedProjects: [], activeProjects: []))
        XCTAssertFalse(SkillScopeFilter.unassigned.matches(isGlobal: false, linkedProjects: ["project"], activeProjects: ["project"]))
    }
}
