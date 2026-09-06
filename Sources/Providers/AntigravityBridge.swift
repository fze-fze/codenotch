import Foundation
import os

/// Asks Antigravity's own language server for the quota, instead of asking
/// Google directly.
///
/// Google refuses us: `retrieveUserQuotaSummary` on `cloudcode-pa` answers 403
/// "You do not have a valid license of this product" for a personal account,
/// because the API judges *which client* is asking and Codenotch cannot
/// honestly claim to be Antigravity. Antigravity's window has the same problem
/// and solves it the same way — it never calls Google for this either. It calls
/// the language server running on this machine, which already holds the
/// credential and the client identity, and lets that make the call.
///
/// So this is not a workaround for a locked door; it is the door Antigravity
/// itself uses. It works only while Antigravity is running, which is honest:
/// the figure comes from Antigravity, so Antigravity has to be there.
enum AntigravityBridge {
    /// Where the language server is listening, and the token it demands.
    struct Endpoint: Equatable {
        /// Every port the server listens on. It opens two and only one serves
        /// this RPC, and which is which is not advertised — so both are tried
        /// rather than guessed at.
        let ports: [Int]
        let csrfToken: String
    }

    /// Antigravity is built on Codeium's stack, and the header still says so.
    /// Six plausible spellings were rejected before this one was found in the
    /// binary — the server's only complaint is "missing CSRF token", never
    /// which header it wanted.
    static let csrfHeader = "x-codeium-csrf-token"

    private static let service =
        "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    // MARK: - Finding it

    /// The token is passed to the language server on its command line, so the
    /// process table is the source of truth. There is no file to read: the
    /// server is started with `--https_server_port 0`, meaning the port is
    /// chosen at runtime and never written down.
    static func discover(processTable: String? = nil, listeningPorts: ((Int) -> [Int])? = nil)
        -> Endpoint? {
        let table = processTable ?? run("/bin/ps", ["-Ao", "pid,command"])
        guard let line = table.split(separator: "\n").first(where: {
            $0.contains("language_server") && $0.contains("--csrf_token")
        }) else { return nil }

        guard let token = value(of: "--csrf_token", in: String(line)),
              let pid = Int(line.trimmingCharacters(in: .whitespaces)
                  .split(separator: " ").first ?? "")
        else { return nil }

        let ports = listeningPorts?(pid) ?? self.listeningPorts(ofPID: pid)
        guard !ports.isEmpty else { return nil }
        return Endpoint(ports: ports, csrfToken: token)
    }

    static func value(of flag: String, in line: String) -> String? {
        let parts = line.split(separator: " ")
        guard let index = parts.firstIndex(of: Substring(flag)),
              index + 1 < parts.count else { return nil }
        return String(parts[index + 1])
    }

    /// Ports are found rather than assumed. The server opens two and only one
    /// serves this RPC, so every candidate is tried in turn.
    static func listeningPorts(ofPID pid: Int) -> [Int] {
        // `-a` is load-bearing: without it lsof ORs the filters rather than
        // ANDing them, and returns every listening socket on the machine. The
        // first match was another process entirely, so the bridge dialled the
        // wrong port and silently fell back to counting requests.
        let output = run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"])
        return parsePorts(fromLSOF: output)
    }

    static func parsePorts(fromLSOF output: String) -> [Int] {
        output.split(separator: "\n").compactMap { line in
            guard let address = line.split(separator: " ").last(where: { $0.contains(":") }),
                  let port = Int(address.split(separator: ":").last ?? "") else { return nil }
            return port
        }
    }

    // MARK: - Asking it

