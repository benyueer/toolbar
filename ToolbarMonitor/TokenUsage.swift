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
        case tokscale
        case localLogs

        var label: String {
            switch self {
            case .tokscale: "tokscale 标准化统计"
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
            let result = await Task.detached(priority: .utility) {
                Result {
                    try TokenUsageCollector.collect(
                        syncAntigravity: shouldSync,
                        refreshQuotas: shouldRefreshQuotas,
                        forceQuotaProviderRefresh: forceQuotaRefresh,
                        cachedQuotas: cachedQuotas,
                        cachedQuotaSource: cachedQuotaSource
                    )
                }
            }.value

            guard let self else { return }
            isRefreshing = false

            switch result {
            case .success(let nextSnapshot):
                snapshot = nextSnapshot
                if shouldSync, nextSnapshot.source == .tokscale {
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
    }

    private struct GraphClient: Decodable {
        let client: String
        let modelId: String
        let tokens: GraphTokens
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

    private struct DayAccumulator {
        var tokens = TokenBreakdown()
        var agents: [String: TokenBreakdown] = [:]
        var models: [String: [String: TokenBreakdown]] = [:]
    }

    private enum CollectorError: LocalizedError {
        case invalidTokscaleOutput
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidTokscaleOutput: "无法解析 tokscale 的统计结果"
            case .processFailed(let command): "Token 统计命令执行失败：\(command)"
            }
        }
    }

    static func collect(
        syncAntigravity: Bool,
        refreshQuotas: Bool = true,
        forceQuotaProviderRefresh: Bool = false,
        cachedQuotas: [ProviderQuotaUsage] = [],
        cachedQuotaSource: TokenUsageSnapshot.QuotaSource? = nil
    ) throws -> TokenUsageSnapshot {
        var snapshot: TokenUsageSnapshot

        if let executable = locateTokscale() {
            do {
                var antigravitySynced = false
                if syncAntigravity {
                    if let syncOutput = try? run(executable, arguments: ["antigravity", "sync"]) {
                        antigravitySynced = detectedAntigravityConnection(in: syncOutput)
                    }
                }

                let start = dayKey(for: Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date())
                let data = try run(
                    executable,
                    arguments: ["graph", "--since", start, "--no-spinner"]
                )
                snapshot = try parseTokscaleGraph(data)
                snapshot.source = .tokscale
                snapshot.antigravitySynced = antigravitySynced
            } catch {
                snapshot = collectLocalLogs()
                snapshot.note = "tokscale 暂时不可用，已改用本地日志统计"
            }
        } else {
            snapshot = collectLocalLogs()
        }

        if refreshQuotas {
            if let limitsData = try? fetchEmbeddedTokenTrackerLimits(forceRefresh: forceQuotaProviderRefresh),
               let quotas = try? parseEmbeddedTokenTrackerLimits(limitsData),
               !quotas.isEmpty {
                snapshot.quotaProviders = quotas
                snapshot.quotaSource = .embeddedTokenTracker
            } else {
                snapshot.quotaProviders = cachedQuotas
                snapshot.quotaSource = cachedQuotaSource
                let quotaNote = cachedQuotas.isEmpty
                    ? "内置 TokenTracker 额度采集器暂时不可用"
                    : "内置 TokenTracker 额度暂时无法刷新，继续显示上次结果"
                snapshot.note = [snapshot.note, quotaNote].compactMap { $0 }.joined(separator: "；")
            }
        } else {
            snapshot.quotaProviders = cachedQuotas
            snapshot.quotaSource = cachedQuotaSource
        }

        return snapshot
    }

    static func parseTokscaleGraph(_ data: Data) throws -> TokenUsageSnapshot {
        guard let graph = try? JSONDecoder().decode(GraphPayload.self, from: data) else {
            throw CollectorError.invalidTokscaleOutput
        }

        var accumulators: [String: DayAccumulator] = [:]
        for contribution in graph.contributions {
            var day = DayAccumulator()
            day.tokens = contribution.tokenBreakdown.breakdown

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

        return makeSnapshot(from: accumulators, source: .tokscale)
    }

    static func parseEmbeddedTokenTrackerLimits(_ data: Data) throws -> [ProviderQuotaUsage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.invalidTokscaleOutput
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
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        guard let output = try? run(
            URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lic", "command -v node"]
        ), let path = String(data: output, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init),
            FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
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
            root: home.appendingPathComponent(".config/tokscale/antigravity-cache/sessions"),
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
            let value = accumulators[key, default: DayAccumulator()]
            let agents = value.agents.map { agent, tokens in
                let models = (value.models[agent] ?? [:])
                    .map { ModelTokenUsage(name: $0.key, tokens: $0.value) }
                    .sorted { $0.tokens.total > $1.tokens.total }
                return AgentTokenUsage(agent: agent, tokens: tokens, models: models)
            }
            .sorted { $0.tokens.total > $1.tokens.total }
            days.append(DailyTokenUsage(dateKey: key, tokens: value.tokens, agents: agents))
        }

        return TokenUsageSnapshot(days: days, source: source, generatedAt: Date())
    }

    private static func recentFiles(at root: URL, extension fileExtension: String, since date: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == fileExtension {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]) else {
                continue
            }
            guard values.isRegularFile == true, (values.contentModificationDate ?? .distantPast) >= date else {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func locateTokscale() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/tokscale",
            "/usr/local/bin/tokscale",
            home.appendingPathComponent(".local/bin/tokscale").path,
            home.appendingPathComponent(".bun/bin/tokscale").path,
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        guard
            let output = try? run(
                URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lic", "command -v tokscale"]
            ),
            let path = String(data: output, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init),
            FileManager.default.isExecutableFile(atPath: path)
        else { return nil }

        return URL(fileURLWithPath: path)
    }

    @discardableResult
    private static func run(_ executable: URL, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TOKSCALE_NATIVE_TIMEOUT_MS"] = "45000"
        environment["NODE_USE_ENV_PROXY"] = "1"
        process.environment = environment

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CollectorError.processFailed(executable.lastPathComponent)
        }
        return data
    }

    private static func number(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        if let text = value as? String, let number = Int64(text) { return max(0, number) }
        return 0
    }

    private static func detectedAntigravityConnection(in output: Data) -> Bool {
        guard let text = String(data: output, encoding: .utf8) else { return false }
        let pattern = #"detected connections:\s*([1-9][0-9]*)"#
        return text.range(of: pattern, options: .regularExpression) != nil
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
