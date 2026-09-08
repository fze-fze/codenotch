import AppKit
import SwiftUI

/// The three pages of the app that are not the notch.
enum PanelTab: String, CaseIterable, Identifiable {
    /// Where the readings come from, and how the notch behaves.
    case settings
    /// Every skill Codenotch knows about, and how far each one reaches.
    case skills
    /// The folders you work in, and what their agents read there.
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .skills:   return "Skills"
        case .projects: return "Projects"
        }
    }

    var symbol: String {
        switch self {
        case .settings: return "gearshape"
        case .skills:   return "square.stack.3d.up"
        case .projects: return "folder"
        }
    }
}

/// One type scale for the whole panel.
///
/// Named rather than reached for at each site, because the first pass used
/// `.caption` and `.footnote` wherever a line felt secondary and the page came
/// out as four sizes of grey — small enough that everything looked like a
/// footnote and nothing looked like a heading. These are a step larger than the
/// system defaults across the board: this is a window you work in, not a
/// palette that has to fit in a corner.
enum PanelFont {
    /// The name of the thing on screen.
    static let title = Font.system(size: 22, weight: .semibold)
    /// Section rows, list rows, control labels — the bulk of the panel.
    static let row = Font.system(size: 14)
    /// A second line under a row, and any sentence that qualifies one.
    static let note = Font.system(size: 13)
    /// Paths and filenames, which have to be read character by character.
    static let mono = Font.system(size: 13, design: .monospaced)
    /// A filename standing in as a row's title.
    static let monoRow = Font.system(size: 14, design: .monospaced)
}

/// Which page is showing. An object rather than `@State` so the menu bar can
/// open the window *on* a page — "Settings…" has to land on Settings.
///
/// Skills is where the panel opens when nobody asked for a page. Settings is a
/// form you visit: you set an edge and a theme once and you are done with it.
/// Skills is the part you come back to — the library changes as you install
/// things, and every project's contents change under you — so it is the page
/// worth landing on, and the one whose being a click away was costing a click
/// every time.
@MainActor
final class PanelSelection: ObservableObject {
    @Published var tab: PanelTab = .skills
}

/// One window, two pages.
///
/// They were two windows. The split was defensible — a short fixed form is a
/// different size of thing from a list you work in — but it produced two
/// separate places to go, each with a menu item, and the second one had to be
/// advertised from inside the first. What they actually are is the same panel:
/// where the app reads from, and what the agents know.
struct CodenotchPanelView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var selection: PanelSelection
    let providers: () -> [ProviderSummary]
    @ObservedObject var skills: SkillManagerModel

    var body: some View {
        TabView(selection: $selection.tab) {
            SettingsView(preferences: preferences, providers: providers)
                .tabItem { Label(PanelTab.settings.title,
                                 systemImage: PanelTab.settings.symbol) }
                .tag(PanelTab.settings)

            SkillsPageView(model: skills)
                .tabItem { Label(PanelTab.skills.title,
                                 systemImage: PanelTab.skills.symbol) }
                .tag(PanelTab.skills)

            ProjectsPageView(model: skills)
                .tabItem { Label(PanelTab.projects.title,
                                 systemImage: PanelTab.projects.symbol) }
                .tag(PanelTab.projects)
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

/// Hosts the panel.
///
/// Kept in the shape both window controllers had, down to
/// `orderFrontRegardless` — an app that can run with no Dock tile is not always
/// allowed to pull a window in front of what the user is working in, and
/// without that the window opens silently behind everything.
///
/// The window is **built on demand and let go when it closes**. This is the
/// difference between a menu bar app and one that behaves like a document
/// editor: `TabView` on macOS instantiates every tab, so opening this once
/// realised the settings form, the whole skill library and every project page
/// at the same time, and holding the window afterwards held all three — with
/// their SwiftUI attribute graph, their rendered rows and their SF Symbols —
/// for the rest of the process's life. The notch, which is what the app is for,
/// needs none of it. Rebuilding costs a few frames on the next open, once.
@MainActor
final class PanelWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let preferences: Preferences
    /// A closure, not a snapshot. Read once at launch, the account shown here
    /// went stale the moment someone switched account in Cursor — and stayed
    /// stale until the app was restarted.
    private let providers: () -> [ProviderSummary]
    /// Readable so a test can assert which page an open landed on. The
    /// landing page is a product decision spread over two defaults — this
    /// object's initial value and `show`'s argument — and a test that cannot
    /// see the result can only check one of them.
    let selection = PanelSelection()
    private let skills: SkillManagerModel

    /// `SkillManagerModel` is `@MainActor`, so it is built here rather than
    /// defaulted in the signature — a default argument is evaluated wherever
    /// the initialiser is called from, which need not be the main actor.
    init(preferences: Preferences,
         providers: @escaping () -> [ProviderSummary],
         skills: SkillManagerModel? = nil) {
        self.preferences = preferences
        self.providers = providers
        self.skills = skills ?? SkillManagerModel()
        super.init()
    }

    func show(_ tab: PanelTab = .skills) {
        selection.tab = tab
        // Re-read on the way in: the library and every project are shared
        // folders, and the most likely reason to have left this window is to
        // have gone and changed something in one.
        if tab != .settings { skills.refresh() }

        if let window {
            surface(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codenotch"
        // A `contentViewController`, not a bare `contentView`. Hosted as a view
        // SwiftUI is not told where the titlebar is, so the top of the content
        // is laid out as if the window began above it and the first row sits
        // underneath the title. A hosting *controller* participates in the
        // window's safe area and the content starts below the chrome.
        window.contentViewController = NSHostingController(
            rootView: CodenotchPanelView(preferences: preferences,
                                         selection: selection,
                                         providers: providers,
                                         skills: skills)
        )
        window.setContentSize(NSSize(width: 900, height: 600))
        window.center()
        // Closing tears the window down rather than parking it. `false` here
        // with a stored reference is what kept the panel resident forever;
        // `windowWillClose` below drops that reference, and AppKit releases the
        // window and its hosting controller once the close completes.
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        surface(window)
    }

    /// Let the whole page go. Both halves matter: the window carries the view
    /// tree, and the model carries what the pages were *showing* — every skill
    /// on the machine with its frontmatter, and every project's contents. Both
    /// are re-read on the way back in, by `show` and by each page's `onAppear`.
    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window?.contentViewController = nil
        window = nil
        skills.releaseCaches()
    }

    private func surface(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
