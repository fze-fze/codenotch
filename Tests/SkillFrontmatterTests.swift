import XCTest
@testable import Codenotch

/// The two strings at the top of a `SKILL.md`. Hand-parsed rather than taken
/// from a YAML library, so what it does *not* understand matters as much as what
/// it does — a shape it cannot read has to come back empty, never wrong.
final class SkillFrontmatterTests: XCTestCase {
    func testItReadsNameAndDescription() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: code-review
        description: Reviews a diff for correctness bugs.
        ---

        # Code review
        """)
        XCTAssertEqual(parsed.name, "code-review")
        XCTAssertEqual(parsed.description, "Reviews a diff for correctness bugs.")
    }

    /// A description is a sentence, and sentences have colons in them. Splitting
    /// on the last colon rather than the first would truncate every one of them.
    func testAValueMayContainColons() {
        let parsed = SkillFrontmatter.parse("""
        ---
        description: Use when: the build fails, or tests hang.
        ---
        """)
        XCTAssertEqual(parsed.description, "Use when: the build fails, or tests hang.")
    }

    func testQuotesAreStripped() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: "my skill"
        description: 'does a thing'
        ---
        """)
        XCTAssertEqual(parsed.name, "my skill")
        XCTAssertEqual(parsed.description, "does a thing")
    }

    /// The real-world shape this exists to survive: Claude Code's own skills
    /// carry a `metadata:` block whose children are indented. Read as top-level
    /// keys they are harmless here, but the same mistake on a nested `name:`
    /// would print the wrong title.
    func testIndentedKeysBelongToTheirParentAndAreIgnored() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: outer
        metadata:
          name: inner
          type: project
        ---
        """)
        XCTAssertEqual(parsed.name, "outer")
    }

    /// The shape four of the skills on this machine actually use. Read as an
    /// ordinary value the description came out as the single character ">".
    func testAFoldedBlockScalarIsJoinedIntoOneLine() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: sketchbook-plate
        description: >
          Paint travel-journal watercolour spreads onto a fixed photograph
          of a real open sketchbook, so every plate shares one paper.
        metadata:
          category: creative
        ---
        """)
        XCTAssertEqual(parsed.name, "sketchbook-plate")
        XCTAssertEqual(parsed.description,
                       "Paint travel-journal watercolour spreads onto a fixed photograph "
                       + "of a real open sketchbook, so every plate shares one paper.")
    }

    /// The block has to end where the indentation does, or the keys after it
    /// are swallowed — `metadata` above must not become part of the sentence.
    func testAKeyAfterABlockScalarIsStillRead() {
        let parsed = SkillFrontmatter.parse("""
        ---
        description: >
          folded text
        name: after-the-block
        ---
        """)
        XCTAssertEqual(parsed.description, "folded text")
        XCTAssertEqual(parsed.name, "after-the-block")
    }

    /// Literal keeps its newlines; folded does not. That is the whole
    /// difference between the two indicators.
    func testALiteralBlockScalarKeepsItsLineBreaks() {
        let parsed = SkillFrontmatter.parse("""
        ---
        description: |
          first line
          second line
        ---
        """)
        XCTAssertEqual(parsed.description, "first line\nsecond line")
    }

    /// A blank line inside a folded block is a paragraph break, not a space.
    func testAFoldedBlockKeepsParagraphBreaks() {
        let parsed = SkillFrontmatter.parse("""
        ---
        description: >
          one two

          three
        ---
        """)
        XCTAssertEqual(parsed.description, "one two\nthree")
    }

    func testChompingIndicatorsAreAccepted() {
        for indicator in [">-", "|-", ">+", "|+"] {
            let parsed = SkillFrontmatter.parse("---\ndescription: \(indicator)\n  text\n---")
            XCTAssertEqual(parsed.description, "text", "\(indicator) was not understood")
        }
    }

    /// `> see below` is prose that happens to start with a chevron, not a block
    /// scalar. Read as one it would swallow whatever key came next.
    func testAChevronFollowedByTextIsAnOrdinaryValue() {
        let parsed = SkillFrontmatter.parse("---\ndescription: > see below\nname: kept\n---")
        XCTAssertEqual(parsed.description, "> see below")
        XCTAssertEqual(parsed.name, "kept")
    }

    func testAFileWithNoFrontmatterYieldsNothing() {
        XCTAssertEqual(SkillFrontmatter.parse("# Just a heading\n\nand prose."),
                       SkillFrontmatter.empty)
    }

    /// A fence that is opened and never closed must not swallow the whole body
    /// as key-value pairs.
    func testAnUnclosedFenceStopsAtTheEnd() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: half
        """)
        XCTAssertEqual(parsed.name, "half")
        XCTAssertNil(parsed.description)
    }

    /// A byte-order mark survives `String(contentsOf:)` and would stop the first
    /// line matching `---`, throwing the whole block away.
    func testALeadingByteOrderMarkIsTolerated() {
        let parsed = SkillFrontmatter.parse("\u{FEFF}---\nname: bom\n---\n")
        XCTAssertEqual(parsed.name, "bom")
    }

    func testCommentsAndBlankLinesAreSkipped() {
        let parsed = SkillFrontmatter.parse("""
        ---
        # what this is
        name: commented

        description: still read
        ---
        """)
        XCTAssertEqual(parsed.name, "commented")
        XCTAssertEqual(parsed.description, "still read")
    }

    /// An empty value is not a value. Left in, it would print a blank title
    /// where the folder name should have shown through.
    func testAnEmptyValueIsTreatedAsAbsent() {
        XCTAssertNil(SkillFrontmatter.parse("---\nname:\n---").name)
    }

    /// Windows line endings arrive with any skill cloned on another machine.
    func testCarriageReturnsAreHandled() {
        let parsed = SkillFrontmatter.parse("---\r\nname: crlf\r\n---\r\n")
        XCTAssertEqual(parsed.name, "crlf")
    }

    // MARK: - Tags

    /// Three spellings, because the format does not settle it and the skills on
    /// this machine use all three.
    func testItReadsTagsUnderAnyOfTheNamesInUse() {
        for key in ["tags", "keywords", "category", "categories"] {
            let found = SkillFrontmatter.parse("""
            ---
            name: x
            \(key): web, Search
            ---
            """)
            XCTAssertEqual(found.tags, ["web", "search"], "\(key) should be read as tags")
        }
    }

    /// `[a, b]`, `a, b` and a block sequence all mean the same list.
    func testEveryYAMLSpellingOfAListReadsTheSame() {
        let inline = SkillFrontmatter.parse("---\ntags: [web, search]\n---")
        let commas = SkillFrontmatter.parse("---\ntags: web, search\n---")
        let block = SkillFrontmatter.parse("""
        ---
        tags:
          - web
          - search
        description: still read after the list
        ---
        """)
        XCTAssertEqual(inline.tags, ["web", "search"])
        XCTAssertEqual(commas.tags, ["web", "search"])
        XCTAssertEqual(block.tags, ["web", "search"])
        XCTAssertEqual(block.description, "still read after the list",
                       "the key after a block sequence is still a key")
    }

    /// Lower-cased and de-duplicated: a tag is something to group by, and `Web`
    /// filtering to a different pile than `web` is a bug a user can see and
    /// cannot explain.
    func testTagsAreLowercasedAndDeduplicated() {
        let found = SkillFrontmatter.parse("---\ntags: Web, web, WEB, \"search\"\n---")
        XCTAssertEqual(found.tags, ["web", "search"])
    }

    func testASkillWithNoTagsHasNone() {
        XCTAssertTrue(SkillFrontmatter.parse("---\nname: x\n---").tags.isEmpty)
    }
}
