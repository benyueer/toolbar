import Darwin
import Foundation

struct CPUUsage: Equatable {
    var total = 0.0
    var user = 0.0
    var system = 0.0
    var idle = 1.0
}

struct MemoryUsage: Equatable {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var available: UInt64 = 0
    var compressed: UInt64 = 0
    var swapUsed: UInt64 = 0

    var utilization: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}

struct NetworkUsage: Equatable {
    var downloadBytesPerSecond = 0.0
    var uploadBytesPerSecond = 0.0
}

/// 网卡收发字节计数器（栈上值类型，避免字典与字符串堆分配）
private struct NetworkCounters {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

/// CPU 各状态累计 Tick 数（栈上值类型，避免每次采样分配堆数组）
private struct CPUTicks {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var nice: UInt64 = 0
}

@MainActor
final class SystemMetrics: ObservableObject {
    private let updateInterval: TimeInterval = 1
    private let historyLimit = 180

    // 缓存进程生命周期内不变的内核端口、内存页大小、物理内存总量与 CPU 核心数，避免每秒重复触发系统调用
    private let hostPort: mach_port_t
    private let pageBytes: UInt64
    private let totalPhysicalMemory: UInt64
    let processorDescription: String
    private var swapMIB: [Int32] = []

    // 采样数据与历史曲线
    private(set) var cpu = CPUUsage()
    private(set) var memory = MemoryUsage()
    private(set) var network = NetworkUsage()
    private(set) var cpuHistory: [Double]
    private(set) var memoryHistory: [Double]
    private(set) var downloadHistory: [Double]
    private(set) var uploadHistory: [Double]
    private(set) var lastUpdated = Date()

    /// 标记详情弹窗是否可见；弹窗关闭时不触发 SwiftUI objectWillChange 广播以降低后台能耗
    var isDashboardVisible = false

    /// 每次采样完成后的轻量主线程回调（用于直接触发状态栏脏检查与绘制）
    var onMetricsUpdated: (() -> Void)?

    private var previousCPUTicks: CPUTicks?
    private var previousNetworkCounters: NetworkCounters?
    private var previousNetworkSampleTime: TimeInterval?
    nonisolated(unsafe) private var timer: Timer?

    init() {
        let port = mach_host_self()
        self.hostPort = port
        self.totalPhysicalMemory = ProcessInfo.processInfo.physicalMemory
        self.processorDescription = "\(ProcessInfo.processInfo.processorCount) 核心"

        var vmPageSize: vm_size_t = 0
        if host_page_size(port, &vmPageSize) == KERN_SUCCESS, vmPageSize > 0 {
            self.pageBytes = UInt64(vmPageSize)
        } else {
            self.pageBytes = UInt64(max(getpagesize(), 4096))
        }

        // 预解析 vm.swapusage 的 sysctl MIB，避免每秒通过字符串查找内核节点
        var mib = [Int32](repeating: 0, count: 4)
        var mibLength = mib.count
        if sysctlnametomib("vm.swapusage", &mib, &mibLength) == 0 {
            self.swapMIB = Array(mib.prefix(mibLength))
        }

        var initialCPU = Array(repeating: 0.0, count: historyLimit)
        initialCPU.reserveCapacity(historyLimit + 1)
        var initialMem = Array(repeating: 0.0, count: historyLimit)
        initialMem.reserveCapacity(historyLimit + 1)
        var initialDown = Array(repeating: 0.0, count: historyLimit)
        initialDown.reserveCapacity(historyLimit + 1)
        var initialUp = Array(repeating: 0.0, count: historyLimit)
        initialUp.reserveCapacity(historyLimit + 1)

        self.cpuHistory = initialCPU
        self.memoryHistory = initialMem
        self.downloadHistory = initialDown
        self.uploadHistory = initialUp

        refresh()

        // 在主线程默认 RunLoop 模式下调度，并设置 20% tolerance 允许系统内核合并定时器唤醒（Timer Coalescing）
        let scheduledTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        scheduledTimer.tolerance = 0.2
        self.timer = scheduledTimer
    }

