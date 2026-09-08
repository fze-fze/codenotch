import Foundation
import CryptoKit
import CoreFoundation

/// Streaming JSONL reader. A malformed line cannot discard the rest of a session.
enum UsageLogParser {
    struct Result {
        var records: [TokenUsageRecord] = []
        var malformedLines = 0
    }

    static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func count(_ json: [String: Any], _ key: String) -> Int64 {
        guard let number = json[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue < Double(Int64.max) / 16 else { return 0 }
        return max(0, number.int64Value)
    }

    static func read(url: URL, agent: UsageAgent) throws -> Result {
        if agent == .gemini { return try gemini(Data(contentsOf: url), fallbackSession: key(url.path)) }
        // Antigravity is a SQLite database of protobuf, not a line-oriented
        // log, so none of the streaming machinery below applies to it.
        if agent == .antigravity { return AntigravityUsageReader.read(url: url) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var parser = Lines(agent: agent, session: key(url.path))
        var pending = Data()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                parser.consume(Data(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
        }
        if !pending.isEmpty { parser.consume(pending) }
        return parser.result
    }

    struct Lines {
        let agent: UsageAgent
        var session: String
        var model = "Unknown model"
        var previous = TokenCounts()
        var forkDate: Date?
        var result = Result()

        mutating func consume(_ data: Data) {
            guard !data.isEmpty else { return }
            // Avoid decoding conversation content and tool output unless this is accounting metadata.
            let markers = agent == .codex ? ["token_count", "turn_context", "session_meta"] : ["\"usage\""]
            guard markers.contains(where: { data.range(of: Data($0.utf8)) != nil }) else { return }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.malformedLines += 1
                return
            }
            if agent == .codex { codex(json) } else if agent == .claudeCode { claude(json) }
        }

        private mutating func codex(_ json: [String: Any]) {
            guard let payload = json["payload"] as? [String: Any] else { return }
            if json["type"] as? String == "session_meta" {
                if let id = payload["id"] as? String { session = UsageLogParser.key(id) }
                if payload["forked_from_id"] != nil { forkDate = ISO8601Stamp.date(payload["timestamp"]) }
                return
            }
            if json["type"] as? String == "turn_context" {
                model = payload["model"] as? String ?? "Unknown model"
                return
            }
            guard payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let raw = info["total_token_usage"] as? [String: Any],
                  let date = ISO8601Stamp.date(json["timestamp"]) else { return }
            let input = UsageLogParser.count(raw, "input_tokens")
            let cached = min(input, UsageLogParser.count(raw, "cached_input_tokens"))
            let write = min(input - cached, UsageLogParser.count(raw, "cache_write_input_tokens"))
            let output = UsageLogParser.count(raw, "output_tokens")
            let totals = TokenCounts(input: input - cached - write, cached: cached, cacheWrite: write,
                                     output: output,
                                     other: max(0, UsageLogParser.count(raw, "total_tokens") - input - output))
            // Quota-only events repeat the cumulative total. Counter decreases are a new segment.
            guard totals != previous else { return }
            let delta = totals.total < previous.total ? totals : totals.subtracting(previous)
            previous = totals
            guard delta.total > 0, forkDate.map({ date >= $0 }) ?? true else { return }
            let identity = "codex:\(session):\(date.timeIntervalSince1970):\(totals.total)"
            result.records.append(TokenUsageRecord(id: UsageLogParser.key(identity), agent: .codex,
                session: session, timestamp: date, model: info["model"] as? String ?? model, tokens: delta))
        }

        private mutating func claude(_ json: [String: Any]) {
            guard json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let date = ISO8601Stamp.date(json["timestamp"]),
                  let messageID = message["id"] as? String ?? json["uuid"] as? String else { return }
            let write = UsageLogParser.count(usage, "cache_creation_input_tokens")
            let creation = usage["cache_creation"] as? [String: Any] ?? [:]
            let long = min(write, UsageLogParser.count(creation, "ephemeral_1h_input_tokens"))
            let tokens = TokenCounts(input: UsageLogParser.count(usage, "input_tokens"),
                cached: UsageLogParser.count(usage, "cache_read_input_tokens"), cacheWrite: write - long,
                cacheWriteLong: long, output: UsageLogParser.count(usage, "output_tokens"))
            guard tokens.total > 0, message["model"] as? String != "<synthetic>" else { return }
            let sessionID = (json["sessionId"] as? String ?? json["session_id"] as? String).map(UsageLogParser.key) ?? session
            result.records.append(TokenUsageRecord(id: UsageLogParser.key("claude:\(messageID)"),
                agent: .claudeCode, session: sessionID, timestamp: date,
                model: message["model"] as? String ?? "Unknown model", tokens: tokens))
        }
    }

    static func gemini(_ data: Data, fallbackSession: String) throws -> Result {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return Result(malformedLines: 1) }
        let session = (json["sessionId"] as? String).map(key) ?? fallbackSession
        var result = Result()
        for message in messages {
            guard message["type"] as? String == "gemini",
                  let raw = message["tokens"] as? [String: Any],
                  let date = ISO8601Stamp.date(message["timestamp"]),
                  let id = message["id"] as? String else { continue }
            let input = count(raw, "input")
            let cached = min(input, count(raw, "cached"))
            let output = count(raw, "output") + count(raw, "thoughts")
            let tokens = TokenCounts(input: input - cached, cached: cached, output: output,
                                     other: max(0, count(raw, "total") - input - output))
            guard tokens.total > 0 else { continue }
            result.records.append(TokenUsageRecord(id: key("gemini:\(session):\(id)"), agent: .gemini,
                session: session, timestamp: date, model: message["model"] as? String ?? "Unknown model", tokens: tokens))
        }
        return result
    }
}
