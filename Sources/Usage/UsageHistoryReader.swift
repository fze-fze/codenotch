import Foundation

/// Keeps a metadata-only ledger across log rotation, and reparses only changed files.
actor UsageHistoryReader {
    struct Snapshot: Sendable {
        var records: [TokenUsageRecord]
        var files: [UsageAgent: Int]
        var warnings: [String]
    }
    private struct Signature: Codable, Equatable {
        let size: Int
        let modified: Date
    }
    private struct Archive: Codable {
        var version = 1
        var records: [String: TokenUsageRecord] = [:]
        var files: [String: Signature] = [:]
    }
    private let home: URL
    private let archiveURL: URL
    private var archive = Archive()
    private var loaded = false
    private var needsSave = false
    private var archiveProblem: String?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, archiveURL: URL? = nil) {
        self.home = home
        self.archiveURL = archiveURL ?? home.appendingPathComponent(
            "Library/Application Support/Codenotch/token-history-v1.json")
    }

    func scan() throws -> Snapshot {
        let manager = FileManager.default
        if !loaded {
            loaded = true
            if manager.fileExists(atPath: archiveURL.path) {
                do {
                    let saved = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: archiveURL))
                    guard saved.version == 1 else { throw CocoaError(.coderReadCorrupt) }
                    archive = saved
                } catch {
                    archiveProblem = "Saved history could not be read. Local logs are shown; the saved file has been preserved."
                }
            }
        }
        var warnings = archiveProblem.map { [$0] } ?? []
        var fileCounts: [UsageAgent: Int] = [:]
        for agent in UsageAgent.allCases where agent.supportsHistory {
            for root in agent.roots(home: home) {
                guard manager.fileExists(atPath: root.path) else { continue }
                var enumerationFailed = false
                guard let enumerator = manager.enumerator(at: root,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles], errorHandler: { _, _ in
                        enumerationFailed = true
                        return true
                    }) else {
                    warnings.append("\(agent.title): history folder could not be read.")
                    continue
                }
                var failures = 0
                for case let url as URL in enumerator {
                    try Task.checkCancellation()
                    guard agent.matches(url) else { continue }
                    fileCounts[agent, default: 0] += 1
                    do {
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                        guard values.isRegularFile == true else { continue }
                        let signature = Signature(size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
                        let fileKey = UsageLogParser.key(url.path)
                        guard archive.files[fileKey] != signature else { continue }
                        let parsed = try UsageLogParser.read(url: url, agent: agent)
                        for record in parsed.records {
                            if let existing = archive.records[record.id] {
                                var merged = existing
                                merged.tokens = existing.tokens.merging(record.tokens)
                                archive.records[record.id] = merged
                            } else {
                                archive.records[record.id] = record
                            }
                        }
                        // Retry partial writes and malformed files on the next refresh.
                        if parsed.malformedLines == 0 { archive.files[fileKey] = signature }
                        else { failures += 1 }
                        needsSave = true
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures += 1 }
                }
                if enumerationFailed { warnings.append("\(agent.title): some history folders are inaccessible.") }
                if failures > 0 { warnings.append("\(agent.title): \(failures) files were incomplete or unreadable; valid records were kept.") }
            }
        }
        try Task.checkCancellation()
        if needsSave && archiveProblem == nil {
            do {
                try manager.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(archive).write(to: archiveURL, options: .atomic)
                needsSave = false
            } catch {
                warnings.append("History could not be saved. These readings are available for this window only.")
            }
        }
        return Snapshot(records: Array(archive.records.values), files: fileCounts, warnings: warnings)
    }
}
