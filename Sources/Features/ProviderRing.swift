import AppKit
import SwiftUI

/// The ring around a provider glyph: a grey track with a coloured arc that
/// starts at 12 o'clock and sweeps clockwise by the fraction used.
struct ProviderRing: View {
    /// Nil when the provider reports what is left but never says out of what —
    /// there is no arc to draw, and inventing one would be a lie in a shape.
    let usedFraction: Double?
    let glyph: ProviderGlyph
    var isStale: Bool = false
    /// Blocked right now. Shown as spent whatever the arc says, because that is
    /// what it means for you — a ring reading 16% while the account is paused
    /// is technically true and practically a lie.
    var isBlocked: Bool = false
    /// A fetch this cell asked for, in flight.
    var isRefreshing: Bool = false
    /// The weekly limit, when the provider has one. Nil is the ordinary case
    /// for a provider with a single window, and draws nothing.
    var weeklyFraction: Double?
    /// Where the user asked for it, if at all.
    var weeklyRing: WeeklyRing = .off
    var bandOverride: UsageBand? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency
    @Environment(\.usageWatchLimit) private var watchLimit
    @Environment(\.usageCriticalLimit) private var criticalLimit
    @Environment(\.colorTransitionStyle) private var colorTransitionStyle
    @Environment(\.codenotchAccentColor) private var accentColor
    @Environment(\.weeklyRingDashed) private var weeklyRingDashed
    @State private var spin: Double = 0

    private var band: UsageBand {
        guard !isBlocked else { return .exhausted }
        if let bandOverride { return bandOverride }
        return UsageBand.band(for: usedFraction ?? 0, watchLimit: watchLimit, criticalLimit: criticalLimit)
    }
    private var sweep: CGFloat { CGFloat(min(max(usedFraction ?? 0, 0), 1)) }
    private var primaryColor: Color {
        isStale ? Palette.textSecondary : band.color(accent: accentColor)
    }

    /// The ring's actual stroke colour: a continuous ramp when that style is chosen, falling
    /// back to the discrete `band.color(accent:)` in hard-step mode and everywhere `band` itself
    /// special-cases — blocked (no fraction is meaningful once a limit is spent) and an explicit
    /// override from the caller (a deliberate discrete choice, not a reading to interpolate).
    private var primaryRingColor: Color {
        guard !isBlocked, bandOverride == nil, colorTransitionStyle == .ramp else {
            return band.color(accent: accentColor)
        }
        return UsageBand.rampColor(for: usedFraction ?? 0, watchLimit: watchLimit, accent: accentColor)
    }

    private var weeklyBand: UsageBand {
        isBlocked ? .exhausted : UsageBand.band(for: weeklyFraction ?? 0, watchLimit: watchLimit, criticalLimit: criticalLimit)
    }
    private var weeklySweep: CGFloat { CGFloat(min(max(weeklyFraction ?? 0, 0), 1)) }
    /// Same fallback rule as `primaryRingColor`, minus `bandOverride` — the weekly ring has none.
    private var weeklyRingColor: Color {
        guard !isBlocked, colorTransitionStyle == .ramp else { return weeklyBand.color(accent: accentColor) }
        return UsageBand.rampColor(for: weeklyFraction ?? 0, watchLimit: watchLimit, accent: accentColor)
    }

