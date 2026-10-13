import Combine
import Foundation

/// Owns session-monitor lifetimes: starts a provider's monitor while it is
/// switched on, stops it when it is switched off, and forwards its sessions.
@MainActor
final class ActivityCoordinator {
    private let monitors: [String: any AgentActivityMonitor]
    private let onSessions: (String, [AgentSession]) -> Void
    private var subscriptions: [String: AnyCancellable] = [:]
    private var enabledIDs: Set<String> = []
    private var nativeSessions: [String: [AgentSession]] = [:]
    private(set) var activeIDs: Set<String> = []

    init(monitors: [String: any AgentActivityMonitor],
         onSessions: @escaping (String, [AgentSession]) -> Void) {
        self.monitors = monitors
        self.onSessions = onSessions
    }

    var isBusy: Bool {
        enabledIDs.contains { id in
            let native = activeIDs.contains(id) ? monitors[id]?.sessions ?? [] : []
            return native.contains { $0.state == .busy }
        }
    }

    func setEnabled(_ enabled: Set<String>) {
        let disabled = enabledIDs.subtracting(enabled)
        enabledIDs = enabled

        let wanted = enabled.intersection(monitors.keys)
        for id in activeIDs.subtracting(wanted) {
            activeIDs.remove(id)
            subscriptions.removeValue(forKey: id)?.cancel()
            monitors[id]?.stop()
            nativeSessions.removeValue(forKey: id)
        }
        for id in disabled {
            onSessions(id, [])
        }
        for id in wanted.subtracting(activeIDs) {
            guard let monitor = monitors[id] else { continue }
            activeIDs.insert(id)
            subscriptions[id] = monitor.sessionsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] sessions in
                    guard let self, self.activeIDs.contains(id) else { return }
                    self.nativeSessions[id] = sessions
                    self.publish(id)
                }
            monitor.start()
        }
    }

    func stop() { setEnabled([]) }

    private func publish(_ id: String) {
        guard enabledIDs.contains(id) else { return }
        onSessions(id, mergedSessions(for: id))
    }

    private func mergedSessions(for id: String) -> [AgentSession] {
        nativeSessions[id, default: []]
            .sorted { $0.since == $1.since ? $0.id < $1.id : $0.since > $1.since }
    }
}
