import XCTest
@testable import Codenotch

final class UsageHistoryTests: XCTestCase {
    private func fixture(_ model: String, output: Int, message: String = "fixture-message") throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "type": "assistant", "timestamp": "2026-09-08T00:00:00Z", "sessionId": "test",
            "message": ["id": message, "model": model, "content": "DO NOT RETAIN THIS PROMPT",
                        "usage": ["input_tokens": 100, "output_tokens": output]]])
        data.append(10)
        return data
    }

    func testImportDeduplicationRefreshRestartAndDeletedLogs() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".claude/projects/project/subagents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("agent.jsonl")
        let duplicate = root.appendingPathComponent("copy.jsonl")
        let archive = home.appendingPathComponent("ledger.json")
        try fixture("test-model", output: 10).write(to: log)
        try fixture("test-model", output: 5).write(to: duplicate)
        let reader = UsageHistoryReader(home: home, archiveURL: archive)
        let first = try await reader.scan()
        XCTAssertEqual(first.records.count, 1)
        XCTAssertEqual(first.records.first?.tokens.total, 110)
        XCTAssertEqual(first.files[.claudeCode], 2)
        let unchanged = try await reader.scan()
        XCTAssertEqual(unchanged.records, first.records)
        try fixture("test-model", output: 1000).write(to: log)
        let changed = try await reader.scan()
        XCTAssertEqual(changed.records.first?.tokens.total, 1100)
        let saved = try String(contentsOf: archive, encoding: .utf8)
        XCTAssertFalse(saved.contains("DO NOT RETAIN"))
        XCTAssertFalse(saved.contains("fixture-message"))
        try FileManager.default.removeItem(at: root)
        let restored = try await UsageHistoryReader(home: home, archiveURL: archive).scan()
        XCTAssertEqual(restored.records.first?.tokens.total, 1100)
        XCTAssertEqual(restored.files[.claudeCode, default: 0], 0)
    }

    func testUnreadableArchiveIsPreservedAndReported() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let archive = home.appendingPathComponent("ledger.json")
        let corrupt = Data("invalid archive".utf8)
        try corrupt.write(to: archive)
        let result = try await UsageHistoryReader(home: home, archiveURL: archive).scan()
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertEqual(try Data(contentsOf: archive), corrupt)
    }

    @MainActor
    func testAgentCombinationsLeaveLifetimeUnfilteredAndPricesPersist() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".claude/projects/project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try fixture("test-model", output: 10).write(to: root.appendingPathComponent("test.jsonl"))
        let suite = "usage-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = UsageHistoryReader(home: home, archiveURL: home.appendingPathComponent("ledger.json"))
        let model = UsageDashboardModel(reader: reader, defaults: defaults)
        await model.refresh()
        model.period = .all
        XCTAssertEqual(model.lifetime.tokens.total, 110)
        model.selectedAgents = [.codex]
        XCTAssertEqual(model.filtered.tokens.total, 0)
        XCTAssertEqual(model.lifetime.tokens.total, 110)
        model.toggle(.claudeCode)
        XCTAssertEqual(model.filtered.tokens.total, 110)
        XCTAssertEqual(model.filtered.unpriced, 1)
        model.savePrice(model: "test-model", price: .init(input: 2, output: 10))
        XCTAssertEqual(model.filtered.unpriced, 0)
        XCTAssertEqual(model.filtered.cost, 0.0003, accuracy: 0.0000001)
        let reopened = UsageDashboardModel(reader: reader, defaults: defaults)
        XCTAssertEqual(reopened.prices["test-model"], model.prices["test-model"])
        model.selectedAgents = []
        XCTAssertEqual(model.filtered.tokens.total, 0)
        XCTAssertEqual(model.lifetime.tokens.total, 110)
    }
}