    var body: some View {
        ZStack {
            // Dimming applies to the usage reading only. Whether Claude is
            // working right now is known first-hand and stays at full strength
            // even when the percentage behind it has gone stale.
            ZStack {
                Circle()
                    .strokeBorder(Palette.ringTrack, lineWidth: NotchLayout.trackStroke)

                if usedFraction != nil {
                    Circle()
                        .inset(by: NotchLayout.trackStroke / 2)
                        .trim(from: 0, to: sweep)
                        .stroke(
                            primaryRingColor,
                            style: StrokeStyle(lineWidth: NotchLayout.progressStroke, lineCap: .round)
                        )
                        // Refreshing spins the reading itself rather than
                        // overlaying a separate spinner: the thing being
                        // refetched is the thing that should move, and a second
                        // arc on the same track only competes with it.
                        .rotationEffect(.degrees(-90 + spin))
                        // A ring that snaps to a new value reads as a glitch; one
                        // that sweeps reads as a measurement being taken.
                        .animation(NotchMotion.reading, value: sweep)
                        .animation(NotchMotion.reading, value: band)
                }

                // The weekly limit, when there is one and it has been asked
                // for. Same start and direction as the headline arc, so the
                // two are read the same way round; thinner and at its own
                // radius, so which is which never has to be worked out.
                //
                // It carries its own band colour rather than borrowing the
                // headline's: a session at 12% beside a week at 91% is exactly
                // the case this exists for, and painting them the same colour
                // would hide it. Held slightly back in opacity so the headline
                // stays the one the eye lands on first.
                if let radius = weeklyRing.radius, weeklyFraction != nil {
                    let inset = NotchLayout.ringDiameter / 2 - radius

                    // A track of its own, for the same reason the headline has
                    // one: a week nobody has spent yet draws an arc of zero
                    // length, and without something behind it that is
                    // indistinguishable from the feature being broken. Codex
                    // opened its week at 0% and read as missing.
                    Circle()
                        .inset(by: inset)
                        .stroke(Palette.ringTrack,
                                style: StrokeStyle(lineWidth: NotchLayout.weeklyRingStroke,
                                                   dash: weeklyRingDashed ? [4, 2] : []))
                        .opacity(reduceTransparency ? 1 : 0.7)

                    Circle()
                        .inset(by: inset)
                        .trim(from: 0, to: weeklySweep)
                        .stroke(
                            weeklyRingColor,
                            style: StrokeStyle(lineWidth: NotchLayout.weeklyRingStroke,
                                               lineCap: weeklyRingDashed ? .butt : .round,
                                               dash: weeklyRingDashed ? [4, 2] : [])
                        )
                        .opacity(reduceTransparency ? 1 : 0.8)
                        .rotationEffect(.degrees(-90))
                        .animation(NotchMotion.reading, value: weeklySweep)
                        .animation(NotchMotion.reading, value: weeklyBand)
                }

                ProviderGlyphView(glyph: glyph)
                    .foregroundStyle(Palette.textPrimary)
                    // A spent limit dims its glyph so the ring reads as "waiting".
                    // Under reduce-transparency, boost opacity so it stays legible without low alpha.
                    .opacity(band == .exhausted ? (reduceTransparency ? 0.7 : 0.35) : 1)
            }
            .opacity(isStale ? (reduceTransparency ? 0.75 : 0.45) : 1)

        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
        // Pressed in while it works, and released when the answer lands. The
        // ring is the button, so the ring is what should feel pressed.
        .scaleEffect(isRefreshing ? 0.93 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isRefreshing)
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            // Exactly one turn, and it stops by itself.
            //
            // The obvious spelling is a `repeatForever` linear spin started on
            // the way in and cancelled on the way out — but `repeatForever` does
            // not stop when you set the value back, and if the value you set is
            // the one it is already animating toward, nothing changes and it
            // simply keeps going. The ring then spins for ever after a refresh
            // that finished half a second in.
            //
            // A single finite turn has no cancellation problem at all: 360° is
            // the same angle as 0°, so it lands exactly where the reading
            // belongs. It eases out, so it settles rather than stopping dead.
            withAnimation(.timingCurve(0.32, 0, 0.14, 1, duration: 0.95)) {
                spin += 360
            }
        }
    }
}

struct ProviderCell: View {
    let snapshot: ProviderSnapshot
    var isRefreshing: Bool = false
    var weeklyRing: WeeklyRing = .off
    /// Whether the reading adds the weekly ring's percentage, as "30%/70%".
    var showsWeeklyReading: Bool = false
    /// Whether the percentage is drawn under the ring.
    ///
    /// Off where the cell sits in a menu-bar strip beside the hardware notch:
    /// the strip is the menu bar's height, which one ring already fills, and a
    /// second line would be drawn in the bezel. The reading is still a hover
    /// away in the card.
    var showsReading: Bool = true

