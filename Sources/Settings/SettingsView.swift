import AppKit
import SwiftUI

/// The settings sheet, reached from the orb below the notch.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let providers: () -> [ProviderSummary]
    /// Re-read whenever the sheet comes forward. Switching account happens in
    /// another app, so the user is always coming *back* here to see it — which
    /// makes returning focus the exact moment the old value is wrong.
    @State private var accounts: [ProviderSummary] = []

    var body: some View {
        Form {
            // Read-only, deliberately. Codenotch never holds these accounts —
            // each reading is borrowed from the tool that does — so the rows
            // say whose account a number belongs to and stop there.
            Section("Integrations") {
                ForEach(accounts) { AccountRow(provider: $0) }
            }

            Section("Appearance") {
                Picker("Show", selection: $preferences.notchVisibility) {
                    ForEach(NotchVisibility.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Hide leaves nothing on screen — \(SettingsView.wayBack)")

                Picker("Edge", selection: $preferences.notchEdge) {
                    ForEach(NotchEdge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("App icon", selection: $preferences.appPresence) {
                    ForEach(AppPresence.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Neither leaves no icon anywhere — \(SettingsView.wayBack)")

                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                Toggle("Open Codenotch at login", isOn: $preferences.launchAtLogin)
                if let problem = preferences.launchAtLoginProblem {
                    Text(problem)
                        .font(PanelFont.note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(PanelFont.row)
        .formStyle(.grouped)
        // Capped rather than fixed. The panel is sized for the Skills page,
        // and a settings form stretched to 900 points is a row of controls
        // with a hand's width of nothing between the label and the switch.
        .frame(maxWidth: SettingsView.width)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { accounts = providers() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification
        )) { _ in accounts = providers() }
    }

    /// The widest the form is allowed to get, not the width of a window — it
    /// no longer has one of its own.
    static let width: CGFloat = 520

    /// Said on the control rather than under it: both "Hide" and "Neither"
    /// take away every visible way back to this window, which is worth
    /// knowing — but not worth a permanent line under a picker that is right
    /// most of the time.
    ///
    /// One string, because it is one fact. The two pickers used to state it in
    /// their own words, and two phrasings of the same sentence on adjacent
    /// rows read as two different warnings.
    static let wayBack = "reopen Codenotch from Applications to get back here"
}

/// One provider: whose account the reading belongs to, and whether it is
/// coming through. Nothing here is a control — the account belongs to the tool
/// that issued it, so the honest place to change any of it is that tool.
private struct AccountRow: View {
    let provider: ProviderSummary

    var body: some View {
        // Centred, not baseline-aligned. A glyph is a `Shape` and has no text
        // baseline, so `.firstTextBaseline` lines its *bottom edge* up with the
        // text's baseline and lifts every icon above its own name.
        HStack(alignment: .center, spacing: 10) {
            ProviderGlyphView(glyph: provider.glyph, size: 16)
                .foregroundStyle(isReading ? .primary : .tertiary)

            Text(provider.name)

            Spacer(minLength: 12)

            if let account = provider.account {
                Text(account.summary)
                    .font(PanelFont.note)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("No account")
                    .font(PanelFont.note)
                    .foregroundStyle(.tertiary)
            }

            // Last in the row and a fixed width, so the dots line up down the
            // section however long the account line above them runs. Colour is
            // the whole message; the words for it are a hover away.
            Circle()
                .fill(isReading ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .frame(width: 10, alignment: .center)
                .help(isReading ? "Connected" : provider.signIn.explanation)
        }
    }

    /// Whether a reading is actually arriving.
    private var isReading: Bool { provider.account != nil }
}
