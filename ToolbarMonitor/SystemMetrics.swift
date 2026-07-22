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

private struct NetworkCounters {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

@MainActor
final class SystemMetrics: ObservableObject {
    private let updateInterval: TimeInterval = 1
    private let historyLimit = 180

    @Published private(set) var cpu = CPUUsage()
    @Published private(set) var memory = MemoryUsage()
    @Published private(set) var network = NetworkUsage()
    @Published private(set) var cpuHistory = Array(repeating: 0.0, count: 180)
    @Published private(set) var memoryHistory = Array(repeating: 0.0, count: 180)
    @Published private(set) var downloadHistory = Array(repeating: 0.0, count: 180)
    @Published private(set) var uploadHistory = Array(repeating: 0.0, count: 180)
    @Published private(set) var lastUpdated = Date()

    private var previousCPUTicks: [UInt64]?
    private var previousNetworkCounters: [String: NetworkCounters]?
    private var previousNetworkSampleTime: TimeInterval?
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refresh() {
        cpu = readCPUUsage()
        memory = readMemoryUsage()
        network = readNetworkUsage(at: ProcessInfo.processInfo.systemUptime)
        append(cpu.total, to: &cpuHistory)
        append(memory.utilization, to: &memoryHistory)
        append(network.downloadBytesPerSecond, to: &downloadHistory)
        append(network.uploadBytesPerSecond, to: &uploadHistory)
        lastUpdated = Date()
    }

    var uptimeText: String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let days = Int(uptime) / 86_400
        let hours = (Int(uptime) % 86_400) / 3_600
        let minutes = (Int(uptime) % 3_600) / 60

        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        return "\(minutes) 分钟"
    }

    var processorDescription: String {
        let count = ProcessInfo.processInfo.processorCount
        return "\(count) 核心"
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLimit {
            history.removeFirst()
        }
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
            let previousNetworkCounters,
            let previousNetworkSampleTime,
            sampleTime > previousNetworkSampleTime
        else {
            return NetworkUsage()
        }

        var receivedDelta: UInt64 = 0
        var sentDelta: UInt64 = 0

        for (name, current) in currentCounters {
            guard let previous = previousNetworkCounters[name] else { continue }

            if current.receivedBytes >= previous.receivedBytes {
                receivedDelta += current.receivedBytes - previous.receivedBytes
            }
            if current.sentBytes >= previous.sentBytes {
                sentDelta += current.sentBytes - previous.sentBytes
            }
        }

        let elapsed = sampleTime - previousNetworkSampleTime
        return NetworkUsage(
            downloadBytesPerSecond: Double(receivedDelta) / elapsed,
            uploadBytesPerSecond: Double(sentDelta) / elapsed
        )
    }

    private func readNetworkCounters() -> [String: NetworkCounters]? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }
        defer { freeifaddrs(firstAddress) }

        var counters: [String: NetworkCounters] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interfacePointer = pointer {
            let interface = interfacePointer.pointee
            defer { pointer = interface.ifa_next }

            guard
                let address = interface.ifa_addr,
                Int32(address.pointee.sa_family) == AF_LINK,
                interface.ifa_flags & UInt32(IFF_UP) != 0,
                interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                let rawData = interface.ifa_data
            else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = NetworkCounters(
                receivedBytes: UInt64(data.ifi_ibytes),
                sentBytes: UInt64(data.ifi_obytes)
            )
        }

        return counters
    }

    private func readCPUUsage() -> CPUUsage {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
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
        var current = [UInt64](repeating: 0, count: Int(CPU_STATE_MAX))

        for core in 0..<Int(cpuCount) {
            let offset = core * Int(CPU_STATE_MAX)
            for state in 0..<Int(CPU_STATE_MAX) {
                current[state] += UInt64(buffer[offset + state])
            }
        }

        let previous = previousCPUTicks
        previousCPUTicks = current

        let delta: [UInt64]
        if let previous, previous.count == current.count {
            delta = zip(current, previous).map { now, old in
                now >= old ? now - old : now
            }
        } else {
            delta = current
        }

        let user = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]
        let system = delta[Int(CPU_STATE_SYSTEM)]
        let idle = delta[Int(CPU_STATE_IDLE)]
        let total = user + system + idle

        guard total > 0 else { return cpu }

        return CPUUsage(
            total: Double(user + system) / Double(total),
            user: Double(user) / Double(total),
            system: Double(system) / Double(total),
            idle: Double(idle) / Double(total)
        )
    }

    private func readMemoryUsage() -> MemoryUsage {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryUsage(total: total, available: total)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)

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
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        return result == 0 ? usage.xsu_used : 0
    }
}

extension Double {
    var percentText: String {
        "\(Int((min(max(self, 0), 1) * 100).rounded()))%"
    }

    var speedText: String {
        let bytes = max(self, 0)
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var scaled = bytes
        var unitIndex = 0

        while scaled >= 1_000, unitIndex < units.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(scaled.rounded())) \(units[unitIndex])"
        }

        let format = scaled >= 100 ? "%.0f %@" : scaled >= 10 ? "%.1f %@" : "%.2f %@"
        return String(format: format, scaled, units[unitIndex])
    }
}

extension UInt64 {
    var byteText: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .memory)
    }
}
