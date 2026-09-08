import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var store: UsageStore?
    private var monitors: [String: any AgentActivityMonitor] = [:]
    private var preferences: Preferences?
    private var panel: PanelWindowController?
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    /// The unit bundle is hosted by this app, so `xcodebuild test` launches it
    /// for real. Without this guard every test run put a live request on the
    /// usage endpoint — which is both wrong on its own terms and, on an endpoint
    /// that rate-limits, actively harmful.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set here, not in the Info.plist: this call is applied at launch and
        // overrides `LSUIElement` either way. Removing the plist key alone left
        // the app registered as a UIElement with no Dock tile, which looked
        // exactly like the icon having failed to install. The user's choice
        // replaces this a moment later, once preferences exist.
        NSApp.setActivationPolicy(.regular)
        guard !isRunningTests else { return }

        let controller = NotchWindowController()

        // Built outside the demo branch below: the Skill half reads no provider
        // and no credential, so it works the same whether the notch is showing
        // real readings or the design frame's.
        let skillsModel = SkillManagerModel()

        // `CODENOTCH_DEMO=1` puts the design frame's three providers on screen
        // with its numbers, for screenshots and for eyeballing the layout.
        let isDemo = ProcessInfo.processInfo.environment["CODENOTCH_DEMO"] == "1"
        let preferences = Preferences()
        self.preferences = preferences
        // Before any window exists. Applied after one is on screen, the panel
        // opens in the system appearance and then repaints, which reads as a
        // flash of the wrong theme on every launch.
        preferences.appearance.apply()

        if isDemo {
            controller.model.snapshots = Fixtures.snapshots()
            let panel = PanelWindowController(preferences: preferences,
                                              providers: { [] },
                                              skills: skillsModel)
            controller.onOpenSettings = { [weak panel] in panel?.show(.settings) }
            controller.onOpenSkills = { [weak panel] in panel?.show(.skills) }
            self.panel = panel
        } else {

            // Cursor reads the editor's own session rather than a browser one:
            // signing into cursor.com separately created a second, empty account.
            //
            // Built *after* preferences and told what is switched off, so the
            // very first list it draws already excludes them. Constructed first,
            // it drew every provider from the archive and only dropped the
            // switched-off ones once the binding below delivered.
            let store = UsageStore(
                providers: [ClaudeOAuthProvider(), CursorLocalProvider(),
                            CodexLocalProvider(), AntigravityProvider(),
                            GrokLocalProvider()],
                disconnected: preferences.disconnectedProviders
            )

            // The stored edge goes in before the panel is ever put up. The
            // sink below delivers on the next run loop turn, by which time the
            // notch has already been shown on the default edge — so without
            // this, every launch on any other edge opens with a flash of the
            // right-hand one and then crossfades away from it.
            controller.model.edge = preferences.notchEdge

            let panel = PanelWindowController(
                preferences: preferences,
                // A closure so the page re-reads accounts each time it comes
                // forward; a snapshot here is what made a switched account keep
                // showing the old address until the app restarted.
                providers: { [weak store] in store?.providerSummaries ?? [] },
                skills: skillsModel
            )
            controller.onOpenSettings = { [weak panel] in panel?.show(.settings) }
            controller.onOpenSkills = { [weak panel] in panel?.show(.skills) }
            self.panel = panel

            let statusItem = StatusItemController(
                onOpenSettings: { [weak panel] in panel?.show(.settings) },
                onOpenSkills: { [weak panel] in panel?.show(.skills) }
            )
            self.statusItem = statusItem

            preferences.$appPresence
                .receive(on: RunLoop.main)
                .sink { presence in
                    NSApp.setActivationPolicy(presence.activationPolicy)
                    if presence.wantsStatusItem { statusItem.show() } else { statusItem.hide() }
                }
                .store(in: &cancellables)

            preferences.$notchVisibility
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.apply($0) }
                .store(in: &cancellables)

            preferences.$notchEdge
                .receive(on: RunLoop.main)
                .sink { [weak controller] in controller?.apply(edge: $0) }
                .store(in: &cancellables)

            preferences.$disconnectedProviders
                .receive(on: RunLoop.main)
                .sink { [weak store] in store?.disconnected = $0 }
                .store(in: &cancellables)

            store.$snapshots
                .receive(on: RunLoop.main)
                .sink { [weak controller] snapshots in
                    withAnimation(NotchMotion.unfold) {
                        controller?.model.snapshots = snapshots
                    }
                    controller?.model.now = Date()
                }
                .store(in: &cancellables)
            store.start()
            controller.onRefresh = { [weak store] in store?.refreshNow() }
            controller.onRefreshProvider = { [weak store] id in store?.refresh(providerID: id) }
            store.$refreshing
                .receive(on: RunLoop.main)
                .sink { [weak controller] ids in controller?.model.refreshing = ids }
                .store(in: &cancellables)

            self.store = store
        }

        // What each agent is doing right now, so the notch can say whether it is
        // still working without you switching to it.
        let monitors: [String: any AgentActivityMonitor] = [
            "claude": ClaudeSessionMonitor(),
            "cursor": CursorActivityMonitor(),
            "codex": CodexActivityMonitor(),
            "gemini": AntigravityActivityMonitor(),
            "grok": GrokActivityMonitor()
        ]
        for (id, monitor) in monitors {
            monitor.sessionsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak controller] live in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        controller?.model.sessions[id] = live
                    }
                    controller?.model.now = Date()
                }
                .store(in: &cancellables)
            monitor.start()
        }
        // Poll usage hard only while something is actually running.
        store?.isBusy = { monitors.values.contains { m in m.sessions.contains { $0.state == .busy } } }
        self.monitors = monitors

        controller.show()
        notchController = controller
    }

    /// Closing the settings window must not take the app with it.
    ///
    /// The default for a Dock app is to quit once its last window closes, which
    /// here would kill the notch — the part that is actually the product —
    /// every time someone shut the settings they had just opened.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The way back in when the notch is hidden.
    ///
    /// With no dock icon, no menu bar item and no notch on screen, there is
    /// otherwise nothing left to click — choosing Hide would be a one-way door.
    /// Launching the app again while it is already running lands here, so
    /// opening it from Applications or Spotlight puts the panel back up.
    ///
    /// It opens on the panel's own default page rather than naming one. That
    /// used to be Settings, on the grounds that this is the rescue hatch and
    /// Settings is where the notch gets switched back on. It still is: the tabs
    /// are along the top of the window this returns, so Settings is one click
    /// from wherever it lands. Nothing about the door being open depended on
    /// which page it opened onto.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        panel?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
        monitors.values.forEach { $0.stop() }
        notchController?.stop()
    }
}
