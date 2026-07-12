import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(IOKit)
import IOKit
#endif

/// Host-wide resource snapshot used by the menu bar monitor.
public struct SystemMetrics: Sendable, Equatable {
    public var cpuPercent: Double
    public var gpuPercent: Double
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var networkInBytesPerSecond: Double
    public var networkOutBytesPerSecond: Double
    public var thermalState: ThermalPressure
    public var sampledAt: Date

    public init(
        cpuPercent: Double = 0,
        gpuPercent: Double = 0,
        memoryUsedBytes: UInt64 = 0,
        memoryTotalBytes: UInt64 = 0,
        networkInBytesPerSecond: Double = 0,
        networkOutBytesPerSecond: Double = 0,
        thermalState: ThermalPressure = .nominal,
        sampledAt: Date = Date()
    ) {
        self.cpuPercent = cpuPercent
        self.gpuPercent = gpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.networkInBytesPerSecond = networkInBytesPerSecond
        self.networkOutBytesPerSecond = networkOutBytesPerSecond
        self.thermalState = thermalState
        self.sampledAt = sampledAt
    }

    public var memoryUsedPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(100, (Double(memoryUsedBytes) / Double(memoryTotalBytes)) * 100)
    }
}

/// Coarse thermal pressure derived from `ProcessInfo.thermalState`.
/// Real die temperature needs SMC private APIs; this is the supported public signal.
public enum ThermalPressure: String, Sendable, Codable, CaseIterable, Equatable {
    case nominal
    case fair
    case serious
    case critical

    public var displayName: String {
        switch self {
        case .nominal: return "正常"
        case .fair: return "偏高"
        case .serious: return "较高"
        case .critical: return "严重"
        }
    }

    public init(processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

/// Polls whole-machine CPU, GPU, memory, network throughput, and thermal pressure.
public final class SystemMetricsMonitor {
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (inbound: UInt64, outbound: UInt64, sampledAt: Date)?
    private var previousGPUBusy: (value: Double, sampledAt: Date)?

    public init() {}

    public func poll() -> SystemMetrics {
        let now = Date()
        let network = sampleNetworkRates(now: now)
        return SystemMetrics(
            cpuPercent: sampleCPUPercent(),
            gpuPercent: sampleGPUPercent(now: now),
            memoryUsedBytes: sampleMemoryUsedBytes(),
            memoryTotalBytes: sampleMemoryTotalBytes(),
            networkInBytesPerSecond: network.inbound,
            networkOutBytesPerSecond: network.outbound,
            thermalState: ThermalPressure(processInfoState: ProcessInfo.processInfo.thermalState),
            sampledAt: now
        )
    }

    // MARK: - CPU

    private func sampleCPUPercent() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for cpu in 0..<Int(numCpus) {
            let offset = Int(CPU_STATE_MAX) * cpu
            user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }

        defer { previousCPUTicks = (user, system, idle, nice) }

        guard let previous = previousCPUTicks else { return 0 }

        let userDelta = user &- previous.user
        let systemDelta = system &- previous.system
        let idleDelta = idle &- previous.idle
        let niceDelta = nice &- previous.nice
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return 0 }

        let busy = userDelta + systemDelta + niceDelta
        return min(100, (Double(busy) / Double(totalDelta)) * 100)
    }

    // MARK: - GPU

    /// Best-effort GPU utilization via IOKit accelerator "PerformanceStatistics".
    /// Not every Mac exposes Device Utilization %; returns 0 when unavailable.
    private func sampleGPUPercent(now: Date) -> Double {
        #if canImport(IOKit)
        guard let matching = IOServiceMatching("IOAccelerator") else { return 0 }

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var best: Double = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any]
            else { continue }

            if let stats = dict["PerformanceStatistics"] as? [String: Any] {
                // Common keys across Apple/Intel/AMD accelerators.
                let keys = [
                    "Device Utilization %",
                    "GPU Activity(%)",
                    "Renderer Utilization %",
                    "Tiler Utilization %",
                    "hardwareWaitTime"
                ]
                for key in keys {
                    if let number = stats[key] as? NSNumber {
                        let value = number.doubleValue
                        // hardwareWaitTime is not a percent; skip non-percent-like values later.
                        if key == "hardwareWaitTime" { continue }
                        if value.isFinite {
                            best = max(best, min(100, max(0, value)))
                        }
                    }
                }

                // Some drivers report Device Utilization as 0–1.
                if best == 0, let number = stats["Device Utilization %"] as? NSNumber {
                    let value = number.doubleValue
                    if value > 0, value <= 1 {
                        best = max(best, value * 100)
                    }
                }
            }
        }

        previousGPUBusy = (best, now)
        return best
        #else
        return 0
        #endif
    }

    // MARK: - Memory

    private func sampleMemoryTotalBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    private func sampleMemoryUsedBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }

        let usedPages =
            UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return usedPages * UInt64(pageSize)
    }

    // MARK: - Network

    private func sampleNetworkRates(now: Date) -> (inbound: Double, outbound: Double) {
        let counters = interfaceByteCounters()
        defer { previousNetwork = (counters.inbound, counters.outbound, now) }

        guard let previous = previousNetwork else { return (0, 0) }
        let elapsed = now.timeIntervalSince(previous.sampledAt)
        guard elapsed > 0 else { return (0, 0) }

        let inboundDelta = Double(counters.inbound &- previous.inbound)
        let outboundDelta = Double(counters.outbound &- previous.outbound)
        return (
            max(0, inboundDelta / elapsed),
            max(0, outboundDelta / elapsed)
        )
    }

    private func interfaceByteCounters() -> (inbound: UInt64, outbound: UInt64) {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return (0, 0)
        }
        defer { freeifaddrs(first) }

        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = current {
            defer { current = interface.pointee.ifa_next }

            let name = String(cString: interface.pointee.ifa_name)
            if name == "lo0" { continue }

            guard let addr = interface.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK)
            else { continue }

            if let raw = interface.pointee.ifa_data {
                let data = raw.assumingMemoryBound(to: if_data.self)
                inbound += UInt64(data.pointee.ifi_ibytes)
                outbound += UInt64(data.pointee.ifi_obytes)
            }
        }

        return (inbound, outbound)
    }
}
