import Foundation
import Observation

@MainActor @Observable
final class UsageDashboardModel {
    var selectedAgents = Set(UsageAgent.allCases) { didSet { recomputeFiltered() } }
    var period: UsagePeriod = .week { didSet { recomputeFiltered() } }
    var grouping: UsageGrouping = .model { didSet { recomputeFiltered() } }
    private(set) var activity = UsageActivity(days: [], now: Date())
    private(set) var series = UsageSeries(records: [], grouping: .model, period: .week, now: Date(), prices: [:], domain: [])
    private(set) var lifetime = UsageSummary()
    private(set) var filtered = UsageSummary()
    private(set) var isRefreshing = false
    private(set) var loaded = false
    private(set) var updatedAt: Date?
    private(set) var warnings: [String] = []
    private(set) var sourceFiles: [UsageAgent: Int] = [:]
    private(set) var sources: [UsageSourceStatus] = []
    private(set) var prices = UsagePricing.defaults
    private(set) var pricingProblem: String?
    @ObservationIgnored private var records: [TokenUsageRecord] = []
    @ObservationIgnored private let reader: UsageHistoryReader
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var overrides: [String: ModelTokenPrice] = [:]
    @ObservationIgnored private var now = Date()

    init(reader: UsageHistoryReader = UsageHistoryReader(), defaults: UserDefaults = .standard) {
        self.reader = reader
        self.defaults = defaults
        if let data = defaults.data(forKey: UsagePricing.defaultsKey) {
            if let saved = try? JSONDecoder().decode([String: ModelTokenPrice].self, from: data) {
                overrides = saved.filter { $0.value.isValid }
                prices.merge(overrides) { _, custom in custom }
            } else { pricingProblem = "Saved model prices could not be read. Reference prices are in use." }
        }
    }

    var allSelected: Bool { selectedAgents == Set(UsageAgent.allCases) }
    var selectionTitle: String {
        if allSelected { return "All agents" }
        if selectedAgents.isEmpty { return "No agents selected" }
        return UsageAgent.allCases.filter { selectedAgents.contains($0) }.map(\.title).joined(separator: " + ")
    }
    func toggle(_ agent: UsageAgent) {
        if selectedAgents.contains(agent) { selectedAgents.remove(agent) }
        else { selectedAgents.insert(agent) }
    }
    func selectAll() { selectedAgents = Set(UsageAgent.allCases) }
    func savePrice(model: String, price: ModelTokenPrice) {
        guard price.isValid else { return }
        overrides[model] = price
        persistPrices()
    }
    func resetPrice(model: String) {
        overrides.removeValue(forKey: model)
        persistPrices()
    }
    private func persistPrices() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: UsagePricing.defaultsKey)
        prices = UsagePricing.defaults.merging(overrides) { _, custom in custom }
        pricingProblem = nil
        recompute()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await reader.scan()
            try Task.checkCancellation()
            records = result.records
            sourceFiles = result.files
            sources = result.sources
            warnings = result.warnings
            now = Date()
            updatedAt = now
            loaded = true
            recompute()
        } catch is CancellationError { return }
        catch { warnings = ["Local history could not be refreshed. Previous readings are still shown."] }
    }

    private func recompute() {
        lifetime = UsageSummary(records: records.filter { $0.timestamp <= now }, prices: prices)
        recomputeFiltered()
    }

    private func recomputeFiltered() {
        let selected = records.filter { selectedAgents.contains($0.agent) && $0.timestamp <= now }
        let matching = selected.filter { period.contains($0.timestamp, now: now) }
        filtered = UsageSummary(records: matching, prices: prices)
        activity = UsageActivity(days: UsageSummary(records: selected).days, now: now)
        let domain = Set(records.map { grouping.key(for: $0) }).sorted()
        series = UsageSeries(records: matching, grouping: grouping, period: period,
                             now: now, prices: prices, domain: domain)
    }
}
