import XCTest
@testable import Codenotch

final class ActivitySummaryTests: XCTestCase {
    private func session(_ state: AgentSession.State, name: String = "s") -> AgentSession {
        AgentSession(id: name, name: name, detail: "Terminal · \(name)",
                     state: state, waitingFor: nil, since: Date())
    }

    func testNothingRunningMeansNoCell() {
        XCTAssertNil(ActivitySummary(sessions: []))
    }

    /// Blocked outranks busy: it is the only state that is asking you for
    /// something, so it must not be hidden behind a session that is merely busy.
    func testWaitingOutranksWorking() {
        let summary = ActivitySummary(sessions: [session(.busy), session(.waiting), session(.idle)])
        XCTAssertEqual(summary?.state, .waiting)
        XCTAssertEqual(summary?.label, "waiting")
    }

    func testWorkingOutranksIdle() {
        XCTAssertEqual(ActivitySummary(sessions: [session(.idle), session(.busy)])?.state, .working)
    }

    func testAllIdleReadsAsIdle() {
        XCTAssertEqual(ActivitySummary(sessions: [session(.idle), session(.idle)])?.state, .idle)
    }

    /// Working must not borrow a colour from the usage scale — the indicator
    /// sits inside a ring whose colour already means something else.
    func testWorkingIsNeutralAndWaitingIsNot() {
        XCTAssertEqual(ActivitySummary(sessions: [session(.busy)])?.color, Palette.textPrimary)
        XCTAssertEqual(ActivitySummary(sessions: [session(.waiting)])?.color, Palette.watch)
    }
}
