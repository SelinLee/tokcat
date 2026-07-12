import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Snapshot of one recognized tool's activity at poll time.
public struct ToolActivity: Sendable, Equatable {
    public var tool: KnownTool
    public var pid: Int32
    public var cpuPercent: Double
    public var residentMemoryBytes: UInt64

    public init(tool: KnownTool, pid: Int32, cpuPercent: Double, residentMemoryBytes: UInt64) {
        self.tool = tool
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
    }
}

/// Zero-config Tier 1 monitor: polls all running processes via `libproc`,
/// matches them against `KnownTool.processNameMatches`, and reports a unified
/// activity signal (CPU%, resident memory). Deliberately does not attempt
/// per-process network monitoring — see project plan risk notes.
public final class ProcessMonitor {
    public var knownTools: [KnownTool]

    /// CPU-time samples from the previous poll, keyed by pid, used to compute
    /// CPU% as a delta over the elapsed wall-clock time between polls.
    private var previousCPUTime: [Int32: (totalUserSystemSeconds: Double, sampledAt: Date)] = [:]

    public init(knownTools: [KnownTool] = KnownTool.allDefaults) {
        self.knownTools = knownTools
    }

    /// Lists all currently running pids via `proc_listallpids`.
    private func listAllPIDs() -> [Int32] {
        let initialSize = proc_listallpids(nil, 0)
        guard initialSize > 0 else { return [] }

        // Over-allocate: process count can change between the sizing call and
        // the actual listing call.
        let capacity = Int(initialSize) * 2
        var pids = [Int32](repeating: 0, count: capacity)
        let bytesWritten = proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size))
        guard bytesWritten > 0 else { return [] }

        let count = Int(bytesWritten) / MemoryLayout<Int32>.size
        return Array(pids[0..<count]).filter { $0 > 0 }
    }

    private func processName(pid: Int32) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let result = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard result > 0 else { return nil }
        return String(cString: nameBuffer)
    }

    private func taskInfo(pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return nil }
        return info
    }

    private func matchedTool(forProcessName name: String) -> KnownTool? {
        let lowercased = name.lowercased()
        return knownTools.first { tool in
            tool.processNameMatches.contains { lowercased.contains($0) }
        }
    }

    /// Polls all running processes and returns activity for the ones matching
    /// `knownTools`. Safe to call on a timer; CPU% is computed as the delta
    /// in accumulated CPU time since the previous call, so the first call
    /// after a pid first appears reports 0% (no baseline yet).
    public func pollActivity() -> [ToolActivity] {
        let now = Date()
        var activities: [ToolActivity] = []
        var seenPIDs: Set<Int32> = []

        for pid in listAllPIDs() {
            guard let name = processName(pid: pid), let tool = matchedTool(forProcessName: name) else {
                continue
            }
            guard let info = taskInfo(pid: pid) else { continue }

            seenPIDs.insert(pid)
            let totalCPUSeconds = Double(info.pti_total_user + info.pti_total_system) / 1_000_000_000.0

            var cpuPercent = 0.0
            if let previous = previousCPUTime[pid] {
                let elapsed = now.timeIntervalSince(previous.sampledAt)
                if elapsed > 0 {
                    let cpuDelta = totalCPUSeconds - previous.totalUserSystemSeconds
                    cpuPercent = max(0, min(100, (cpuDelta / elapsed) * 100))
                }
            }
            previousCPUTime[pid] = (totalCPUSeconds, now)

            activities.append(
                ToolActivity(
                    tool: tool,
                    pid: pid,
                    cpuPercent: cpuPercent,
                    residentMemoryBytes: info.pti_resident_size
                )
            )
        }

        // Drop CPU-time baselines for pids that no longer exist, so a reused
        // pid doesn't inherit a stale delta.
        previousCPUTime = previousCPUTime.filter { seenPIDs.contains($0.key) }

        return activities
    }
}
