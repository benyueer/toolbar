import Combine
import Foundation

struct TokenBreakdown: Equatable, Sendable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var reasoning: Int64 = 0

    var total: Int64 {
        input + output + cacheRead + cacheWrite + reasoning
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            input: max(0, lhs.input - rhs.input),
            output: max(0, lhs.output - rhs.output),
            cacheRead: max(0, lhs.cacheRead - rhs.cacheRead),
            cacheWrite: max(0, lhs.cacheWrite - rhs.cacheWrite),
            reasoning: max(0, lhs.reasoning - rhs.reasoning)
        )
    }
}

struct ModelTokenUsage: Identifiable, Equatable, Sendable {
    let name: String
    let tokens: TokenBreakdown

    var id: String { name }
}

struct AgentTokenUsage: Identifiable, Equatable, Sendable {
    let agent: String
    let tokens: TokenBreakdown
    let models: [ModelTokenUsage]

    var id: String { agent }

    var displayName: String {
        switch agent.lowercased() {
        case "codex": "Codex"
        case "claude": "Claude Code"
        case "gemini": "Gemini CLI"
        case "antigravity": "Antigravity"
        case "opencode": "OpenCode"
        case "cursor": "Cursor"
        case "copilot": "GitHub Copilot"
        case "openclaw": "OpenClaw"
        case "droid": "Factory Droid"
        case "kiro": "Kiro"
        case "kimi": "Kimi"
        case "trae": "Trae"
        case "zed": "Zed"
        default: agent.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    var topModel: String? { models.first?.name }
}

struct DailyTokenUsage: Identifiable, Equatable, Sendable {
    let dateKey: String
    let tokens: TokenBreakdown
    let agents: [AgentTokenUsage]
    let estimatedCost: Double?

    var id: String { dateKey }
}

enum QuotaWindowStyle: Equatable, Sendable {
    case usage
    case resetCredit
}

struct QuotaWindowUsage: Identifiable, Equatable, Sendable {
    let label: String
    let usedPercent: Double
    let remainingLabel: String?
    let resetsAt: Date?
    let style: QuotaWindowStyle

    init(
        label: String,
        usedPercent: Double,
        remainingLabel: String? = nil,
        resetsAt: Date? = nil,
        style: QuotaWindowStyle = .usage
    ) {
        self.label = label
        self.usedPercent = usedPercent
        self.remainingLabel = remainingLabel
        self.resetsAt = resetsAt
        self.style = style
    }

    var id: String { label }
}

struct ProviderQuotaUsage: Identifiable, Equatable, Sendable {
    let id: String
    let provider: String
    let plan: String?
    let windows: [QuotaWindowUsage]

    var canonicalAgent: String {
        let key = provider.lowercased()
        if key.contains("codex") { return "codex" }
        if key.contains("claude") { return "claude" }
        if key.contains("antigravity") { return "antigravity" }
        if key.contains("gemini") { return "gemini" }
        if key.contains("opencode") { return "opencode" }
        if key.contains("cursor") { return "cursor" }
        if key.contains("copilot") { return "copilot" }
        return key.replacingOccurrences(of: " ", with: "-")
    }

    var displayName: String {
        guard let plan, !plan.isEmpty else { return provider }
        return "\(provider) \(plan)"
    }
}

struct TokenUsageSnapshot: Equatable, Sendable {
    enum Source: String, Sendable {
        case embeddedCollector
        case localLogs

        var label: String {
            switch self {
            case .embeddedCollector: "内置标准化统计"
            case .localLogs: "本地日志回退"
            }
        }
    }

    enum QuotaSource: String, Sendable {
        case embeddedTokenTracker

        var label: String { "内置 TokenTracker" }
    }

    var days: [DailyTokenUsage] = []
    var quotaProviders: [ProviderQuotaUsage] = []
    var quotaSource: QuotaSource?
    var source: Source = .localLogs
    var antigravitySynced = false
    var note: String?
    var generatedAt = Date()

    static let empty = TokenUsageSnapshot()

    var today: TokenBreakdown { totals(last: 1) }
    var todayEstimatedCost: Double? { selectedDays(last: 1).first?.estimatedCost }
    var last7Days: TokenBreakdown { totals(last: 7) }
    var last30Days: TokenBreakdown { totals(last: 30) }

    func totals(last count: Int) -> TokenBreakdown {
        selectedDays(last: count).reduce(into: TokenBreakdown()) { result, day in
            result = result + day.tokens
        }
    }

    func agents(last count: Int) -> [AgentTokenUsage] {
        var agentTotals: [String: TokenBreakdown] = [:]
        var modelTotals: [String: [String: TokenBreakdown]] = [:]

        for day in selectedDays(last: count) {
            for agent in day.agents {
                agentTotals[agent.agent, default: TokenBreakdown()] =
                    agentTotals[agent.agent, default: TokenBreakdown()] + agent.tokens
                for model in agent.models {
                    modelTotals[agent.agent, default: [:]][model.name, default: TokenBreakdown()] =
                        modelTotals[agent.agent, default: [:]][model.name, default: TokenBreakdown()] + model.tokens
                }
            }
        }

        return agentTotals.map { agent, tokens in
            let models = (modelTotals[agent] ?? [:])
                .map { ModelTokenUsage(name: $0.key, tokens: $0.value) }
                .sorted { $0.tokens.total > $1.tokens.total }
            return AgentTokenUsage(agent: agent, tokens: tokens, models: models)
        }
        .sorted { $0.tokens.total > $1.tokens.total }
    }

    private func selectedDays(last count: Int) -> ArraySlice<DailyTokenUsage> {
        days.suffix(max(0, count))
    }
}

@MainActor
final class TokenUsageMonitor: ObservableObject {
    @Published private(set) var snapshot = TokenUsageSnapshot.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let refreshInterval: TimeInterval = 3 * 60
    private let antigravitySyncInterval: TimeInterval = 10 * 60
    private let quotaRefreshInterval: TimeInterval = 10 * 60
    private var lastAntigravitySync: Date?
    private var lastQuotaRefresh: Date?
    private var timer: Timer?

    init() {
        refresh(forceAntigravitySync: true, forceQuotaRefresh: true)
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refresh(forceAntigravitySync: Bool = false, forceQuotaRefresh: Bool = false) {
        guard !isRefreshing else { return }

        let syncIsDue = lastAntigravitySync.map {
            Date().timeIntervalSince($0) >= antigravitySyncInterval
        } ?? true
        let shouldSync = forceAntigravitySync || syncIsDue
        let quotaIsDue = lastQuotaRefresh.map {
            Date().timeIntervalSince($0) >= quotaRefreshInterval
        } ?? true
        let shouldRefreshQuotas = forceQuotaRefresh || quotaIsDue
        let cachedQuotas = snapshot.quotaProviders
        let cachedQuotaSource = snapshot.quotaSource

        isRefreshing = true
        errorMessage = nil

        Task { [weak self] in
            let result: Result<TokenUsageSnapshot, Error>
            do {
                let nextSnapshot = try await Task.detached(priority: .userInitiated) {
                    try await TokenUsageCollector.collect(
                        syncAntigravity: shouldSync,
                        refreshQuotas: shouldRefreshQuotas,
                        forceQuotaProviderRefresh: forceQuotaRefresh,
                        cachedQuotas: cachedQuotas,
                        cachedQuotaSource: cachedQuotaSource
                    )
                }.value
                result = .success(nextSnapshot)
            } catch {
                result = .failure(error)
            }

            guard let self else { return }
            isRefreshing = false

            switch result {
            case .success(let nextSnapshot):
                snapshot = nextSnapshot
                if shouldSync, nextSnapshot.source == .embeddedCollector, nextSnapshot.antigravitySynced {
                    lastAntigravitySync = Date()
                }
                if shouldRefreshQuotas, nextSnapshot.quotaSource == .embeddedTokenTracker {
                    lastQuotaRefresh = Date()
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum TokenUsageCollector {
    private struct GraphPayload: Decodable {
        let contributions: [GraphContribution]
    }

    private struct GraphContribution: Decodable {
        let date: String
        let tokenBreakdown: GraphTokens
        let clients: [GraphClient]
        let totals: GraphTotals?
    }

    private struct GraphClient: Decodable {
        let client: String
        let modelId: String
        let tokens: GraphTokens
        let cost: Double?
    }

    private struct GraphTotals: Decodable {
        let cost: Double?
    }

    private struct GraphTokens: Decodable {
        let input: Int64
        let output: Int64
        let cacheRead: Int64
        let cacheWrite: Int64
        let reasoning: Int64

        var breakdown: TokenBreakdown {
            TokenBreakdown(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                reasoning: reasoning
            )
        }
    }

    private struct AntigravityStatus: Decodable {
        let cacheExists: Bool
        let sessionsDirExists: Bool
        let manifestExists: Bool
        let detectedConnections: Int
        let lastSyncedAt: String?
    }

    private struct AntigravitySyncOutcome {
        let synced: Bool
        let note: String?
    }

    private struct DayAccumulator {
        var tokens = TokenBreakdown()
        var agents: [String: TokenBreakdown] = [:]
        var models: [String: [String: TokenBreakdown]] = [:]
        var estimatedCost: Double?
    }

    private static let usageCollectorStorageLock = NSLock()

    private enum CollectorError: LocalizedError {
        case invalidCollectorOutput
        case processFailed(String)
        case processTimeout(String)

        var errorDescription: String? {
            switch self {
            case .invalidCollectorOutput: "无法解析内置统计引擎的结果"
            case .processFailed(let command): "Token 统计命令执行失败：\(command)"
            case .processTimeout(let command): "Token 统计命令执行超时：\(command)"
            }
        }
    }

    /// 线程安全的可执行文件路径定位与缓存器（带有 TTL 保护，避免频繁启动 Shell）
    private final class ExecutableLocator: @unchecked Sendable {
        static let shared = ExecutableLocator()
        private let lock = NSLock()
        private var cache: [String: (url: URL?, timestamp: Date)] = [:]
        private let ttl: TimeInterval = 300 // 缓存 5 分钟

        func locate(_ name: String, candidates: [String], shellCommand: String) -> URL? {
            lock.lock()
            if let cached = cache[name], Date().timeIntervalSince(cached.timestamp) < ttl {
                let url = cached.url
                lock.unlock()
                return url
            }
            lock.unlock()

            var foundURL: URL?
            for candidate in candidates {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    foundURL = URL(fileURLWithPath: candidate)
                    break
                }
            }

            if foundURL == nil {
                if let output = try? TokenUsageCollector.run(
                    URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-lic", shellCommand],
                    timeout: 3
                ), let path = String(data: output, encoding: .utf8)?
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map(String.init),
                    FileManager.default.isExecutableFile(atPath: path) {
                    foundURL = URL(fileURLWithPath: path)
                }
            }

            lock.lock()
            cache[name] = (foundURL, Date())
            lock.unlock()
            return foundURL
        }
    }

    static func collect(
        syncAntigravity: Bool,
        refreshQuotas: Bool = true,
        forceQuotaProviderRefresh: Bool = false,
        cachedQuotas: [ProviderQuotaUsage] = [],
        cachedQuotaSource: TokenUsageSnapshot.QuotaSource? = nil
    ) async throws -> TokenUsageSnapshot {
        // 并行任务 1：从内置统计引擎 / 本地日志拉取 Token 使用量与同步记录
        async let snapshotTask = Task.detached(priority: .userInitiated) { () -> TokenUsageSnapshot in
            var snapshot: TokenUsageSnapshot
            if let executable = locateEmbeddedUsageCollector() {
                do {
                    let antigravitySync = syncAntigravity
                        ? synchronizeAntigravity(using: executable)
                        : AntigravitySyncOutcome(synced: false, note: nil)

                    let start = dayKey(for: Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date())
                    let data = try run(
                        executable,
                        arguments: ["graph", "--since", start, "--no-spinner"],
                        timeout: 15
                    )
                    snapshot = try parseUsageGraph(data)
                    snapshot.source = .embeddedCollector
                    snapshot.antigravitySynced = antigravitySync.synced
                    snapshot.note = antigravitySync.note

                    let localSnapshot = collectLocalAntigravity()
                    mergeAntigravityDataIfNeeded(into: &snapshot, from: localSnapshot)
                } catch {
                    snapshot = collectLocalLogs()
                    snapshot.note = "内置统计引擎暂时不可用，已改用本地日志统计"
                }
            } else {
                snapshot = collectLocalLogs()
                snapshot.note = "未找到内置统计引擎，已改用本地日志统计"
            }
            return snapshot
        }.value

        // 并行任务 2：从 TokenTracker 后端异步拉取实时额度
        async let quotasTask = Task.detached(priority: .userInitiated) { () -> ([ProviderQuotaUsage]?, TokenUsageSnapshot.QuotaSource?) in
            guard refreshQuotas else {
                return (cachedQuotas, cachedQuotaSource)
            }
            if let limitsData = try? fetchEmbeddedTokenTrackerLimits(forceRefresh: forceQuotaProviderRefresh),
               let quotas = try? parseEmbeddedTokenTrackerLimits(limitsData),
               !quotas.isEmpty {
                return (quotas, .embeddedTokenTracker)
            } else {
                return (nil, nil)
            }
        }.value

        var finalSnapshot = await snapshotTask
        let (fetchedQuotas, fetchedSource) = await quotasTask

        if let fetchedQuotas, !fetchedQuotas.isEmpty, let fetchedSource {
            finalSnapshot.quotaProviders = fetchedQuotas
            finalSnapshot.quotaSource = fetchedSource
        } else if refreshQuotas {
            finalSnapshot.quotaProviders = cachedQuotas
            finalSnapshot.quotaSource = cachedQuotaSource
            let quotaNote = cachedQuotas.isEmpty
                ? "内置 TokenTracker 额度采集器暂时不可用"
                : "内置 TokenTracker 额度暂时无法刷新，继续显示上次结果"
            finalSnapshot.note = [finalSnapshot.note, quotaNote].compactMap { $0 }.joined(separator: "；")
        } else {
            finalSnapshot.quotaProviders = cachedQuotas
            finalSnapshot.quotaSource = cachedQuotaSource
        }

        return finalSnapshot
    }

    /// 确保在内置聚合结果与本地 Antigravity 缓存之间取并集，防止任何新导出的 Token 遗漏
    private static func mergeAntigravityDataIfNeeded(
        into snapshot: inout TokenUsageSnapshot,
        from localSnapshot: TokenUsageSnapshot
    ) {
        var daysMap = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.dateKey, $0) })

        for localDay in localSnapshot.days {
            guard let localAntigravity = localDay.agents.first(where: { $0.agent == "antigravity" }),
                  localAntigravity.tokens.total > 0
            else { continue }

            let key = localDay.dateKey
            var dayUsage = daysMap[key] ?? DailyTokenUsage(
                dateKey: key,
                tokens: TokenBreakdown(),
                agents: [],
                estimatedCost: nil
            )
            var agents = dayUsage.agents

            if let index = agents.firstIndex(where: { $0.agent == "antigravity" }) {
                // 若本地解析出的 Antigravity Token 数量大于现有的，则取大值补全
                if localAntigravity.tokens.total > agents[index].tokens.total {
                    let diff = localAntigravity.tokens - agents[index].tokens
                    agents[index] = localAntigravity
                    dayUsage = DailyTokenUsage(
                        dateKey: key,
                        tokens: dayUsage.tokens + diff,
                        agents: agents.sorted { $0.tokens.total > $1.tokens.total },
                        estimatedCost: dayUsage.estimatedCost
                    )
                }
            } else {
                // 若原有结果中没有 Antigravity，直接追加合并
                agents.append(localAntigravity)
                dayUsage = DailyTokenUsage(
                    dateKey: key,
                    tokens: dayUsage.tokens + localAntigravity.tokens,
                    agents: agents.sorted { $0.tokens.total > $1.tokens.total },
                    estimatedCost: dayUsage.estimatedCost
                )
            }
            daysMap[key] = dayUsage
        }

        let sortedKeys = daysMap.keys.sorted()
        snapshot.days = sortedKeys.compactMap { daysMap[$0] }
    }

    static func parseUsageGraph(_ data: Data) throws -> TokenUsageSnapshot {
        guard let graph = try? JSONDecoder().decode(GraphPayload.self, from: data) else {
            throw CollectorError.invalidCollectorOutput
        }

        var accumulators: [String: DayAccumulator] = [:]
        for contribution in graph.contributions {
            var day = DayAccumulator()
            day.tokens = contribution.tokenBreakdown.breakdown
            let clientCosts = contribution.clients.compactMap(\.cost)
            day.estimatedCost = contribution.totals?.cost
                ?? (clientCosts.isEmpty ? nil : clientCosts.reduce(0, +))

            for item in contribution.clients where item.tokens.breakdown.total > 0 {
                let client = item.client.lowercased()
                let breakdown = item.tokens.breakdown
                day.agents[client, default: TokenBreakdown()] =
                    day.agents[client, default: TokenBreakdown()] + breakdown
                day.models[client, default: [:]][item.modelId, default: TokenBreakdown()] =
                    day.models[client, default: [:]][item.modelId, default: TokenBreakdown()] + breakdown
            }
            accumulators[contribution.date] = day
        }

        return makeSnapshot(from: accumulators, source: .embeddedCollector)
    }

    static func parseEmbeddedTokenTrackerLimits(_ data: Data) throws -> [ProviderQuotaUsage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.invalidCollectorOutput
        }

        func object(_ value: Any?) -> [String: Any]? {
            value as? [String: Any]
        }

        func number(_ value: Any?) -> Double? {
            if let value = value as? NSNumber { return value.doubleValue }
            if let value = value as? String { return Double(value) }
            return nil
        }

        func plan(_ provider: [String: Any]) -> String? {
            (provider["plan_label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func isUsable(_ provider: [String: Any]) -> Bool {
            provider["configured"] as? Bool == true && provider["error"] as? String == nil
        }

        func isoWindow(_ provider: [String: Any], key: String, label: String) -> QuotaWindowUsage? {
            guard let window = object(provider[key]), let percent = number(window["used_percent"]) else {
                return nil
            }
            return QuotaWindowUsage(
                label: label,
                usedPercent: min(max(percent, 0), 100),
                resetsAt: (window["reset_at"] as? String).flatMap(parseISODate)
            )
        }

        func claudeWindow(_ provider: [String: Any], key: String, label: String) -> QuotaWindowUsage? {
            guard let window = object(provider[key]), let percent = number(window["utilization"]) else {
                return nil
            }
            return QuotaWindowUsage(
                label: label,
                usedPercent: min(max(percent, 0), 100),
                resetsAt: (window["resets_at"] as? String).flatMap(parseISODate)
            )
        }

        func codexWindow(_ provider: [String: Any], key: String, label: String) -> QuotaWindowUsage? {
            guard let window = object(provider[key]), let percent = number(window["used_percent"]) else {
                return nil
            }
            let reset = number(window["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            return QuotaWindowUsage(
                label: label,
                usedPercent: min(max(percent, 0), 100),
                resetsAt: reset
            )
        }

        var providers: [ProviderQuotaUsage] = []

        func appendProvider(key: String, title: String, windows: [QuotaWindowUsage]) {
            guard let provider = object(root[key]), isUsable(provider), !windows.isEmpty else { return }
            providers.append(
                ProviderQuotaUsage(
                    id: key,
                    provider: title,
                    plan: plan(provider),
                    windows: windows
                )
            )
        }

        if let claude = object(root["claude"]), isUsable(claude) {
            var windows = [
                claudeWindow(claude, key: "five_hour", label: "5h"),
                claudeWindow(claude, key: "seven_day", label: "7d"),
                claudeWindow(claude, key: "seven_day_opus", label: "Opus"),
            ].compactMap { $0 }
            for scoped in claude["weekly_scoped"] as? [[String: Any]] ?? [] {
                guard let label = scoped["label"] as? String,
                      let percent = number(scoped["utilization"]) else { continue }
                windows.append(
                    QuotaWindowUsage(
                        label: label,
                        usedPercent: min(max(percent, 0), 100),
                        resetsAt: (scoped["resets_at"] as? String).flatMap(parseISODate)
                    )
                )
            }
            appendProvider(key: "claude", title: "Claude", windows: windows)
        }

        if let codex = object(root["codex"]), isUsable(codex) {
            var windows = [
                codexWindow(codex, key: "primary_window", label: "5h"),
                codexWindow(codex, key: "secondary_window", label: "7d"),
                codexWindow(codex, key: "credit_window", label: "Credits"),
                codexWindow(codex, key: "spark_primary_window", label: "Spark 5h"),
                codexWindow(codex, key: "spark_secondary_window", label: "Spark 7d"),
            ].compactMap { $0 }

            if let resetCredits = object(codex["reset_credits"]) {
                var displayIndex = 0
                for credit in resetCredits["credits"] as? [[String: Any]] ?? [] {
                    guard credit["status"] as? String == "available",
                          let expiresText = credit["expires_at"] as? String,
                          let expiresAt = parseISODate(expiresText) else { continue }
                    displayIndex += 1
                    let grantedAt = (credit["granted_at"] as? String).flatMap(parseISODate)
                    let lifetimePercent: Double
                    if let grantedAt, expiresAt > grantedAt {
                        lifetimePercent = min(
                            100,
                            max(0, expiresAt.timeIntervalSinceNow / expiresAt.timeIntervalSince(grantedAt) * 100)
                        )
                    } else {
                        lifetimePercent = 100
                    }
                    windows.append(
                        QuotaWindowUsage(
                            label: "重置 \(displayIndex)",
                            usedPercent: lifetimePercent,
                            resetsAt: expiresAt,
                            style: .resetCredit
                        )
                    )
                }
            }
            appendProvider(key: "codex", title: "Codex", windows: windows)
        }

        func genericProvider(key: String, title: String, specs: [(String, String)]) {
            guard let provider = object(root[key]), isUsable(provider) else { return }
            let windows = specs.compactMap { field, label in
                isoWindow(provider, key: field, label: label)
            }
            appendProvider(key: key, title: title, windows: windows)
        }

        genericProvider(
            key: "cursor",
            title: "Cursor",
            specs: [("primary_window", "Plan"), ("secondary_window", "Auto"), ("tertiary_window", "API")]
        )
        genericProvider(
            key: "gemini",
            title: "Gemini",
            specs: [("primary_window", "Pro"), ("secondary_window", "Flash"), ("tertiary_window", "Lite")]
        )
        genericProvider(
            key: "kimi",
            title: "Kimi",
            specs: [("primary_window", "Weekly"), ("secondary_window", "5h"), ("tertiary_window", "Total")]
        )
        genericProvider(
            key: "kiro",
            title: "Kiro",
            specs: [("primary_window", "Monthly"), ("secondary_window", "Bonus")]
        )

        if let grok = object(root["grok"]), isUsable(grok) {
            let period = (grok["period_type"] as? String)?.lowercased()
            let periodLabel = period == "daily" ? "Daily" : (period == "monthly" ? "Monthly" : "Weekly")
            appendProvider(
                key: "grok",
                title: "Grok",
                windows: [
                    isoWindow(grok, key: "primary_window", label: periodLabel),
                    isoWindow(grok, key: "secondary_window", label: "On-demand"),
                ].compactMap { $0 }
            )
        }

        genericProvider(
            key: "copilot",
            title: "GitHub Copilot",
            specs: [("primary_window", "Premium"), ("secondary_window", "Chat")]
        )

        if let zcode = object(root["zcode"]), isUsable(zcode) {
            let specs = zcode["plan_kind"] as? String == "coding-plan"
                ? [("primary_window", "5h"), ("secondary_window", "Weekly"), ("tertiary_window", "Tools")]
                : [("primary_window", "GLM-5.2"), ("secondary_window", "GLM-5-Turbo")]
            appendProvider(
                key: "zcode",
                title: "Z Code",
                windows: specs.compactMap { field, label in isoWindow(zcode, key: field, label: label) }
            )
        }

        genericProvider(
            key: "antigravity",
            title: "Antigravity",
            specs: [
                ("primary_window", "Cl 7d"),
                ("secondary_window", "Cl 5h"),
                ("tertiary_window", "Gm 7d"),
                ("quaternary_window", "Gm 5h"),
            ]
        )
        genericProvider(
            key: "opencodeGo",
            title: "OpenCode Go",
            specs: [("primary_window", "5h"), ("secondary_window", "Weekly"), ("tertiary_window", "Monthly")]
        )

        return applyQuotaProviderPreferences(to: providers)
    }

    private static func applyQuotaProviderPreferences(
        to providers: [ProviderQuotaUsage]
    ) -> [ProviderQuotaUsage] {
        let defaults = UserDefaults.standard
        let visibility = defaults.dictionary(forKey: "QuotaProviderVisibility")
        let defaultVisible: Set<String> = ["codex", "antigravity", "opencodeGo"]
        let visible = providers.filter { provider in
            if let visibility {
                return (visibility[provider.id] as? Bool) ?? true
            }
            return defaultVisible.contains(provider.id)
        }
        let order = defaults.stringArray(forKey: "QuotaProviderOrder")
            ?? ["codex", "antigravity", "opencodeGo"]
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return visible.sorted {
            (positions[$0.id] ?? Int.max) < (positions[$1.id] ?? Int.max)
        }
    }

    private static func fetchEmbeddedTokenTrackerLimits(forceRefresh: Bool) throws -> Data {
        guard let runner = locateTokenTrackerQuotaRunner(), let node = locateNode() else {
            throw CollectorError.processFailed("内置 TokenTracker")
        }
        var arguments = [runner.path]
        if forceRefresh { arguments.append("--refresh") }
        return try run(node, arguments: arguments)
    }

    private static func locateTokenTrackerQuotaRunner() -> URL? {
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("TokenTrackerBackend/quota-runner.js"),
            sourceDirectory.appendingPathComponent("Resources/TokenTrackerBackend/quota-runner.js"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func locateNode() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            home.appendingPathComponent(".volta/bin/node").path,
            home.appendingPathComponent(".bun/bin/node").path,
        ]
        return ExecutableLocator.shared.locate("node", candidates: candidates, shellCommand: "command -v node")
    }

    private static func collectLocalLogs() -> TokenUsageSnapshot {
        var accumulators: [String: DayAccumulator] = [:]
        let earliestDate = Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date()
        let home = FileManager.default.homeDirectoryForCurrentUser

        parseCodex(
            root: home.appendingPathComponent(".codex/sessions"),
            earliestDate: earliestDate,
            into: &accumulators
        )
        parseCodex(
            root: home.appendingPathComponent(".codex/archived_sessions"),
            earliestDate: earliestDate,
            into: &accumulators
        )
        parseClaude(
            root: home.appendingPathComponent(".claude/projects"),
            earliestDate: earliestDate,
            into: &accumulators
        )
        parseClaude(
            root: home.appendingPathComponent(".claude/transcripts"),
            earliestDate: earliestDate,
            into: &accumulators
        )
        parseGemini(
            root: home.appendingPathComponent(".gemini/tmp"),
            earliestDate: earliestDate,
            into: &accumulators
        )

        parseAntigravityCache(
            root: prepareUsageCollectorStorage().appendingPathComponent("antigravity-cache/sessions"),
            earliestDate: earliestDate,
            into: &accumulators
        )

        return makeSnapshot(from: accumulators, source: .localLogs)
    }

    private static func collectLocalAntigravity() -> TokenUsageSnapshot {
        var accumulators: [String: DayAccumulator] = [:]
        let earliestDate = Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date()
        let collectorConfig = prepareUsageCollectorStorage()
        parseAntigravityCache(
            root: collectorConfig.appendingPathComponent("antigravity-cache/sessions"),
            earliestDate: earliestDate,
            into: &accumulators
        )

        return makeSnapshot(from: accumulators, source: .localLogs)
    }

    private static func parseCodex(
        root: URL,
        earliestDate: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        var seenEvents = Set<String>()
        for file in recentFiles(at: root, extension: "jsonl", since: earliestDate) {
            guard let lines = try? String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline) else {
                continue
            }

            var previousTotal: TokenBreakdown?
            var model = "unknown"
            var sessionID = file.deletingPathExtension().lastPathComponent

            for line in lines {
                guard
                    let data = String(line).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                let type = object["type"] as? String
                let payload = object["payload"] as? [String: Any]

                if type == "session_meta", let value = payload?["id"] as? String {
                    sessionID = value
                }
                if type == "turn_context", let value = payload?["model"] as? String {
                    model = value
                }

                guard type == "event_msg" else { continue }
                let directType = payload?["type"] as? String
                let nested = payload?["msg"] as? [String: Any]
                guard directType == "token_count" || nested?["type"] as? String == "token_count" else {
                    continue
                }

                let info = (directType == "token_count" ? payload?["info"] : nested?["info"]) as? [String: Any]
                let last = breakdown(fromCodexUsage: info?["last_token_usage"] as? [String: Any])
                let total = breakdown(fromCodexUsage: info?["total_token_usage"] as? [String: Any])
                let delta: TokenBreakdown?

                if let total, let previousTotal {
                    delta = total.total < previousTotal.total ? (last ?? total) : total - previousTotal
                } else {
                    delta = last ?? total
                }
                if let total { previousTotal = total }

                guard
                    let delta,
                    delta.total > 0,
                    let timestamp = object["timestamp"] as? String,
                    let date = parseISODate(timestamp),
                    date >= earliestDate
                else { continue }

                let eventKey = "\(sessionID):\(timestamp):\(total?.total ?? delta.total)"
                guard seenEvents.insert(eventKey).inserted else { continue }
                record(delta, agent: "codex", model: model, date: date, into: &accumulators)
            }
        }
    }

    private static func parseClaude(
        root: URL,
        earliestDate: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        var seenMessages = Set<String>()
        for file in recentFiles(at: root, extension: "jsonl", since: earliestDate) {
            guard let lines = try? String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline) else {
                continue
            }

            for line in lines where line.contains("\"usage\"") {
                guard
                    let data = String(line).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let message = object["message"] as? [String: Any],
                    let usage = (message["usage"] ?? object["usage"]) as? [String: Any],
                    let timestamp = object["timestamp"] as? String,
                    let date = parseISODate(timestamp),
                    date >= earliestDate
                else { continue }

                if let messageID = message["id"] as? String {
                    let requestID = object["requestId"] as? String
                    let key = requestID.map { "\(messageID):\($0)" } ?? messageID
                    guard seenMessages.insert(key).inserted else { continue }
                }

                let tokens = TokenBreakdown(
                    input: number(usage["input_tokens"]),
                    output: number(usage["output_tokens"]),
                    cacheRead: number(usage["cache_read_input_tokens"]),
                    cacheWrite: number(usage["cache_creation_input_tokens"])
                )
                guard tokens.total > 0 else { continue }
                let model = (message["model"] as? String) ?? (object["model"] as? String) ?? "unknown"
                record(tokens, agent: "claude", model: model, date: date, into: &accumulators)
            }
        }
    }

    private static func parseGemini(
        root: URL,
        earliestDate: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        for file in recentFiles(at: root, extension: "json", since: earliestDate) {
            guard
                let data = try? Data(contentsOf: file),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let messages = object["messages"] as? [[String: Any]]
            else { continue }

            var previous: TokenBreakdown?
            var previousReportedTotal: Int64 = 0

            for message in messages {
                guard let rawTokens = message["tokens"] as? [String: Any] else { continue }
                let current = TokenBreakdown(
                    input: number(rawTokens["input"]),
                    output: number(rawTokens["output"]) + number(rawTokens["tool"]),
                    cacheRead: number(rawTokens["cached"]),
                    reasoning: number(rawTokens["thoughts"])
                )
                let reportedTotal = max(number(rawTokens["total"]), current.total)
                let delta = (reportedTotal < previousReportedTotal || previous == nil)
                    ? current
                    : current - (previous ?? TokenBreakdown())
                previous = current
                previousReportedTotal = reportedTotal

                guard
                    delta.total > 0,
                    let timestamp = message["timestamp"] as? String,
                    let date = parseISODate(timestamp),
                    date >= earliestDate
                else { continue }

                let model = (message["model"] as? String) ?? "unknown"
                record(delta, agent: "gemini", model: model, date: date, into: &accumulators)
            }
        }
    }

    private static func parseAntigravityCache(
        root: URL,
        earliestDate: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        var seenResponses = Set<String>()
        for file in recentFiles(at: root, extension: "jsonl", since: earliestDate) {
            guard let lines = try? String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline) else {
                continue
            }

            var fallbackModel = "unknown"
            for line in lines {
                guard
                    let data = String(line).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                if object["type"] as? String == "session_meta" {
                    fallbackModel = (object["modelId"] as? String) ?? fallbackModel
                    continue
                }
                guard object["type"] as? String == "usage" else { continue }

                if let responseID = object["responseId"] as? String,
                   !seenResponses.insert(responseID).inserted {
                    continue
                }

                let timestamp = number(object["timestamp"])
                guard timestamp > 0 else { continue }
                let date = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
                guard date >= earliestDate else { continue }

                let tokens = TokenBreakdown(
                    input: number(object["input"]),
                    output: number(object["output"]),
                    cacheRead: number(object["cacheRead"]),
                    cacheWrite: number(object["cacheWrite"]),
                    reasoning: number(object["reasoning"])
                )
                guard tokens.total > 0 else { continue }
                let model = (object["modelId"] as? String) ?? fallbackModel
                record(tokens, agent: "antigravity", model: model, date: date, into: &accumulators)
            }
        }
    }

    private static func breakdown(fromCodexUsage usage: [String: Any]?) -> TokenBreakdown? {
        guard let usage else { return nil }
        let cacheRead = number(usage["cached_input_tokens"])
        return TokenBreakdown(
            input: max(0, number(usage["input_tokens"]) - cacheRead),
            output: number(usage["output_tokens"]),
            cacheRead: cacheRead,
            cacheWrite: number(usage["cache_creation_input_tokens"]),
            reasoning: number(usage["reasoning_output_tokens"])
        )
    }

    private static func record(
        _ tokens: TokenBreakdown,
        agent: String,
        model: String,
        date: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        let key = dayKey(for: date)
        var day = accumulators[key, default: DayAccumulator()]
        day.tokens = day.tokens + tokens
        day.agents[agent, default: TokenBreakdown()] = day.agents[agent, default: TokenBreakdown()] + tokens
        day.models[agent, default: [:]][model, default: TokenBreakdown()] =
            day.models[agent, default: [:]][model, default: TokenBreakdown()] + tokens
        accumulators[key] = day
    }

    private static func makeSnapshot(
        from accumulators: [String: DayAccumulator],
        source: TokenUsageSnapshot.Source
    ) -> TokenUsageSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [DailyTokenUsage] = []

        for offset in (-29)...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = dayKey(for: date)
            let value = accumulators[key] ?? DayAccumulator()
            let agents = value.agents.map { agent, tokens in
                let models = (value.models[agent] ?? [:])
                    .map { ModelTokenUsage(name: $0.key, tokens: $0.value) }
                    .sorted { $0.tokens.total > $1.tokens.total }
                return AgentTokenUsage(agent: agent, tokens: tokens, models: models)
            }
            .sorted { $0.tokens.total > $1.tokens.total }
            days.append(
                DailyTokenUsage(
                    dateKey: key,
                    tokens: value.tokens,
                    agents: agents,
                    estimatedCost: value.estimatedCost
                )
            )
        }

        return TokenUsageSnapshot(days: days, source: source, generatedAt: Date())
    }

    private static func recentFiles(
        at root: URL,
        extension fileExtension: String,
        since date: Date,
        maxSizeBytes: Int64 = 10 * 1024 * 1024
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == fileExtension {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            // 过滤非普通文件、修改时间过早的文件以及超过大小限制（默认 10MB）的大日志
            guard values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= date,
                  Int64(values.fileSize ?? 0) <= maxSizeBytes
            else {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func locateEmbeddedUsageCollector() -> URL? {
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("UsageCollectorBackend/usage-collector"),
            sourceDirectory.appendingPathComponent("Resources/UsageCollectorBackend/usage-collector"),
        ].compactMap { $0 }
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func usageCollectorConfigDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("ToolbarMonitor", isDirectory: true)
            .appendingPathComponent("UsageCollector", isDirectory: true)
    }

    /// 首次升级时只复制仍有价值的本地缓存，后续全部写入 ToolbarMonitor 自己的目录。
    private static func prepareUsageCollectorStorage() -> URL {
        usageCollectorStorageLock.lock()
        defer { usageCollectorStorageLock.unlock() }

        let fileManager = FileManager.default
        let destinationRoot = usageCollectorConfigDirectory()
        try? fileManager.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: true
        )

        let legacyRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tokscale", isDirectory: true)
        for directoryName in ["antigravity-cache", "cursor-cache", "trae-cache"] {
            let source = legacyRoot.appendingPathComponent(directoryName, isDirectory: true)
            let destination = destinationRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path)
            else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }

        return destinationRoot
    }

    @discardableResult
    private static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 15) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["NODE_USE_ENV_PROXY"] = "1"
        if executable.lastPathComponent == "usage-collector" {
            environment["TOKSCALE_CONFIG_DIR"] = prepareUsageCollectorStorage().path
            environment["TOKSCALE_NATIVE_TIMEOUT_MS"] = "45000"
        }
        process.environment = environment

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWorkItem.cancel()

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal {
                throw CollectorError.processTimeout(executable.lastPathComponent)
            }
            throw CollectorError.processFailed(executable.lastPathComponent)
        }
        return data
    }

    private static func number(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        if let text = value as? String, let number = Int64(text) { return max(0, number) }
        return 0
    }

    private static func synchronizeAntigravity(using executable: URL) -> AntigravitySyncOutcome {
        var latestStatus = try? readAntigravityStatus(using: executable)
        var expectedConnections = latestStatus?.detectedConnections ?? 0
        var synchronizedConnections = 0
        var completedSync = false

        // Antigravity 的全局与工作区 language server 可能分两轮才被发现。
        // 每轮 sync 后重新读取 status；仅当 status 看到了尚未同步的连接时再补一次。
        for attempt in 1...2 {
            do {
                let output = try run(
                    executable,
                    arguments: ["antigravity", "sync"],
                    timeout: 30
                )
                completedSync = true
                synchronizedConnections = max(
                    synchronizedConnections,
                    antigravityConnectionCount(in: output) ?? 0
                )
            } catch {
                if attempt == 2 {
                    break
                }
                continue
            }

            if let status = try? readAntigravityStatus(using: executable) {
                latestStatus = status
                expectedConnections = max(expectedConnections, status.detectedConnections)
            }

            if synchronizedConnections >= expectedConnections {
                break
            }
        }

        guard completedSync else {
            return AntigravitySyncOutcome(
                synced: false,
                note: "反重力同步失败，稍后将自动重试"
            )
        }

        let visibleConnections = max(expectedConnections, latestStatus?.detectedConnections ?? 0)
        guard visibleConnections > 0 else {
            return AntigravitySyncOutcome(
                synced: false,
                note: "未检测到反重力语言服务，稍后将自动重试"
            )
        }

        guard synchronizedConnections >= visibleConnections else {
            return AntigravitySyncOutcome(
                synced: false,
                note: "反重力仅同步 \(synchronizedConnections)/\(visibleConnections) 个语言服务，稍后将自动重试"
            )
        }

        if let status = latestStatus,
           !status.cacheExists || !status.sessionsDirExists || !status.manifestExists || status.lastSyncedAt == nil {
            return AntigravitySyncOutcome(
                synced: false,
                note: "反重力缓存状态异常，稍后将自动重试"
            )
        }

        return AntigravitySyncOutcome(synced: true, note: nil)
    }

    private static func readAntigravityStatus(using executable: URL) throws -> AntigravityStatus {
        let data = try run(
            executable,
            arguments: ["antigravity", "status", "--json"],
            timeout: 15
        )
        return try JSONDecoder().decode(AntigravityStatus.self, from: data)
    }

    private static func antigravityConnectionCount(in output: Data) -> Int? {
        guard let text = String(data: output, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard
                parts.count == 2,
                parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "detected connections"
            else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

}

extension Int64 {
    var tokenText: String {
        let value = Double(Swift.max(0, self))
        switch value {
        case 1_000_000_000...:
            return String(format: value >= 10_000_000_000 ? "%.0fB" : "%.1fB", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: value >= 100_000_000 ? "%.0fM" : "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: value >= 100_000 ? "%.0fK" : "%.1fK", value / 1_000)
        default:
            return "\(self)"
        }
    }
}

extension Double {
    var estimatedCostText: String {
        let value = Swift.max(0, self)
        return String(format: value > 0 && value < 0.01 ? "$%.3f" : "$%.2f", value)
    }
}