    deinit {
        timer?.invalidate()
        if hostPort != MACH_PORT_NULL {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
    }

    func refresh() {
        let nextCPU = readCPUUsage()
        let nextMemory = readMemoryUsage()
        let nextNetwork = readNetworkUsage(at: ProcessInfo.processInfo.systemUptime)

        // 仅在弹窗可见时通知 SwiftUI 刷新详情视图，后台驻留时零 Combine 广播开销
        if isDashboardVisible {
            objectWillChange.send()
        }

        cpu = nextCPU
        memory = nextMemory
        network = nextNetwork
        append(nextCPU.total, to: &cpuHistory)
        append(nextMemory.utilization, to: &memoryHistory)
        append(nextNetwork.downloadBytesPerSecond, to: &downloadHistory)
        append(nextNetwork.uploadBytesPerSecond, to: &uploadHistory)
        lastUpdated = Date()

        onMetricsUpdated?()
    }

    var uptimeText: String {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let days = uptime / 86_400
        let hours = (uptime % 86_400) / 3_600
        let minutes = (uptime % 3_600) / 60

        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        return "\(minutes) 分钟"
    }

    private func append(_ value: Double, to history: inout [Double]) {
        if history.count >= historyLimit {
            history.removeFirst(history.count - historyLimit + 1)
        }
        history.append(value)
    }

    private func readNetworkUsage(at sampleTime: TimeInterval) -> NetworkUsage {
        guard let currentCounters = readNetworkCounters() else {
            return network
        }

        defer {
            previousNetworkCounters = currentCounters
            previousNetworkSampleTime = sampleTime
        }

        guard
            let previous = previousNetworkCounters,
            let previousSampleTime = previousNetworkSampleTime,
            sampleTime > previousSampleTime
        else {
            return NetworkUsage()
        }

        let receivedDelta: UInt64 = currentCounters.receivedBytes >= previous.receivedBytes
            ? currentCounters.receivedBytes - previous.receivedBytes
            : 0
        let sentDelta: UInt64 = currentCounters.sentBytes >= previous.sentBytes
            ? currentCounters.sentBytes - previous.sentBytes
            : 0

        let elapsed = sampleTime - previousSampleTime
        return NetworkUsage(
            downloadBytesPerSecond: Double(receivedDelta) / elapsed,
            uploadBytesPerSecond: Double(sentDelta) / elapsed
        )
    }

    /// 零堆分配读取 en0 网卡收发字节数
    private func readNetworkCounters() -> NetworkCounters? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }
        defer { freeifaddrs(firstAddress) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interfacePointer = pointer {
            let interface = interfacePointer.pointee
            pointer = interface.ifa_next

            guard
                let address = interface.ifa_addr,
                Int32(address.pointee.sa_family) == AF_LINK,
                interface.ifa_flags & UInt32(IFF_UP) != 0,
                interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                let rawData = interface.ifa_data,
                let ifaName = interface.ifa_name
            else {
                continue
            }

            // 直接比较 C 字符串 "en0\0"，避免每次遍历几十个虚拟网卡时产生 String 堆分配
            guard
                ifaName[0] == 0x65, // 'e'
                ifaName[1] == 0x6E, // 'n'
                ifaName[2] == 0x30, // '0'
                ifaName[3] == 0
            else {
                continue
            }

            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            return NetworkCounters(
                receivedBytes: UInt64(data.ifi_ibytes),
                sentBytes: UInt64(data.ifi_obytes)
            )
        }

        return nil
    }

