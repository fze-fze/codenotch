import Foundation

struct PhoneLinkSnapshotBuilder {
    static func formatISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: date)
    }

    static func build(
        snapshots: [ProviderSnapshot],
        disconnected: Set<String>,
        order: [String],
        serverName: String,
        serverVersion: String,
        now: Date
    ) -> PhoneLinkSnapshot {
        let server = PhoneLinkSnapshot.ServerInfo(
            name: serverName,
            version: serverVersion,
            generatedAt: formatISO(now),
            demo: false
        )
        
        var providers: [PhoneLinkSnapshot.Provider] = []
        var orderedSnaps = snapshots
        
        if !order.isEmpty {
            orderedSnaps.sort { a, b in
                let aIndex = order.firstIndex(of: a.id) ?? Int.max
                let bIndex = order.firstIndex(of: b.id) ?? Int.max
                return aIndex < bIndex
            }
        }
        
        for snap in orderedSnaps {
            if disconnected.contains(snap.id) { continue }
            
            var kindStr = "ok"
            var sinceStr: String? = nil
            var whyStr: String? = nil
            
            switch snap.status {
            case .ok: kindStr = "ok"
            case .stale(let since): 
                kindStr = "stale"
                sinceStr = formatISO(since)
            case .needsAuth, .signedOutByOwner: kindStr = "needsAuth"
            case .accessDenied: kindStr = "accessDenied"
            case .unsupported(let why):
                kindStr = "unsupported"
                whyStr = why
            case .error(let why):
                kindStr = "error"
                whyStr = why
            }
            
            let status = PhoneLinkSnapshot.Status(kind: kindStr, since: sinceStr, why: whyStr)
            
            let windows = snap.windows.map { w in
                PhoneLinkSnapshot.Window(
                    id: w.id,
                    label: w.label,
                    usedFraction: w.usedFraction,
                    remaining: w.remaining,
                    used: w.used,
                    resetsAt: w.resetsAt.map { formatISO($0) }
                )
            }
            
            let block = snap.block.map { b in
                PhoneLinkSnapshot.Block(reason: b.reason, resetsAt: b.resetsAt.map { formatISO($0) })
            }
            
            let account = snap.plan.map { PhoneLinkSnapshot.Account(plan: $0, source: "Codenotch") }
            
            let p = PhoneLinkSnapshot.Provider(
                id: snap.id,
                displayName: snap.displayName,
                fidelity: String(describing: snap.fidelity),
                status: status,
                windows: windows,
                headlineId: snap.headlineID,
                block: block,
                account: account
            )
            providers.append(p)
        }
        
        // The wire format keeps its `sessions` array for the phone, which
        // expects it; Codenotch no longer tracks sessions, so it is empty.
        return PhoneLinkSnapshot(server: server, providers: providers, sessions: [])
    }
}
