import SwiftUI
import XCTest
@testable import Codenotch

@MainActor
final class AccessibilityTransparencyTests: XCTestCase {
    func testEnvironmentValueCanBeOverridden() {
        var values = EnvironmentValues()
        XCTAssertFalse(values.codenotchReduceTransparency)
        values.codenotchReduceTransparency = true
        XCTAssertTrue(values.codenotchReduceTransparency)
    }

    func testProviderRingRendersUnderStandardAndReducedTransparency() throws {
        let normalRing = ProviderRing(usedFraction: 0.5, glyph: .claude)
            .environment(\.codenotchReduceTransparency, false)
            .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)

        let reducedRing = ProviderRing(usedFraction: 0.5, glyph: .claude)
            .environment(\.codenotchReduceTransparency, true)
            .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)

        let normalRenderer = ImageRenderer(content: normalRing)
        let reducedRenderer = ImageRenderer(content: reducedRing)

        let normalImage = try XCTUnwrap(normalRenderer.nsImage)
        let reducedImage = try XCTUnwrap(reducedRenderer.nsImage)

        XCTAssertEqual(normalImage.size.width, NotchLayout.ringDiameter)
        XCTAssertEqual(reducedImage.size.width, NotchLayout.ringDiameter)
    }

    func testExhaustedAndStaleProviderRingsRenderUnderReducedTransparency() throws {
        let staleExhaustedRing = ProviderRing(
            usedFraction: 1.0,
            glyph: .grok,
            isStale: true,
            isBlocked: true
        )
        .environment(\.codenotchReduceTransparency, true)
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)

        let renderer = ImageRenderer(content: staleExhaustedRing)
        let image = try XCTUnwrap(renderer.nsImage)

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testTooltipCardRendersUnderReducedTransparency() throws {
        let snapshot = ProviderSnapshot(
            id: "claude",
            displayName: "Claude",
            glyph: .claude,
            fidelity: .official,
            status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.6)]
        )

        let standardCard = TooltipCard(snapshot: snapshot, now: Date())
            .environment(\.codenotchReduceTransparency, false)
            .padding(10)

        let reducedCard = TooltipCard(snapshot: snapshot, now: Date())
            .environment(\.codenotchReduceTransparency, true)
            .padding(10)

        let standardImage = try XCTUnwrap(ImageRenderer(content: standardCard).nsImage)
        let reducedImage = try XCTUnwrap(ImageRenderer(content: reducedCard).nsImage)

        XCTAssertGreaterThan(standardImage.size.height, 0)
        XCTAssertEqual(reducedImage.size, standardImage.size,
                       "reduced transparency changes the material, not the card's size")
    }

    func testSettingsViewRendersUnderReducedTransparency() throws {
        let defaults = UserDefaults(suiteName: "AccessibilityTransparencyTests.\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        let updater = Updater()

        let view = SettingsView(
            preferences: preferences,
            providers: { [] },
            signOut: { _ in },
            signIn: { _ in false },
            switchAccount: { _ in false },
            retry: { _ in },
            resetPosition: {},
            quit: {},
            updater: updater
        )
        .environment(\.codenotchReduceTransparency, true)
        .frame(width: SettingsView.width, height: SettingsView.height)

        let renderer = ImageRenderer(content: view)
        let image = try XCTUnwrap(renderer.nsImage)

        XCTAssertEqual(image.size.width, SettingsView.width)
        XCTAssertEqual(image.size.height, SettingsView.height)
    }
}