    /// 零堆分配读取全核 CPU 负载
    private func readCPUUsage() -> CPUUsage {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return cpu
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let buffer = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        let stateMax = Int(CPU_STATE_MAX)
        let userIdx = Int(CPU_STATE_USER)
        let systemIdx = Int(CPU_STATE_SYSTEM)
        let idleIdx = Int(CPU_STATE_IDLE)
        let niceIdx = Int(CPU_STATE_NICE)

        var current = CPUTicks()
        for core in 0..<Int(cpuCount) {
            let offset = core * stateMax
            current.user &+= UInt64(buffer[offset + userIdx])
            current.system &+= UInt64(buffer[offset + systemIdx])
            current.idle &+= UInt64(buffer[offset + idleIdx])
            current.nice &+= UInt64(buffer[offset + niceIdx])
        }

        let previous = previousCPUTicks
        previousCPUTicks = current

        let deltaUser: UInt64
        let deltaSystem: UInt64
        let deltaIdle: UInt64
        let deltaNice: UInt64

        if let previous {
            deltaUser = current.user >= previous.user ? current.user - previous.user : current.user
            deltaSystem = current.system >= previous.system ? current.system - previous.system : current.system
            deltaIdle = current.idle >= previous.idle ? current.idle - previous.idle : current.idle
            deltaNice = current.nice >= previous.nice ? current.nice - previous.nice : current.nice
        } else {
            deltaUser = current.user
            deltaSystem = current.system
            deltaIdle = current.idle
            deltaNice = current.nice
        }

        let userTotal = deltaUser + deltaNice
        let total = userTotal + deltaSystem + deltaIdle
        guard total > 0 else { return cpu }

        let totalDouble = Double(total)
        return CPUUsage(
            total: Double(userTotal + deltaSystem) / totalDouble,
            user: Double(userTotal) / totalDouble,
            system: Double(deltaSystem) / totalDouble,
            idle: Double(deltaIdle) / totalDouble
        )
    }

    private func readMemoryUsage() -> MemoryUsage {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(hostPort, HOST_VM_INFO64, rebound, &count)
            }
        }

        let total = totalPhysicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryUsage(total: total, available: total)
        }

        let active = UInt64(statistics.active_count) * pageBytes
        let wired = UInt64(statistics.wire_count) * pageBytes
        let compressed = UInt64(statistics.compressor_page_count) * pageBytes
        let used = min(active + wired + compressed, total)

        return MemoryUsage(
            total: total,
            used: used,
            available: total - used,
            compressed: compressed,
            swapUsed: readSwapUsed()
        )
    }

    private func readSwapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if !swapMIB.isEmpty {
            let result = swapMIB.withUnsafeBufferPointer { mibBuffer -> Int32 in
                guard let baseAddress = mibBuffer.baseAddress else { return -1 }
                return sysctl(
                    UnsafeMutablePointer(mutating: baseAddress),
                    u_int(mibBuffer.count),
                    &usage,
                    &size,
                    nil,
                    0
                )
            }
            if result == 0 {
                return usage.xsu_used
            }
        }
        let fallbackResult = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        return fallbackResult == 0 ? usage.xsu_used : 0
    }
}

extension Double {
    var percentText: String {
        "\(Int((min(max(self, 0), 1) * 100).rounded()))%"
    }

    var speedText: String {
        let bytes = max(self, 0)
        if bytes < 1_000 {
            return "\(Int(bytes.rounded())) B/s"
        }

        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var scaled = bytes
        var unitIndex = 0

        while scaled >= 1_000, unitIndex < units.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }

        let format = scaled >= 100 ? "%.0f %@" : scaled >= 10 ? "%.1f %@" : "%.2f %@"
        return String(format: format, scaled, units[unitIndex])
    }
}

/// 线程安全的共享 ByteCountFormatter，避免每次格式化都新建 NSByteCountFormatter 实例
private final class SharedByteCountFormatter: @unchecked Sendable {
    static let shared = SharedByteCountFormatter()
    private let lock = NSLock()
    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    func string(fromByteCount count: Int64) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(fromByteCount: count)
    }
}

extension UInt64 {
    var byteText: String {
        SharedByteCountFormatter.shared.string(fromByteCount: Int64(clamping: self))
    }
}