    static func quota(from endpoint: Endpoint, session: URLSession) async throws -> [LimitWindow] {
        var lastError: Error?
        for port in endpoint.ports {
            do {
                let windows = try await quota(port: port, token: endpoint.csrfToken,
                                              session: session)
                if !windows.isEmpty { return windows }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    private static func quota(port: Int, token: String,
                              session: URLSession) async throws -> [LimitWindow] {
        var request = URLRequest(
            url: URL(string: "https://127.0.0.1:\(port)\(service)")!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: csrfHeader)
        // `forceRefresh` is why this reads as live rather than as whatever was
        // last looked at. The language server keeps a `QuotaSummaryCache`, and
        // an empty request is served from it — so the figure only moved when
        // something else refreshed it, which in practice meant opening
        // Antigravity's own Models & Usage panel and pressing its refresh
        // button. The field is real: `RetrieveUserQuotaSummaryRequest` has a
        // `GetForceRefresh` accessor.
        request.httpBody = Data(#"{"forceRefresh":true}"#.utf8)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UsageProviderError.badResponse(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        return windows(in: data)
    }

    /// Turns the quota summary into limit windows.
    ///
    /// The server reports what is **left**, not what is spent — the notch shows
    /// the opposite, so every fraction is inverted here rather than in the view,
    /// where it would be a percentage whose meaning depended on the provider.
    static func windows(in data: Data) -> [LimitWindow] {
        struct Response: Decodable {
            struct Bucket: Decodable {
                let bucketId: String?
                let displayName: String?
                /// Which window this bucket meters — "weekly" on the one shape
                /// captured verbatim. Read as a hint, not as a contract: the
                /// id is the half confirmed for every bucket seen in the wild.
                let window: String?
                let remainingFraction: Double?
                let resetTime: String?
            }
            struct Group: Decodable {
                let displayName: String?
                let buckets: [Bucket]?
            }
            struct Body: Decodable { let groups: [Group]? }
            let response: Body?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let groups = decoded.response?.groups
        else { return [] }

        return groups.flatMap { group -> [LimitWindow] in
            // Soonest deadline first, within each group. Antigravity returns
            // the week before the five hours, but the five hours is the one
            // that actually stops you — and the first window is the one the
            // notch puts on the ring, so the order is not merely cosmetic. It
            // also matches how every other provider here reads: Codex leads
            // with its 5h limit, Claude with the current session.
            //
            // Sorted by when the window rolls rather than by its name, so a
            // window neither of us has seen yet still lands in the right place.
            let buckets = (group.buckets ?? []).sorted { a, b in
                switch (a.resetTime.flatMap(AntigravityCredentials.parse),
                        b.resetTime.flatMap(AntigravityCredentials.parse)) {
                case let (l?, r?): return l < r
                case (nil, _?):    return false   // undated windows go last
                case (_?, nil):    return true
                case (nil, nil):   return false
                }
            }
            return buckets.compactMap { bucket in
                guard let remaining = bucket.remainingFraction,
                      remaining >= 0, remaining <= 1
                else { return nil }
                return LimitWindow(
                    id: bucket.bucketId ?? group.displayName ?? "quota",
                    label: label(models: group.displayName,
                                 bucketId: bucket.bucketId,
                                 window: bucket.window,
                                 bucketName: bucket.displayName),
                    usedFraction: 1 - remaining,
                    resetsAt: bucket.resetTime.flatMap(AntigravityCredentials.parse)
                )
            }
        }
    }

    /// What one row calls itself.
    ///
    /// The group names the models and the bucket names the window, and it
    /// takes both to identify a row. Antigravity meters each group of models
    /// over a rolling five hours *and* over a week, so a label taken from the
    /// group alone printed "Gemini Models" twice and "Claude and GPT models"
    /// twice — four rows with two names between them, and nothing on the row
    /// to say which was which. The reset line was the only tell, and reading
    /// "Resets in 51 min" against "Resets Fri 12:00 AM" is work the label
    /// should have saved.
    ///
    /// The earlier comment here said the bucket "only ever says 'Weekly Limit
    /// Remaining', which is the same for both". That was true of the one
    /// response captured at the time, when each group had a single bucket.
    static func label(models: String?, bucketId: String?,
                      window: String?, bucketName: String?) -> String {
        let period = period(bucketId: bucketId, window: window, bucketName: bucketName)

        // Nothing names the models — an ungrouped bucket, which the direct
        // Google path can return. The window's own words are then the whole
        // label, not half of "Daily Limit · Daily".
        guard let models, !models.isEmpty else {
            return period ?? bucketName ?? "Usage"
        }
        guard let period else { return shorten(models) }
        return "\(shorten(models)) · \(period)"
    }

    /// The models a group covers, in the fewest words that still name them.
    ///
    /// There is very little room. The card is 600 frame px wide, the reset copy
    /// sits on the same line, and a weekly window six days out prints the long
    /// form — "Resets Sat 1:40 AM" — which leaves about half the line for the
    /// label. Google writes "Gemini Models" and "Claude and GPT models", and
    /// the full name plus a window name does not fit: both of that group's rows
    /// truncated to "Claude and GPT m…", which is a worse duplicate than the
    /// one this was meant to cure.
    ///
    /// So the two words that carry nothing are dropped. Every row in this card
    /// is a group of models, which makes the trailing noun redundant, and an
    /// ampersand says "and" in a fifth of the width.
    static func shorten(_ name: String) -> String {
        var text = name
        for suffix in [" models", " Models"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        return text.replacingOccurrences(of: " and ", with: " & ")
    }

    /// Which window a bucket meters, in as few words as the row has room for.
    ///
    /// The id is read first because it is the half confirmed for every bucket
    /// seen in the wild — `gemini-weekly`, `gemini-5h`, `3p-weekly`, `3p-5h` —
    /// and it is what the archive keys on, so it cannot drift without the
    /// stored readings drifting with it. `window` is the server's own word for
    /// the same thing and stands in when the id is not one of those shapes.
    static func period(bucketId: String?, window: String?, bucketName: String?) -> String? {
        for candidate in [bucketId, window] {
            guard let text = candidate?.lowercased(), !text.isEmpty else { continue }
            if text.contains("5h") || text.contains("5-hour") || text.contains("five") {
                return "5h"
            }
            // Named as spans rather than as adverbs — "Week" beside "5h"
            // rather than "Weekly" beside "5h" — because the pair has to read
            // as two lengths of the same thing, and because the six characters
            // saved are the ones that decide whether the row fits.
            if text.contains("week")  { return "Week" }
            if text.contains("month") { return "Month" }
            if text.contains("dai") || text.contains("day") { return "Day" }
            if text.contains("hour")  { return "Hour" }
        }

        // A shape not seen here. Fall back to the bucket's own words with the
        // boilerplate taken off: "Weekly Limit Remaining" spends three words
        // saying what the bar and the percentage under it already say.
        var name = bucketName ?? ""
        for boilerplate in ["Limit", "Remaining", "Quota", "Usage"] {
            name = name.replacingOccurrences(of: boilerplate, with: "")
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: - Plumbing

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