    private var reading: ProviderReading {
        ProviderReading(snapshot: snapshot, weeklyRing: weeklyRing,
                        showsWeeklyReading: showsWeeklyReading)
    }

    private var readingText: String { reading.text }

    var body: some View {
        VStack(spacing: NotchLayout.ringLabelGap) {
            ProviderRing(
                usedFraction: snapshot.hasReading ? snapshot.ringFraction : nil,
                glyph: snapshot.glyph,
                isStale: snapshot.status.isStale || !snapshot.hasReading,
                isBlocked: snapshot.block != nil,
                isRefreshing: isRefreshing,
                weeklyFraction: snapshot.hasReading ? snapshot.weeklyFraction : nil,
                weeklyRing: weeklyRing,
                bandOverride: snapshot.bandOverride
            )
            if showsReading { reading }
        }
        .frame(height: NotchLayout.cellExtent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Everything the cell says, as one sentence for VoiceOver and the tests.
    var accessibilityText: String {
        "\(snapshot.displayName), \(readingText)"
    }
}

private struct WeeklyRingDashedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var weeklyRingDashed: Bool {
        get { self[WeeklyRingDashedKey.self] }
        set { self[WeeklyRingDashedKey.self] = newValue }
    }
}

/// **A cell's percentage**, on its own: under its ring, or — merged into the
/// Mac's notch with a single ring — on the other side of the Mac's notch,
/// where the notch widens with nothing else to carry.
struct ProviderReading: View {
    let snapshot: ProviderSnapshot
    var weeklyRing: WeeklyRing = .off
    /// Whether the reading adds the weekly ring's percentage, as "30%/70%".
    var showsWeeklyReading: Bool = false
    /// Drawn on its own across the Mac's notch rather than under the ring: the
    /// larger size, and no more room along the bar than `width`.
    var across: CGFloat? = nil
    /// Which end of that room it sits at — the Mac's notch's.
    var acrossAlignment: Alignment = .leading

    /// A dash, not "0%": nothing read is not the same as nothing used.
    var text: String {
        guard snapshot.hasReading else { return "—" }
        guard let weekly = weeklyReading else { return snapshot.headlineText }
        return "\(snapshot.headlineText)/\(Percent.text(for: weekly))%"
    }

    /// What the weekly ring draws, when it and its reading are on. The pair
    /// mirrors the two rings, so with the weekly limit as the main ring or the
    /// daily pace ring the second number is the session, as the thin ring is.
    ///
    /// Only after a percentage: a count or a cost with a percentage after it
    /// would read as one quantity, and it is not.
    private var weeklyReading: Double? {
        guard showsWeeklyReading, weeklyRing != .off,
              snapshot.usedFraction != nil, snapshot.headline?.prefersUsedText != true
        else { return nil }
        return snapshot.weeklyFraction
    }

    /// Whether it reads as the pair, "30%/70%".
    var isPair: Bool { snapshot.hasReading && weeklyReading != nil }

    /// How wide it is drawn across the Mac's notch, in design points — what
    /// the side carrying it is sized to.
    var acrossWidth: CGFloat {
        let size = isPair ? Typography.percentPairAcrossSize : Typography.percentAcrossSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        if let width = across {
            Text(text)
                .font(isPair ? Typography.percentPairAcross : Typography.percentAcross)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                // Never into the side's own curved end: smaller before that.
                .minimumScaleFactor(0.4)
                .frame(width: width, alignment: acrossAlignment)
                .contentTransition(.numericText())
                .animation(NotchMotion.reading, value: text)
        } else {
            underTheRing
        }
    }

    private var underTheRing: some View {
        Text(text)
            .font(snapshot.hasReading && weeklyReading != nil ? Typography.percentPair : Typography.percent)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: NotchLayout.percentLineHeight)
            .contentTransition(.numericText())
            .animation(NotchMotion.reading, value: text)
    }
}
