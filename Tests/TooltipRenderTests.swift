import XCTest
import SwiftUI
@testable import Codenotch

/// Renders the tooltip with a session in every state.
///
/// Partly a smoke test — a card that fails to lay out fails here rather than on
/// someone's screen — and partly a way to actually look at it: set
/// `TOOLTIP_RENDER_PATH` and the frame is written there.
@MainActor
final class TooltipRenderTests: XCTestCase {
    private func session(_ name: String, _ state: AgentSession.State,
                         minutes: Int) -> AgentSession {
        AgentSession(id: name, name: name, detail: "Terminal · usage-notch",
                     state: state, waitingFor: state == .waiting ? "your answer" : nil,
                     since: Date().addingTimeInterval(Double(-minutes) * 60))
    }

    func testTheCardLaysOutEverySessionState() throws {
        let snapshot = ProviderSnapshot(
            id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.47)]
        )
        let activity = ActivitySummary(sessions: [
            session("codenotch-6f", .idle, minutes: 0),
            session("hivinz-web-2f", .busy, minutes: 1),
            session("codenotch-18", .waiting, minutes: 3)
        ])

        let view = TooltipCard(snapshot: snapshot, activity: activity, now: Date())
            .padding(20)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)

        // Three sessions of two lines each, under the window rows: a card that
        // silently collapsed would still render, just far too short.
        XCTAssertGreaterThan(image.size.height, NotchLayout.cardWidth * 0.5,
                             "the card laid out far shorter than three sessions need")
        XCTAssertGreaterThan(image.size.width, NotchLayout.cardWidth)

        if let path = ProcessInfo.processInfo.environment["TOOLTIP_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// The Antigravity card, with the four windows a real account returns and the
/// reset copy those windows actually produce today — all four fall inside the
/// week, which is the *longest* form the right-hand column ever takes. That is
/// what makes this the worst case for the label beside it, and it is the case
/// that was truncating on screen.
@MainActor
final class AntigravityTooltipRenderTests: XCTestCase {
    func testTheFourWindowCardFitsItsLabels() throws {
        let now = Date()
        func window(_ id: String, _ label: String, _ used: Double, hours: Double) -> LimitWindow {
            LimitWindow(id: id, label: label, usedFraction: used,
                        resetsAt: now.addingTimeInterval(hours * 3600))
        }
        let snapshot = ProviderSnapshot(
            id: "gemini", displayName: "Antigravity", glyph: .antigravity,
            fidelity: .official, status: .ok,
            windows: [
                window("gemini-5h", AntigravityBridge.label(
                    models: "Gemini Models", bucketId: "gemini-5h",
                    window: nil, bucketName: "Weekly Limit Remaining"), 0.014, hours: 4),
                window("gemini-weekly", AntigravityBridge.label(
                    models: "Gemini Models", bucketId: "gemini-weekly",
                    window: "weekly", bucketName: "Weekly Limit Remaining"), 0.024, hours: 6 * 24),
                window("3p-5h", AntigravityBridge.label(
                    models: "Claude and GPT models", bucketId: "3p-5h",
                    window: nil, bucketName: "Weekly Limit Remaining"), 0, hours: 5),
                window("3p-weekly", AntigravityBridge.label(
                    models: "Claude and GPT models", bucketId: "3p-weekly",
                    window: "weekly", bucketName: "Weekly Limit Remaining"), 0, hours: 6 * 24)
            ],
            headlineID: "gemini-5h"
        )

        let view = TooltipCard(snapshot: snapshot, activity: ActivitySummary(sessions: []), now: now)
            .padding(20)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, NotchLayout.cardWidth)

        if let path = ProcessInfo.processInfo.environment["ANTIGRAVITY_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
