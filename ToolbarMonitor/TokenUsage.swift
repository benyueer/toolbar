import Combine
import Foundation

struct TokenBreakdown: Equatable, Sendable, Codable {
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
    var estimatedCost: Double? = nil

    var id: String { agent }

    var displayName: String {
        Self.displayName(for: agent)
    }

    static func displayName(for agent: String) -> String {
        switch agent.lowercased() {
        case "codex": "Codex"
        case "claude": "Claude Code"
        case "gemini": "Gemini CLI"
        case "antigravity": "Antigravity"
        case "agy-cli", "antigravity-cli", "agy": "Agy CLI"
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
    let isCached: Bool
    let cachedAt: Date?

    init(
        id: String,
        provider: String,
        plan: String? = nil,
        windows: [QuotaWindowUsage],
        isCached: Bool = false,
        cachedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.isCached = isCached
        self.cachedAt = cachedAt
    }

    var canonicalAgent: String {
        let key = provider.lowercased()
        if key.contains("codex") { return "codex" }
        if key.contains("claude") { return "claude" }
        if key.contains("antigravity") { return "antigravity" }
        if key.contains("agy") { return "agy-cli" }
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

    var days: [DailyTokenUsage] = [] {
        didSet {
            recomputeAggregates()
        }
    }
    var quotaProviders: [ProviderQuotaUsage] = []
    var quotaSource: QuotaSource?
    var source: Source = .localLogs
    var antigravitySynced = false
    var note: String?
    var generatedAt = Date()

    // 预计算的常用聚合缓存，使 SwiftUI 视图层读取全部降为 O(1) 零内存分配
    private(set) var today = TokenBreakdown()
    private(set) var todayEstimatedCost: Double?
    private(set) var last7Days = TokenBreakdown()
    private(set) var last7DaysEstimatedCost: Double?
    private(set) var last30Days = TokenBreakdown()
    private(set) var last30DaysEstimatedCost: Double?
    private(set) var maxDailyTokens: Int64 = 0
    private(set) var agents1Day: [AgentTokenUsage] = []
    private(set) var agents7Days: [AgentTokenUsage] = []
    private(set) var agents30Days: [AgentTokenUsage] = []
    private(set) var daysByKey: [String: DailyTokenUsage] = [:]

    static let empty = TokenUsageSnapshot()

    init(
        days: [DailyTokenUsage] = [],
        quotaProviders: [ProviderQuotaUsage] = [],
        quotaSource: QuotaSource? = nil,
        source: Source = .localLogs,
        antigravitySynced: Bool = false,
        note: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.days = days
        self.quotaProviders = quotaProviders
        self.quotaSource = quotaSource
        self.source = source
        self.antigravitySynced = antigravitySynced
        self.note = note
        self.generatedAt = generatedAt
        recomputeAggregates()
    }

    private mutating func recomputeAggregates() {
        today = computeTotals(last: 1)
        todayEstimatedCost = selectedDays(last: 1).first?.estimatedCost
        last7Days = computeTotals(last: 7)
        last7DaysEstimatedCost = computeEstimatedCost(last: 7)
        last30Days = computeTotals(last: 30)
        last30DaysEstimatedCost = computeEstimatedCost(last: 30)
        maxDailyTokens = days.reduce(0) { max($0, $1.tokens.total) }
        agents1Day = selectedDays(last: 1).first?.agents ?? []
        agents7Days = computeAgents(last: 7)
        agents30Days = computeAgents(last: 30)
        daysByKey = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
    }

    private func computeEstimatedCost(last count: Int) -> Double? {
        let costs = selectedDays(last: count).compactMap(\.estimatedCost)
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +)
    }

    func day(forKey key: String) -> DailyTokenUsage? {
        daysByKey[key]
    }

    func totals(last count: Int) -> TokenBreakdown {
        switch count {
        case 1: return today
        case 7: return last7Days
        case 30: return last30Days
        default: return computeTotals(last: count)
        }
    }

    func estimatedCost(last count: Int) -> Double? {
        switch count {
        case 1: return todayEstimatedCost
        case 7: return last7DaysEstimatedCost
        case 30: return last30DaysEstimatedCost
        default: return computeEstimatedCost(last: count)
        }
    }

    func agents(last count: Int) -> [AgentTokenUsage] {
        switch count {
        case 1: return agents1Day
        case 7: return agents7Days
        case 30: return agents30Days
        default: return computeAgents(last: count)
        }
    }

    private func computeTotals(last count: Int) -> TokenBreakdown {
        selectedDays(last: count).reduce(into: TokenBreakdown()) { result, day in
            result = result + day.tokens
        }
    }

    private func computeAgents(last count: Int) -> [AgentTokenUsage] {
        var agentTotals: [String: TokenBreakdown] = [:]
        var modelTotals: [String: [String: TokenBreakdown]] = [:]
        var costTotals: [String: Double] = [:]

        for day in selectedDays(last: count) {
            for agent in day.agents {
                agentTotals[agent.agent, default: TokenBreakdown()] =
                    agentTotals[agent.agent, default: TokenBreakdown()] + agent.tokens
                if let cost = agent.estimatedCost {
                    costTotals[agent.agent, default: 0] += cost
                }
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
            return AgentTokenUsage(
                agent: agent,
                tokens: tokens,
                models: models,
                estimatedCost: costTotals[agent]
            )
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
    @Published private(set) var isQuotaRefreshing = false
    @Published private(set) var isUsageRefreshing = false
    @Published private(set) var lastUsageRefresh: Date? = Date()
    @Published private(set) var errorMessage: String?

    private let refreshInterval: TimeInterval = 3 * 60
    private let antigravitySyncInterval: TimeInterval = 10 * 60
    private let quotaRefreshInterval: TimeInterval = 10 * 60
    private var lastAntigravitySync: Date?
    private var lastQuotaRefresh: Date?
    private var timer: Timer?

    init() {
        refresh(forceAntigravitySync: true, forceQuotaRefresh: true)
        let scheduledTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        // 设置 15 秒定时器容差，允许 macOS 合并后台唤醒
        scheduledTimer.tolerance = 15
        RunLoop.main.add(scheduledTimer, forMode: .common)
        self.timer = scheduledTimer
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
        isQuotaRefreshing = shouldRefreshQuotas
        isUsageRefreshing = true
        errorMessage = nil

        // 分阶段渐进式加载：本地 Token 用量（~0.3s）完成后立刻更新菜单栏与主界面，不被网络额度请求阻塞
        Task { [weak self] in
            async let usageTask = Task.detached(priority: .userInitiated) {
                await TokenUsageCollector.collectUsageOnly(syncAntigravity: shouldSync)
            }.value

            async let quotasTask = Task.detached(priority: .userInitiated) { () -> ([ProviderQuotaUsage]?, TokenUsageSnapshot.QuotaSource?) in
                guard shouldRefreshQuotas else {
                    return (cachedQuotas, cachedQuotaSource)
                }
                return TokenUsageCollector.collectQuotasOnly(forceRefresh: forceQuotaRefresh)
            }.value

            var usageSnapshot = await usageTask

            if let self {
                // 先保留已有额度缓存，立刻将最新 Token 用量与花费渲染到菜单栏和面板
                usageSnapshot.quotaProviders = self.snapshot.quotaProviders.isEmpty ? cachedQuotas : self.snapshot.quotaProviders
                usageSnapshot.quotaSource = self.snapshot.quotaSource ?? cachedQuotaSource
                self.snapshot = usageSnapshot
                self.isUsageRefreshing = false
                self.lastUsageRefresh = Date()
                if shouldSync, usageSnapshot.source == .embeddedCollector, usageSnapshot.antigravitySynced {
                    self.lastAntigravitySync = Date()
                }
                if !shouldRefreshQuotas {
                    self.isRefreshing = false
                    self.isQuotaRefreshing = false
                }
            }

            guard shouldRefreshQuotas else { return }

            let (fetchedQuotas, fetchedSource) = await quotasTask
            guard let self else { return }

            var finalSnapshot = self.snapshot
            if let fetchedQuotas, !fetchedQuotas.isEmpty, let fetchedSource {
                finalSnapshot.quotaProviders = fetchedQuotas
                finalSnapshot.quotaSource = fetchedSource
                self.lastQuotaRefresh = Date()
            } else {
                finalSnapshot.quotaProviders = cachedQuotas
                finalSnapshot.quotaSource = cachedQuotaSource
                let quotaNote = cachedQuotas.isEmpty
                    ? "内置 TokenTracker 额度采集器暂时不可用"
                    : "内置 TokenTracker 额度暂时无法刷新，继续显示上次结果"
                finalSnapshot.note = [finalSnapshot.note, quotaNote].compactMap { $0 }.joined(separator: "；")
            }

            self.snapshot = finalSnapshot
            self.isQuotaRefreshing = false
            self.isRefreshing = false
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

    private struct DayAccumulator {
        var tokens = TokenBreakdown()
        var agents: [String: TokenBreakdown] = [:]
        var models: [String: [String: TokenBreakdown]] = [:]
        var agentCosts: [String: Double] = [:]
        var estimatedCost: Double?
    }

    // 排除已由本地混合解析器 100% 精准接管的 antigravity（省去扫描 44.6K 条缓存记录的 CPU 开销）及未配置会输出警告的 cursor
    private static let embeddedGraphClientList =
        "opencode,claude,codex,gemini,amp,droid,openclaw,pi,kimi,qwen,roocode,kilocode,mux,kilo,crush,hermes,copilot,goose,codebuff,zed,kiro,trae,synthetic"

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

    /// 线程安全的可执行文件与资源路径定位缓存器（带有 TTL 保护，避免频繁磁盘 stat 或启动 Shell）
    private final class ExecutableLocator: @unchecked Sendable {
        static let shared = ExecutableLocator()
        private let lock = NSLock()
        private var cache: [String: (url: URL?, timestamp: Date)] = [:]
        private let ttl: TimeInterval = 600 // 缓存 10 分钟

        func locateFile(_ key: String, candidates: [URL], requireExecutable: Bool) -> URL? {
            lock.lock()
            if let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < ttl {
                let url = cached.url
                lock.unlock()
                return url
            }
            lock.unlock()

            let found = candidates.first { url in
                if requireExecutable {
                    return FileManager.default.isExecutableFile(atPath: url.path)
                } else {
                    return FileManager.default.fileExists(atPath: url.path)
                }
            }

            lock.lock()
            cache[key] = (found, Date())
            lock.unlock()
            return found
        }

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

    /// 会话内部聚合记录（支持 Codable 持久化到磁盘）
    private struct NativeSessionRecord: Codable {
        let dateKey: String
        let model: String
        let tokens: TokenBreakdown
    }

    /// 会话文件级别增量缓存项（基于修改时间戳与文件大小，防止每次遍历或应用重启后重复读取 6GB+ 巨量日志）
    private struct NativeSessionCacheEntry: Codable {
        let modificationTime: TimeInterval
        let fileSize: UInt64
        let records: [NativeSessionRecord]
    }

    /// 线程安全且支持跨进程磁盘持久化的 Antigravity / Agy CLI 会话解析增量缓存单例
    private final class NativeAntigravityCache: @unchecked Sendable {
        static let shared = NativeAntigravityCache()
        private let lock = NSLock()
        private var cache: [String: NativeSessionCacheEntry] = [:]
        private var isDirty = false
        private let diskCacheURL: URL

        private init() {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            let dir = appSupport.appendingPathComponent("ToolbarMonitor", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.diskCacheURL = dir.appendingPathComponent("native-session-cache-v2.json", isDirectory: false)

            if let data = try? Data(contentsOf: diskCacheURL),
               let decoded = try? JSONDecoder().decode([String: NativeSessionCacheEntry].self, from: data) {
                self.cache = decoded
            }
        }

        func get(path: String, modificationDate: Date, fileSize: UInt64) -> [NativeSessionRecord]? {
            let mtime = modificationDate.timeIntervalSince1970
            lock.lock()
            defer { lock.unlock() }
            guard let entry = cache[path] else { return nil }
            if abs(entry.modificationTime - mtime) < 0.001 && entry.fileSize == fileSize {
                return entry.records
            }
            return nil
        }

        func set(path: String, modificationDate: Date, fileSize: UInt64, records: [NativeSessionRecord]) {
            let mtime = modificationDate.timeIntervalSince1970
            lock.lock()
            cache[path] = NativeSessionCacheEntry(
                modificationTime: mtime,
                fileSize: fileSize,
                records: records
            )
            isDirty = true
            lock.unlock()
        }

        /// 若本轮扫描有新解析或更新的会话，异步将增量缓存持久化到磁盘
        func flushToDiskIfNeeded(activePaths: Set<String>) {
            lock.lock()
            guard isDirty else {
                lock.unlock()
                return
            }
            isDirty = false
            // 清理已过期或不在活跃集合中的条目，保持磁盘缓存紧凑（通常仅几十 KB）
            if !activePaths.isEmpty && cache.count > activePaths.count + 50 {
                cache = cache.filter { activePaths.contains($0.key) }
            }
            let snapshotToSave = cache
            lock.unlock()

            let targetURL = diskCacheURL
            DispatchQueue.global(qos: .utility).async {
                guard let data = try? JSONEncoder().encode(snapshotToSave) else { return }
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    /// 采集并合并本地 Token 用量（不阻塞等待额度网络请求）
    static func collectUsageOnly(syncAntigravity: Bool) async -> TokenUsageSnapshot {
        // 在后台按 TTL（12 小时）静默刷新本地 LiteLLM 价格缓存，既不阻塞统计，又保证最新模型费率持续生效
        ModelPricingCatalog.shared.refreshCacheInBackgroundIfNeeded()

        // 并行任务 1A：从内置统计引擎拉取除 Antigravity 外的各客户端 Token 用量
        async let graphTask = Task.detached(priority: .userInitiated) { () -> TokenUsageSnapshot in
            var snapshot: TokenUsageSnapshot
            if let executable = locateEmbeddedUsageCollector() {
                if syncAntigravity, shouldPerformInitialAntigravityCacheSync() {
                    // 仅在本地旧版历史回退缓存目录尚未初始化时，在后台静默同步一次；
                    // 新版会话均已直接从 transcript.jsonl 读取内联 Token 与 model，无需周期性启动外部进程全量同步
                    Task.detached(priority: .utility) {
                        _ = try? run(
                            executable,
                            arguments: ["antigravity", "sync"],
                            timeout: 15
                        )
                    }
                }

                do {
                    let start = dayKey(for: Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date())
                    let data = try run(
                        executable,
                        arguments: [
                            "graph",
                            "--since", start,
                            "--no-spinner",
                            "-c", embeddedGraphClientList,
                        ],
                        timeout: 15
                    )
                    snapshot = try parseUsageGraph(data)
                    snapshot.source = .embeddedCollector
                    snapshot.antigravitySynced = true
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

        // 并行任务 1B：并发扫描原生 Antigravity 与 Agy CLI 会话日志（带内存+磁盘双层增量缓存）
        async let localAntigravityTask = Task.detached(priority: .userInitiated) { () -> TokenUsageSnapshot in
            collectLocalAntigravity()
        }.value

        var finalSnapshot = await graphTask
        let localSnapshot = await localAntigravityTask
        mergeAntigravityDataIfNeeded(into: &finalSnapshot, from: localSnapshot)
        return finalSnapshot
    }

    /// 仅从内置 TokenTracker 采集已启用 Provider 的账户实时额度
    static func collectQuotasOnly(forceRefresh: Bool) -> ([ProviderQuotaUsage]?, TokenUsageSnapshot.QuotaSource?) {
        if let limitsData = try? fetchEmbeddedTokenTrackerLimits(forceRefresh: forceRefresh),
           let quotas = try? parseEmbeddedTokenTrackerLimits(limitsData),
           !quotas.isEmpty {
            return (quotas, .embeddedTokenTracker)
        }
        return (nil, nil)
    }

    static func collect(
        syncAntigravity: Bool,
        refreshQuotas: Bool = true,
        forceQuotaProviderRefresh: Bool = false,
        cachedQuotas: [ProviderQuotaUsage] = [],
        cachedQuotaSource: TokenUsageSnapshot.QuotaSource? = nil
    ) async throws -> TokenUsageSnapshot {
        async let usageTask = collectUsageOnly(syncAntigravity: syncAntigravity)
        async let quotasTask = Task.detached(priority: .userInitiated) { () -> ([ProviderQuotaUsage]?, TokenUsageSnapshot.QuotaSource?) in
            guard refreshQuotas else {
                return (cachedQuotas, cachedQuotaSource)
            }
            return collectQuotasOnly(forceRefresh: forceQuotaProviderRefresh)
        }.value

        var finalSnapshot = await usageTask
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

    /// 模型费率（单位：美元 / 百万 Token）
    private struct ModelRate: Sendable {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    /// 线程安全的动态模型定价目录：
    /// 1. 优先复用内置 usage-collector（Tokscale）缓存目录下的 custom-pricing.json / pricing-litellm.json / pricing-openrouter.json；
    /// 2. 后台按 12 小时 TTL 从 LiteLLM 官方源刷新缓存并原子写回 Tokscale 兼容格式；
    /// 3. 无缓存或未命中时回退至 2026-11 最新官方费率表。
    private final class ModelPricingCatalog: @unchecked Sendable {
        static let shared = ModelPricingCatalog()

        private static let litellmPricingURL = URL(
            string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        )!
        private static let refreshTTL: TimeInterval = 12 * 60 * 60
        private static let million: Double = 1_000_000

        private static let tokscaleCostFields: [String] = [
            "input_cost_per_token",
            "input_cost_per_token_above_128k_tokens",
            "input_cost_per_token_above_200k_tokens",
            "input_cost_per_token_above_256k_tokens",
            "input_cost_per_token_above_272k_tokens",
            "output_cost_per_token",
            "output_cost_per_token_above_128k_tokens",
            "output_cost_per_token_above_200k_tokens",
            "output_cost_per_token_above_256k_tokens",
            "output_cost_per_token_above_272k_tokens",
            "cache_creation_input_token_cost",
            "cache_creation_input_token_cost_above_200k_tokens",
            "cache_read_input_token_cost",
            "cache_read_input_token_cost_above_200k_tokens",
            "cache_read_input_token_cost_above_272k_tokens",
        ]

        private static let reasoningSuffixes: [String] = [
            "-xhigh-fast",
            "-high-fast",
            "-medium-fast",
            "-low-fast",
            "-xhigh",
            "-high",
            "-medium",
            "-low",
            "-fast",
            "-thinking",
            "-think",
        ]

        private static let excludedPrefixes: [String] = [
            "github_copilot/",
            "azure/",
            "azure_ai/",
            "bedrock/",
            "vertex_ai/",
            "vertex_ai_beta/",
            "databricks/",
            "sagemaker/",
            "snowflake/",
            "aihubmix/",
            "apac.",
            "eu.",
            "us.",
        ]

        private let lock = NSLock()
        private var customRates: [String: ModelRate] = [:]
        private var litellmRates: [String: ModelRate] = [:]
        private var openrouterRates: [String: ModelRate] = [:]
        private var customMtime: TimeInterval?
        private var litellmMtime: TimeInterval?
        private var openrouterMtime: TimeInterval?
        private var lookupCache: [String: ModelRate] = [:]
        private var isRefreshingRemote = false
        private var lastRefreshAttempt: Date?

        private init() {}

        func rate(for rawModel: String, agent: String) -> ModelRate {
            reloadDiskCachesIfNeeded()

            let cacheKey = "\(agent.lowercased())|\(rawModel)"
            lock.lock()
            if let cached = lookupCache[cacheKey] {
                lock.unlock()
                return cached
            }
            let custom = customRates
            let litellm = litellmRates
            let openrouter = openrouterRates
            lock.unlock()

            let resolved = resolveRate(
                rawModel: rawModel,
                agent: agent,
                custom: custom,
                litellm: litellm,
                openrouter: openrouter
            )

            lock.lock()
            if lookupCache.count > 512 {
                lookupCache.removeAll(keepingCapacity: true)
            }
            lookupCache[cacheKey] = resolved
            lock.unlock()
            return resolved
        }

        /// 在后台按 TTL 检查并更新本地 LiteLLM 价格缓存（与 usage-collector 共享同一文件）
        func refreshCacheInBackgroundIfNeeded(force: Bool = false) {
            let cacheURL = litellmCacheURL()
            let now = Date()

            lock.lock()
            if isRefreshingRemote {
                lock.unlock()
                return
            }
            if !force, let lastAttempt = lastRefreshAttempt, now.timeIntervalSince(lastAttempt) < 30 * 60 {
                lock.unlock()
                return
            }
            if !force,
               let mtime = fileModificationDate(at: cacheURL),
               now.timeIntervalSince(mtime) < Self.refreshTTL {
                lock.unlock()
                return
            }
            isRefreshingRemote = true
            lastRefreshAttempt = now
            lock.unlock()

            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                defer {
                    self.finishRemoteRefresh()
                }
                await self.fetchAndPersistLitellmCache(to: cacheURL)
            }
        }

        private func finishRemoteRefresh() {
            lock.lock()
            isRefreshingRemote = false
            lock.unlock()
        }

        private func invalidateLitellmCache() {
            lock.lock()
            litellmMtime = nil
            lookupCache.removeAll(keepingCapacity: true)
            lock.unlock()
        }

        private func fetchAndPersistLitellmCache(to destinationURL: URL) async {
            var request = URLRequest(url: Self.litellmPricingURL)
            request.timeoutInterval = 15
            request.setValue("ToolbarMonitor/1.0", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let rawObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return
            }

            // 精简并转换为 Tokscale 缓存格式：{ "timestamp": <unix_sec>, "data": { ... } }
            var slimData: [String: [String: Any]] = [:]
            slimData.reserveCapacity(rawObject.count)
            for (modelKey, value) in rawObject {
                guard let entry = value as? [String: Any] else { continue }
                var filtered: [String: Any] = [:]
                var hasAnyCost = false
                for field in Self.tokscaleCostFields {
                    if let num = Self.doubleValue(entry[field]), num.isFinite {
                        filtered[field] = num
                        hasAnyCost = true
                    }
                }
                if hasAnyCost {
                    slimData[modelKey] = filtered
                }
            }

            guard !slimData.isEmpty else { return }

            let payload: [String: Any] = [
                "timestamp": Int64(Date().timeIntervalSince1970),
                "data": slimData,
            ]
            guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else { return }

            let dir = destinationURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? encoded.write(to: destinationURL, options: .atomic)

            // 清空内存查找缓存，下次计费自动重新读取最新文件
            invalidateLitellmCache()
        }

        private func cacheDirectory() -> URL {
            TokenUsageCollector.prepareUsageCollectorStorage().appendingPathComponent("cache", isDirectory: true)
        }

        private func customPricingURL() -> URL {
            TokenUsageCollector.prepareUsageCollectorStorage().appendingPathComponent("custom-pricing.json", isDirectory: false)
        }

        private func litellmCacheURL() -> URL {
            cacheDirectory().appendingPathComponent("pricing-litellm.json", isDirectory: false)
        }

        private func openrouterCacheURL() -> URL {
            cacheDirectory().appendingPathComponent("pricing-openrouter.json", isDirectory: false)
        }

        private func fileModificationDate(at url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }

        private func reloadDiskCachesIfNeeded() {
            let customURL = customPricingURL()
            let litellmURL = litellmCacheURL()
            let openrouterURL = openrouterCacheURL()

            let curCustomMtime = fileModificationDate(at: customURL)?.timeIntervalSince1970
            let curLitellmMtime = fileModificationDate(at: litellmURL)?.timeIntervalSince1970
            let curOpenrouterMtime = fileModificationDate(at: openrouterURL)?.timeIntervalSince1970

            lock.lock()
            let needCustom = curCustomMtime != customMtime
            let needLitellm = curLitellmMtime != litellmMtime
            let needOpenrouter = curOpenrouterMtime != openrouterMtime
            lock.unlock()

            guard needCustom || needLitellm || needOpenrouter else { return }

            let parsedCustom = needCustom ? loadCustomPricing(from: customURL) : nil
            let parsedLitellm = needLitellm ? loadDatasetPricing(from: litellmURL) : nil
            let parsedOpenrouter = needOpenrouter ? loadDatasetPricing(from: openrouterURL) : nil

            lock.lock()
            if needCustom {
                customRates = parsedCustom ?? [:]
                customMtime = curCustomMtime
            }
            if needLitellm {
                litellmRates = parsedLitellm ?? [:]
                litellmMtime = curLitellmMtime
            }
            if needOpenrouter {
                openrouterRates = parsedOpenrouter ?? [:]
                openrouterMtime = curOpenrouterMtime
            }
            lookupCache.removeAll(keepingCapacity: true)
            lock.unlock()
        }

        private func loadCustomPricing(from url: URL) -> [String: ModelRate] {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = root["models"] as? [String: Any]
            else {
                return [:]
            }

            var result: [String: ModelRate] = [:]
            for (rawKey, rawValue) in models {
                guard let entry = rawValue as? [String: Any] else { continue }
                let input = Self.doubleValue(entry["input_cost_per_million_tokens"])
                    ?? Self.doubleValue(entry["input_cost_per_token"]).map { $0 * Self.million }
                let output = Self.doubleValue(entry["output_cost_per_million_tokens"])
                    ?? Self.doubleValue(entry["output_cost_per_token"]).map { $0 * Self.million }
                guard let input, let output, (input > 0 || output > 0) else { continue }

                let cacheRead = Self.doubleValue(entry["cache_read_input_token_cost_per_million_tokens"])
                    ?? Self.doubleValue(entry["cache_read_input_token_cost"]).map { $0 * Self.million }
                    ?? 0
                let cacheWrite = Self.doubleValue(entry["cache_creation_input_token_cost_per_million_tokens"])
                    ?? Self.doubleValue(entry["cache_creation_input_token_cost"]).map { $0 * Self.million }
                    ?? 0

                result[rawKey.lowercased()] = ModelRate(
                    input: input,
                    output: output,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite
                )
            }
            return result
        }

        private func loadDatasetPricing(from url: URL) -> [String: ModelRate] {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataset = (root["data"] as? [String: Any]) ?? (root as [String: Any]?)
            else {
                return [:]
            }

            var result: [String: ModelRate] = [:]
            result.reserveCapacity(dataset.count)

            for (rawKey, rawValue) in dataset {
                let lowerKey = rawKey.lowercased()
                if lowerKey.hasSuffix(":batch") || lowerKey.hasSuffix(":free") {
                    continue
                }
                if Self.excludedPrefixes.contains(where: { lowerKey.hasPrefix($0) }) {
                    continue
                }
                guard let entry = rawValue as? [String: Any] else { continue }
                let inputPerToken = Self.doubleValue(entry["input_cost_per_token"]) ?? 0
                let outputPerToken = Self.doubleValue(entry["output_cost_per_token"]) ?? 0
                guard inputPerToken > 0 || outputPerToken > 0 else { continue }

                let cacheReadPerToken = Self.doubleValue(entry["cache_read_input_token_cost"]) ?? 0
                let cacheWritePerToken = Self.doubleValue(entry["cache_creation_input_token_cost"]) ?? 0

                result[lowerKey] = ModelRate(
                    input: inputPerToken * Self.million,
                    output: outputPerToken * Self.million,
                    cacheRead: cacheReadPerToken * Self.million,
                    cacheWrite: cacheWritePerToken * Self.million
                )
            }
            return result
        }

        private func resolveRate(
            rawModel: String,
            agent: String,
            custom: [String: ModelRate],
            litellm: [String: ModelRate],
            openrouter: [String: ModelRate]
        ) -> ModelRate {
            let candidates = buildLookupCandidates(for: rawModel)
            let providerPrefixes = preferredPrefixes(for: rawModel, agent: agent)

            // 1. 自定义覆盖价格
            if let rate = lookup(candidates: candidates, prefixes: providerPrefixes, in: custom) {
                return rate
            }
            // 2. LiteLLM 官方价格表（与 usage-collector 主口径一致）
            if let rate = lookup(candidates: candidates, prefixes: providerPrefixes, in: litellm) {
                return rate
            }
            // 3. OpenRouter 价格表
            if let rate = lookup(candidates: candidates, prefixes: providerPrefixes, in: openrouter) {
                return rate
            }
            // 4. 离线最新兜底费率表
            return fallbackRate(for: rawModel, agent: agent)
        }

        private func lookup(
            candidates: [String],
            prefixes: [String],
            in table: [String: ModelRate]
        ) -> ModelRate? {
            guard !table.isEmpty else { return nil }
            for candidate in candidates {
                if let exact = table[candidate] {
                    return exact
                }
            }
            for candidate in candidates {
                for prefix in prefixes {
                    if let prefixed = table["\(prefix)\(candidate)"] {
                        return prefixed
                    }
                }
            }
            return nil
        }

        private func preferredPrefixes(for rawModel: String, agent: String) -> [String] {
            let lower = rawModel.lowercased()
            let agentLower = agent.lowercased()

            if lower.contains("gemini") {
                return ["gemini/", "google/"]
            }
            if lower.contains("claude") {
                return ["anthropic/", "anthropic."]
            }
            if lower.contains("gpt") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
                return ["openai/"]
            }
            if lower.contains("grok") {
                return ["xai/", "x-ai/"]
            }
            if lower.contains("deepseek") {
                return ["deepseek/"]
            }
            if lower.contains("kimi") {
                return ["moonshot/", "moonshotai/"]
            }
            if lower.contains("glm") {
                return ["zai/", "z-ai/", "zhipu/"]
            }
            if agentLower == "antigravity" || agentLower == "agy-cli" || agentLower == "gemini" {
                return ["gemini/", "google/", "anthropic/", "openai/"]
            }
            return ["openai/", "anthropic/", "gemini/", "google/", "xai/", "deepseek/"]
        }

        private func buildLookupCandidates(for rawModel: String) -> [String] {
            var seen = Set<String>()
            var result: [String] = []

            func append(_ value: String) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
                result.append(trimmed)
            }

            let rawLower = rawModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            append(rawLower)

            // 若带供应商前缀，同时保留去掉前缀后的裸模型名
            let base = rawLower.split(separator: "/").last.map(String.init) ?? rawLower
            append(base)

            // 去除括号修饰，例如 "Gemini 4 Neon (High)" -> "gemini-4-neon"
            let withoutParens = base.replacingOccurrences(
                of: #"\([^)]*\)"#,
                with: " ",
                options: .regularExpression
            )
            let normalized = withoutParens
                .replacingOccurrences(of: #"[^a-z0-9.]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            append(normalized)

            // 迭代剥离尾部推理档位后缀（例如 gemini-4-neon-high -> gemini-4-neon）
            var stripped = normalized
            var didStrip = true
            while didStrip {
                didStrip = false
                for suffix in Self.reasoningSuffixes where stripped.hasSuffix(suffix) {
                    stripped = String(stripped.dropLast(suffix.count))
                    append(stripped)
                    didStrip = true
                    break
                }
            }

            // 兼容 Claude 小数点与连字符版本写法（claude-opus-4.6 <-> claude-opus-4-6）
            let snapshot = result
            for item in snapshot {
                if item.hasPrefix("claude-") {
                    let hyphenMinor = item.replacingOccurrences(
                        of: #"^(claude-(?:opus|sonnet|haiku|fable)-\d+)\.(\d+)"#,
                        with: "$1-$2",
                        options: .regularExpression
                    )
                    append(hyphenMinor)
                    let dotMinor = item.replacingOccurrences(
                        of: #"^(claude-(?:opus|sonnet|haiku|fable)-\d+)-(\d+)"#,
                        with: "$1.$2",
                        options: .regularExpression
                    )
                    append(dotMinor)
                }
            }

            return result
        }

        private func fallbackRate(for rawModel: String, agent: String) -> ModelRate {
            let name = rawModel.lowercased()
            let agentKey = agent.lowercased()

            // Claude 系列（按 Anthropic 最新官方价）
            if name.contains("fable") {
                if name.contains("5-2") || name.contains("5.2") {
                    return ModelRate(input: 8.00, output: 40.00, cacheRead: 0.20, cacheWrite: 10.00)
                }
                return ModelRate(input: 10.00, output: 50.00, cacheRead: 1.00, cacheWrite: 12.50)
            }
            if name.contains("opus") {
                if name.contains("opus-4-1") || name.contains("opus-4.1") || name.contains("opus-4-2025") {
                    return ModelRate(input: 15.00, output: 75.00, cacheRead: 1.50, cacheWrite: 18.75)
                }
                return ModelRate(input: 5.00, output: 25.00, cacheRead: 0.50, cacheWrite: 6.25)
            }
            if name.contains("sonnet") {
                if name.contains("sonnet-5-5") || name.contains("sonnet-5.5") {
                    return ModelRate(input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite: 2.50)
                }
                if name.contains("sonnet-5") {
                    return ModelRate(input: 2.00, output: 10.00, cacheRead: 0.20, cacheWrite: 2.50)
                }
                return ModelRate(input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75)
            }
            if name.contains("haiku") {
                if name.contains("4-5") || name.contains("4.5") || name.contains("haiku-4") {
                    return ModelRate(input: 1.00, output: 5.00, cacheRead: 0.10, cacheWrite: 1.25)
                }
                return ModelRate(input: 0.80, output: 4.00, cacheRead: 0.08, cacheWrite: 1.00)
            }

            // Gemini 系列（含 Gemini 4 与 Gemini 3.x / 2.5）
            if name.contains("gemini") || agentKey == "antigravity" || agentKey == "agy-cli" || agentKey == "gemini" {
                if name.contains("neon") {
                    return ModelRate(input: 3.00, output: 15.00, cacheRead: 0.15, cacheWrite: 0)
                }
                if name.contains("argon") || name.contains("carbon") {
                    return ModelRate(input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite: 0)
                }
                if name.contains("hydrogen") {
                    return ModelRate(input: 1.50, output: 7.50, cacheRead: 0.075, cacheWrite: 0)
                }
                if name.contains("3.8-flash") || name.contains("3.7-flash") {
                    return ModelRate(input: 0.75, output: 3.75, cacheRead: 0.075, cacheWrite: 0)
                }
                if name.contains("3.5-flash-lite") {
                    return ModelRate(input: 0.30, output: 2.50, cacheRead: 0.03, cacheWrite: 0)
                }
                if name.contains("3.5-flash") {
                    return ModelRate(input: 1.50, output: 9.00, cacheRead: 0.15, cacheWrite: 0)
                }
                if name.contains("3.1-pro") || name.contains("3-pro") || name.contains("3.0-pro") {
                    return ModelRate(input: 2.00, output: 12.00, cacheRead: 0.20, cacheWrite: 0)
                }
                if name.contains("pro") {
                    return ModelRate(input: 1.25, output: 10.00, cacheRead: 0.125, cacheWrite: 0)
                }
                if name.contains("3-flash") || name.contains("3.0-flash") {
                    return ModelRate(input: 0.50, output: 3.00, cacheRead: 0.05, cacheWrite: 0)
                }
                return ModelRate(input: 0.30, output: 2.50, cacheRead: 0.03, cacheWrite: 0)
            }

            // OpenAI / Codex GPT-6 / GPT-5 系列
            if name.contains("gpt-6.2-astra") {
                return ModelRate(input: 8.00, output: 40.00, cacheRead: 0.40, cacheWrite: 10.00)
            }
            if name.contains("astra") {
                return ModelRate(input: 10.00, output: 50.00, cacheRead: 1.00, cacheWrite: 12.50)
            }
            if name.contains("gpt-6.2-sol") || name.contains("gpt-6.1-sol") {
                return ModelRate(input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite: 2.50)
            }
            if name.contains("gpt-6-sol") {
                return ModelRate(input: 2.00, output: 10.00, cacheRead: 0.20, cacheWrite: 2.50)
            }
            if name.contains("gpt-6-luna") || name.contains("gpt-6.1-luna") {
                return ModelRate(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125)
            }
            if name.contains("gpt-5.6-sol") {
                return ModelRate(input: 4.00, output: 20.00, cacheRead: 0.40, cacheWrite: 5.00)
            }
            if name.contains("gpt-5.6-terra") {
                return ModelRate(input: 2.00, output: 12.00, cacheRead: 0.20, cacheWrite: 2.50)
            }
            if name.contains("gpt-5.6-luna") {
                return ModelRate(input: 0.20, output: 1.20, cacheRead: 0.02, cacheWrite: 0.25)
            }
            if name.contains("luna") || name.contains("nano") {
                return ModelRate(input: 0.20, output: 1.25, cacheRead: 0.02, cacheWrite: 0)
            }
            if name.contains("mini") || name.contains("flash") {
                return ModelRate(input: 0.75, output: 4.50, cacheRead: 0.075, cacheWrite: 0)
            }
            if name.contains("sol") || name.contains("gpt-6") || name.contains("gpt-5") || name.contains("o1") || name.contains("o3") {
                return ModelRate(input: 2.50, output: 15.00, cacheRead: 0.25, cacheWrite: 0)
            }
            return ModelRate(input: 2.50, output: 10.00, cacheRead: 0.25, cacheWrite: 0)
        }

        private static func doubleValue(_ value: Any?) -> Double? {
            if let num = value as? NSNumber { return num.doubleValue }
            if let str = value as? String { return Double(str) }
            return nil
        }
    }

    /// 精准估算单个 Agent 的预估费用（按输入、输出、缓存读取、缓存写入、思考推理细分，优先读取最新动态定价缓存）
    private static func estimateAgentCost(_ agent: AgentTokenUsage) -> Double {
        var totalCost: Double = 0
        let million: Double = 1_000_000

        for model in agent.models {
            let tokens = model.tokens
            let rate = ModelPricingCatalog.shared.rate(for: model.name, agent: agent.agent)

            let inputCost = (Double(tokens.input) / million) * rate.input
            let outputCost = (Double(tokens.output + tokens.reasoning) / million) * rate.output
            let cacheReadCost = (Double(tokens.cacheRead) / million) * rate.cacheRead
            let cacheWriteCost = (Double(tokens.cacheWrite) / million) * rate.cacheWrite
            totalCost += (inputCost + outputCost + cacheReadCost + cacheWriteCost)
        }
        return totalCost
    }

    /// 校准快照中的 Antigravity 与 Agy CLI 用量
    private static func mergeAntigravityDataIfNeeded(
        into snapshot: inout TokenUsageSnapshot,
        from localSnapshot: TokenUsageSnapshot
    ) {
        var daysMap = snapshot.daysByKey
        let targetAgents = ["antigravity", "agy-cli"]

        var allKeys = Set(daysMap.keys)
        for localDay in localSnapshot.days {
            allKeys.insert(localDay.dateKey)
        }

        let localDaysMap = localSnapshot.daysByKey

        for key in allKeys {
            var dayUsage = daysMap[key] ?? DailyTokenUsage(
                dateKey: key,
                tokens: TokenBreakdown(),
                agents: [],
                estimatedCost: nil
            )
            var agents = dayUsage.agents
            var dayChanged = false

            for targetAgent in targetAgents {
                let localAgent = localDaysMap[key]?.agents.first(where: { $0.agent == targetAgent })
                let existingIndex = agents.firstIndex(where: { $0.agent == targetAgent })

                if let localAgent, localAgent.tokens.total > 0 {
                    var calibratedAgent = localAgent
                    if calibratedAgent.estimatedCost == nil {
                        calibratedAgent.estimatedCost = estimateAgentCost(calibratedAgent)
                    }
                    if let existingIndex {
                        agents[existingIndex] = calibratedAgent
                    } else {
                        agents.append(calibratedAgent)
                    }
                    dayChanged = true
                } else if let existingIndex {
                    agents.remove(at: existingIndex)
                    dayChanged = true
                }
            }

            if dayChanged {
                var recalculatedTokens = TokenBreakdown()
                var recomputedCost: Double = 0
                for ag in agents {
                    recalculatedTokens = recalculatedTokens + ag.tokens
                    if let exact = ag.estimatedCost, exact > 0 {
                        recomputedCost += exact
                    } else {
                        recomputedCost += estimateAgentCost(ag)
                    }
                }

                dayUsage = DailyTokenUsage(
                    dateKey: key,
                    tokens: recalculatedTokens,
                    agents: agents.sorted { $0.tokens.total > $1.tokens.total },
                    estimatedCost: recomputedCost > 0 ? recomputedCost : (recalculatedTokens.total == 0 ? 0 : dayUsage.estimatedCost)
                )
                daysMap[key] = dayUsage
            }
        }

        // 严格保证按照 30 天日期窗口对齐输出
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var resultDays: [DailyTokenUsage] = []
        resultDays.reserveCapacity(30)
        for offset in (-29)...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = dayKey(for: date)
            if let usage = daysMap[key] {
                resultDays.append(usage)
            } else {
                resultDays.append(DailyTokenUsage(dateKey: key, tokens: TokenBreakdown(), agents: [], estimatedCost: 0))
            }
        }
        snapshot.days = resultDays
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
                if let cost = item.cost {
                    day.agentCosts[client, default: 0] += cost
                }
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
            let provenance = object(provider["provenance"])
            let isCached = (provider["cached"] as? Bool == true)
                || (provider["stale"] as? Bool == true)
                || (provenance?["stale"] as? Bool == true)
            let cachedAtText = (provider["cached_at"] as? String) ?? (provenance?["captured_at"] as? String)
            providers.append(
                ProviderQuotaUsage(
                    id: key,
                    provider: title,
                    plan: plan(provider),
                    windows: windows,
                    isCached: isCached,
                    cachedAt: cachedAtText.flatMap(parseISODate)
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

    /// 获取用户当前配置为可见的额度 Provider ID 列表，仅向这些平台发起额度探测
    private static func configuredVisibleQuotaProviderIds() -> [String] {
        let defaults = UserDefaults.standard
        let defaultVisible = ["codex", "antigravity", "opencodeGo"]
        guard let visibility = defaults.dictionary(forKey: "QuotaProviderVisibility") else {
            return defaultVisible
        }
        let allKnown = ["claude", "codex", "cursor", "kimi", "gemini", "kiro", "antigravity", "copilot", "grok", "zcode", "opencodeGo"]
        let enabled = allKnown.filter { (visibility[$0] as? Bool) ?? true }
        return enabled.isEmpty ? defaultVisible : enabled
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
        let targetProviders = configuredVisibleQuotaProviderIds().joined(separator: ",")
        var arguments = [runner.path, "--providers", targetProviders]
        if forceRefresh { arguments.append("--refresh") }
        return try run(node, arguments: arguments)
    }

    private static func locateTokenTrackerQuotaRunner() -> URL? {
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("TokenTrackerBackend/quota-runner.js"),
            sourceDirectory.appendingPathComponent("Resources/TokenTrackerBackend/quota-runner.js"),
        ].compactMap { $0 }
        return ExecutableLocator.shared.locateFile(
            "quota-runner.js",
            candidates: candidates,
            requireExecutable: false
        )
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

        parseNativeAntigravityAndAgy(
            earliestDate: earliestDate,
            into: &accumulators
        )

        return makeSnapshot(from: accumulators, source: .localLogs)
    }

    private static func collectLocalAntigravity() -> TokenUsageSnapshot {
        var accumulators: [String: DayAccumulator] = [:]
        let earliestDate = Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date()

        parseNativeAntigravityAndAgy(
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
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    continue
                }

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
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
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
                let data = try? Data(contentsOf: file, options: .mappedIfSafe),
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

    private struct CachedAntigravityStepUsage {
        let modelId: String?
        let tokens: TokenBreakdown
    }

    /// 构建 sessionId -> antigravity-cache 会话文件路径的索引
    private static func buildAntigravityCacheIndex() -> [String: URL] {
        let sessionsRoot = prepareUsageCollectorStorage().appendingPathComponent("antigravity-cache/sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var index: [String: URL] = [:]
        index.reserveCapacity(files.count)
        for file in files where file.pathExtension.lowercased() == "jsonl" {
            let name = file.deletingPathExtension().lastPathComponent
            guard name.count >= 36 else { continue }
            let sessionId = String(name.prefix(36))
            index[sessionId] = file
        }
        return index
    }

    /// 读取指定会话在 antigravity-cache 中的单步精确 Token 列表
    private static func loadCachedAntigravityUsages(from file: URL?) -> [CachedAntigravityStepUsage] {
        guard let file,
              let content = try? String(contentsOf: file, encoding: .utf8)
        else { return [] }

        var usages: [CachedAntigravityStepUsage] = []
        var fallbackModel: String?
        for line in content.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }

            let type = object["type"] as? String
            if type == "session_meta" {
                if let modelId = object["modelId"] as? String, !modelId.isEmpty {
                    fallbackModel = modelId
                }
                continue
            }
            guard type == "usage" else { continue }

            let tokens = TokenBreakdown(
                input: number(object["input"]),
                output: number(object["output"]),
                cacheRead: number(object["cacheRead"]),
                cacheWrite: number(object["cacheWrite"]),
                reasoning: number(object["reasoning"])
            )
            let modelId = (object["modelId"] as? String) ?? fallbackModel
            usages.append(CachedAntigravityStepUsage(modelId: modelId, tokens: tokens))
        }
        return usages
    }

    private static let plannerResponseMarker = Data("\"PLANNER_RESPONSE\"".utf8)
    private static let modelSelectionMarker = Data("Model Selection".utf8)
    private static let userInputMarker = Data("\"USER_INPUT\"".utf8)

    /// 直接解析本机 ~/.gemini/ 目录下 Antigravity IDE 和 Agy CLI 原生会话日志。
    /// 采用 mmap 零拷贝字节流扫描 + 内存与磁盘双层增量缓存，避免重复读取 6GB+ 巨量日志。
    private static func parseNativeAntigravityAndAgy(
        earliestDate: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiDir = home.appendingPathComponent(".gemini", isDirectory: true)

        let targets: [(agent: String, dir: URL)] = [
            ("antigravity", geminiDir.appendingPathComponent("antigravity/brain", isDirectory: true)),
            ("antigravity", geminiDir.appendingPathComponent("antigravity-ide/brain", isDirectory: true)),
            ("agy-cli", geminiDir.appendingPathComponent("antigravity-cli/brain", isDirectory: true)),
        ]

        let fileManager = FileManager.default
        let earliestDayKey = dayKey(for: earliestDate)
        var lazyCacheIndex: [String: URL]? = nil
        var activePaths = Set<String>()

        for target in targets {
            guard fileManager.fileExists(atPath: target.dir.path) else { continue }
            guard let sessionDirs = try? fileManager.contentsOfDirectory(
                at: target.dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for sessionDir in sessionDirs {
                let sessionId = sessionDir.lastPathComponent
                let transcriptFile = sessionDir
                    .appendingPathComponent(".system_generated", isDirectory: true)
                    .appendingPathComponent("logs", isDirectory: true)
                    .appendingPathComponent("transcript.jsonl", isDirectory: false)

                guard let values = try? transcriptFile.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      let mtime = values.contentModificationDate,
                      let size = values.fileSize,
                      mtime >= earliestDate
                else { continue }

                let filePath = transcriptFile.path
                activePaths.insert(filePath)

                // 优先从内存/磁盘增量缓存中 O(1) 获取该会话已聚合的记录
                if let cachedRecords = NativeAntigravityCache.shared.get(
                    path: filePath,
                    modificationDate: mtime,
                    fileSize: UInt64(size)
                ) {
                    for rec in cachedRecords where rec.dateKey >= earliestDayKey {
                        record(rec.tokens, agent: target.agent, model: rec.model, dateKey: rec.dateKey, into: &accumulators)
                    }
                    continue
                }

                // 使用 mmap 内存映射零拷贝读取新增或变更的会话文件
                guard let fileData = try? Data(contentsOf: transcriptFile, options: .mappedIfSafe),
                      !fileData.isEmpty
                else { continue }

                var cachedUsages: [CachedAntigravityStepUsage]?
                var currentModel: String?
                var plannerStepIndex = 0
                var sessionTokens: [String: [String: TokenBreakdown]] = [:]

                let newlineByte = UInt8(ascii: "\n")
                var lineStart = fileData.startIndex
                let endIndex = fileData.endIndex

                while lineStart < endIndex {
                    let lineEnd = fileData[lineStart..<endIndex].firstIndex(of: newlineByte) ?? endIndex
                    let lineData = fileData[lineStart..<lineEnd]
                    lineStart = lineEnd < endIndex ? lineEnd + 1 : endIndex

                    guard !lineData.isEmpty else { continue }

                    // 快速字节子串过滤：仅对包含目标标记的行执行 JSON 反序列化
                    if lineData.range(of: modelSelectionMarker) != nil && lineData.range(of: userInputMarker) != nil {
                        if let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                           object["type"] as? String == "USER_INPUT",
                           let textContent = object["content"] as? String,
                           let match = extractModelSelection(from: textContent) {
                            currentModel = normalizeAntigravityModel(match)
                        }
                    }

                    guard lineData.range(of: plannerResponseMarker) != nil,
                          let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          object["type"] as? String == "PLANNER_RESPONSE"
                    else { continue }

                    let stepIdx = plannerStepIndex
                    plannerStepIndex += 1

                    guard let timestamp = object["created_at"] as? String,
                          let stepDayKey = extractDayKey(from: timestamp)
                    else { continue }

                    let inputTokens = number(object["input_tokens"])
                    let outputTokens = number(object["output_tokens"])
                    let cacheRead = number(object["cache_read_tokens"])
                    let cacheWrite = number(object["cache_write_tokens"])

                    let inlineReasoning = number(object["reasoning_tokens"])
                    let reasoningTokens: Int64
                    if inlineReasoning > 0 {
                        reasoningTokens = inlineReasoning
                    } else if let thinking = object["thinking"] as? String, !thinking.isEmpty {
                        reasoningTokens = Int64(thinking.count / 3)
                    } else {
                        reasoningTokens = 0
                    }

                    var tokens = TokenBreakdown(
                        input: inputTokens,
                        output: outputTokens,
                        cacheRead: cacheRead,
                        cacheWrite: cacheWrite,
                        reasoning: reasoningTokens
                    )

                    // 优先读取 PLANNER_RESPONSE 内联的 model 字段，其次使用会话切换的模型名
                    var stepModel: String?
                    if let inlineModel = object["model"] as? String, !inlineModel.isEmpty {
                        let normalized = normalizeAntigravityModel(inlineModel)
                        stepModel = normalized
                        currentModel = normalized
                    } else {
                        stepModel = currentModel
                    }

                    if inputTokens == 0 && outputTokens == 0 && cacheRead == 0 {
                        if cachedUsages == nil {
                            if lazyCacheIndex == nil {
                                lazyCacheIndex = buildAntigravityCacheIndex()
                            }
                            cachedUsages = loadCachedAntigravityUsages(from: lazyCacheIndex?[sessionId])
                        }
                        if let usages = cachedUsages, !usages.isEmpty {
                            let matchedUsage = stepIdx < usages.count ? usages[stepIdx] : usages.last!
                            if matchedUsage.tokens.total > 0 {
                                tokens = matchedUsage.tokens
                            }
                            if stepModel == nil, let cachedModel = matchedUsage.modelId {
                                stepModel = normalizeAntigravityModel(cachedModel)
                            }
                        }

                        if tokens.total == 0 {
                            let contentStr = object["content"] as? String ?? ""
                            let toolCallsCount = (object["tool_calls"] as? [Any])?.count ?? 0
                            let estOutput = Int64((contentStr.count + toolCallsCount * 150) / 3)
                            tokens = TokenBreakdown(
                                input: 1000,
                                output: estOutput,
                                cacheRead: 0,
                                cacheWrite: 0,
                                reasoning: reasoningTokens
                            )
                        }
                    } else if stepModel == nil {
                        if cachedUsages == nil {
                            if lazyCacheIndex == nil {
                                lazyCacheIndex = buildAntigravityCacheIndex()
                            }
                            cachedUsages = loadCachedAntigravityUsages(from: lazyCacheIndex?[sessionId])
                        }
                        if let usages = cachedUsages, stepIdx < usages.count, let cachedModel = usages[stepIdx].modelId {
                            stepModel = normalizeAntigravityModel(cachedModel)
                        }
                    }

                    if tokens.total > 0 {
                        let resolvedModel = stepModel ?? "gemini-3.8-flash"
                        var modelsForDay = sessionTokens[stepDayKey, default: [:]]
                        modelsForDay[resolvedModel, default: TokenBreakdown()] =
                            modelsForDay[resolvedModel, default: TokenBreakdown()] + tokens
                        sessionTokens[stepDayKey] = modelsForDay
                    }
                }

                var sessionRecords: [NativeSessionRecord] = []
                for (dKey, models) in sessionTokens {
                    for (mName, tok) in models {
                        sessionRecords.append(NativeSessionRecord(dateKey: dKey, model: mName, tokens: tok))
                        if dKey >= earliestDayKey {
                            record(tok, agent: target.agent, model: mName, dateKey: dKey, into: &accumulators)
                        }
                    }
                }
                NativeAntigravityCache.shared.set(
                    path: filePath,
                    modificationDate: mtime,
                    fileSize: UInt64(size),
                    records: sessionRecords
                )
            }
        }

        NativeAntigravityCache.shared.flushToDiskIfNeeded(activePaths: activePaths)
    }

    /// 从日志上下文字符串中提取切换的模型名
    private static func extractModelSelection(from text: String) -> String? {
        guard text.contains("<USER_SETTINGS_CHANGE>") else { return nil }
        guard let range = text.range(of: "`Model Selection` from ") else { return nil }
        let afterFrom = text[range.upperBound...]
        guard let toRange = afterFrom.range(of: " to ") else { return nil }
        let target = afterFrom[toRange.upperBound...]
        let lineSlice = target.prefix { $0 != "`" && $0 != "\n" && $0 != "\r" }
        let raw: Substring
        if let sentenceEnd = lineSlice.range(of: ". ") {
            raw = lineSlice[..<sentenceEnd.lowerBound]
        } else if lineSlice.hasSuffix(".") {
            raw = lineSlice.dropLast()
        } else {
            raw = lineSlice
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 50 else { return nil }
        let disallowedCharacters = CharacterSet(charactersIn: "{}[]<>;\\\"")
        guard trimmed.rangeOfCharacter(from: disallowedCharacters) == nil else { return nil }
        return trimmed
    }

    /// 归一化 Antigravity / Agy CLI 的模型标识
    private static func normalizeAntigravityModel(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return "gemini-3.8-flash" }
        let lower = model.lowercased()
        if lower.contains("placeholder") || lower == "gemini-default" || lower == "none" {
            return "gemini-3.8-flash"
        }
        if lower.contains("4") && lower.contains("argon") { return "gemini-4-argon" }
        if lower.contains("4") && lower.contains("pro") && lower.contains("gemini") { return "gemini-4-pro" }
        if lower.contains("4") && lower.contains("flash") && lower.contains("gemini") { return "gemini-4-flash" }
        if lower.contains("3.8") && lower.contains("flash") { return "gemini-3.8-flash" }
        if lower.contains("3.7") && lower.contains("flash") { return "gemini-3.7-flash" }
        if lower.contains("3.6") && lower.contains("flash") { return "gemini-3.6-flash" }
        if lower.contains("3.5") && lower.contains("flash") { return "gemini-3.5-flash" }
        if lower.contains("3.1") && lower.contains("pro") { return "gemini-3.1-pro" }
        if lower.contains("3") && lower.contains("flash") { return "gemini-3-flash" }
        if lower.contains("sonnet") { return "claude-sonnet-4-6" }
        if lower.contains("opus") { return "claude-opus-4-6" }
        if lower.contains("haiku") { return "claude-haiku-4-5" }

        var cleaned = lower
        if let parenIndex = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[..<parenIndex])
        }
        let slug = cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ".")))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "gemini-3.8-flash" : slug
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
        dateKey: String,
        into accumulators: inout [String: DayAccumulator]
    ) {
        var day = accumulators[dateKey, default: DayAccumulator()]
        day.tokens = day.tokens + tokens
        day.agents[agent, default: TokenBreakdown()] = day.agents[agent, default: TokenBreakdown()] + tokens
        day.models[agent, default: [:]][model, default: TokenBreakdown()] =
            day.models[agent, default: [:]][model, default: TokenBreakdown()] + tokens
        accumulators[dateKey] = day
    }

    private static func record(
        _ tokens: TokenBreakdown,
        agent: String,
        model: String,
        date: Date,
        into accumulators: inout [String: DayAccumulator]
    ) {
        record(tokens, agent: agent, model: model, dateKey: dayKey(for: date), into: &accumulators)
    }

    private static func makeSnapshot(
        from accumulators: [String: DayAccumulator],
        source: TokenUsageSnapshot.Source
    ) -> TokenUsageSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [DailyTokenUsage] = []
        days.reserveCapacity(30)

        for offset in (-29)...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = dayKey(for: date)
            let value = accumulators[key] ?? DayAccumulator()
            let agents = value.agents.map { agent, tokens in
                let models = (value.models[agent] ?? [:])
                    .map { ModelTokenUsage(name: $0.key, tokens: $0.value) }
                    .sorted { $0.tokens.total > $1.tokens.total }
                var usage = AgentTokenUsage(
                    agent: agent,
                    tokens: tokens,
                    models: models,
                    estimatedCost: value.agentCosts[agent]
                )
                if usage.estimatedCost == nil && usage.tokens.total > 0 {
                    let estimated = estimateAgentCost(usage)
                    usage.estimatedCost = estimated > 0 ? estimated : nil
                }
                return usage
            }
            .sorted { $0.tokens.total > $1.tokens.total }

            let dayCost: Double?
            if let cost = value.estimatedCost {
                dayCost = cost
            } else if !agents.isEmpty {
                let sum = agents.reduce(0.0) { partial, ag in
                    partial + (ag.estimatedCost ?? estimateAgentCost(ag))
                }
                dayCost = sum > 0 ? sum : nil
            } else {
                dayCost = nil
            }

            days.append(
                DailyTokenUsage(
                    dateKey: key,
                    tokens: value.tokens,
                    agents: agents,
                    estimatedCost: dayCost
                )
            )
        }

        return TokenUsageSnapshot(days: days, source: source, generatedAt: Date())
    }

    private static func recentFiles(
        at root: URL,
        extension fileExtension: String,
        since date: Date,
        maxSizeBytes: Int64 = 150 * 1024 * 1024
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
        return ExecutableLocator.shared.locateFile(
            "usage-collector",
            candidates: candidates,
            requireExecutable: true
        )
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

    /// 利用 Swift static let 原生线程安全懒加载（dispatch_once），整个进程生命周期仅初始化一次存储目录
    private static let preparedStorageURL: URL = {
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
    }()

    private static func prepareUsageCollectorStorage() -> URL {
        preparedStorageURL
    }

    /// 检查是否需要执行首次 antigravity-cache 回退缓存初始化
    private static func shouldPerformInitialAntigravityCacheSync() -> Bool {
        let manifestURL = prepareUsageCollectorStorage()
            .appendingPathComponent("antigravity-cache/manifest.json", isDirectory: false)
        return !FileManager.default.fileExists(atPath: manifestURL.path)
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
            environment["TOKSCALE_NATIVE_TIMEOUT_MS"] = "15000"
            // 强制使用本地定价缓存，防止在弱网环境下每次请求 GitHub LiteLLM JSON 失败重试卡死 30+ 秒
            environment["TOKSCALE_PRICING_CACHE_ONLY"] = "yes"
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

    private final class DateFormatters: @unchecked Sendable {
        static let shared = DateFormatters()
        private let lock = NSLock()
        private let isoWithFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        private let isoBasic = ISO8601DateFormatter()
        private let dayKeyFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        func parseISO(_ value: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            return isoWithFractional.date(from: value) ?? isoBasic.date(from: value)
        }

        func dayKey(for date: Date) -> String {
            lock.lock()
            defer { lock.unlock() }
            return dayKeyFormatter.string(from: date)
        }
    }

    private static func parseISODate(_ value: String) -> Date? {
        DateFormatters.shared.parseISO(value)
    }

    private static func dayKey(for date: Date) -> String {
        DateFormatters.shared.dayKey(for: date)
    }

    /// 极速从 ISO8601 时间戳中提取 "yyyy-MM-dd"，纳秒级无分配
    private static func extractDayKey(from timestamp: String) -> String? {
        guard timestamp.utf8.count >= 10 else { return nil }
        let prefix = timestamp.prefix(10)
        var index = prefix.utf8.startIndex
        for pos in 0..<10 {
            let byte = prefix.utf8[index]
            if pos == 4 || pos == 7 {
                guard byte == UInt8(ascii: "-") else { return nil }
            } else {
                guard byte >= 48 && byte <= 57 else { return nil }
            }
            prefix.utf8.formIndex(after: &index)
        }
        return String(prefix)
    }
}

/// 线程安全的共享十进制数字格式化器，避免每次调用 formattedWithSeparators 都实例化 NumberFormatter
private final class SharedDecimalNumberFormatter: @unchecked Sendable {
    static let shared = SharedDecimalNumberFormatter()
    private let lock = NSLock()
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    func string(from value: Int64) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

extension Int64 {
    var tokenText: String {
        let value = Double(Swift.max(0, self))
        switch value {
        case 1_000_000_000...:
            return String(format: value >= 10_000_000_000 ? "%.0fB" : "%.1fB", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: value >= 100_000 ? "%.0fK" : "%.1fK", value / 1_000)
        default:
            return "\(self)"
        }
    }

    var formattedWithSeparators: String {
        SharedDecimalNumberFormatter.shared.string(from: self)
    }
}

extension Double {
    var estimatedCostText: String {
        let value = Swift.max(0, self)
        return String(format: value > 0 && value < 0.01 ? "$%.3f" : "$%.2f", value)
    }
}
