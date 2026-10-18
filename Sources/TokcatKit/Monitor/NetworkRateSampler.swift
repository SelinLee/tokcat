import Foundation
import Darwin

/// An administrative change also starts a fresh baseline, even if an interface
/// index is reused and its new counters happen to be larger than the old ones.
struct NetworkInterfaceID: Hashable {
    var index: UInt16
    var changedAtSeconds: Int32 = 0
    var changedAtMicroseconds: Int32 = 0
}

struct NetworkByteCounters {
    var inbound: UInt64
    var outbound: UInt64
}

struct NetworkRateSampler {
    private var previous: (counters: [NetworkInterfaceID: NetworkByteCounters], time: TimeInterval)?
    private var smoothed: (inbound: Double, outbound: Double)?

    /// `time` must come from a monotonic clock, not a wall-clock Date.
    /// nil means the read failed; an empty dictionary means no interfaces.
    mutating func sample(
        counters: [NetworkInterfaceID: NetworkByteCounters]?,
        at time: TimeInterval,
        smoothingTimeConstant: TimeInterval = 1.5
    ) -> (inbound: Double, outbound: Double) {
        guard let counters, time.isFinite else {
            self = NetworkRateSampler()
            return (0, 0)
        }
        guard let previous else {
            self.previous = (counters, time)
            return (0, 0)
        }
        let elapsed = time - previous.time
        // Ignore duplicate/out-of-order samples without advancing the baseline.
        guard elapsed > 0 else { return smoothed ?? (0, 0) }
        self.previous = (counters, time)

        var inbound: Double = 0
        var outbound: Double = 0
        var discontinuity = counters.keys.contains { previous.counters[$0] == nil }
            || previous.counters.keys.contains { counters[$0] == nil }
        for (id, current) in counters {
            // A newly appearing interface's lifetime bytes are not new traffic.
            guard let old = previous.counters[id] else { continue }
            guard current.inbound >= old.inbound, current.outbound >= old.outbound else {
                // Reset/wrap: rebase this interface while still counting traffic
                // on unaffected interfaces. Never use unsigned wrapping subtraction.
                discontinuity = true
                continue
            }
            inbound += Double(current.inbound - old.inbound) / elapsed
            outbound += Double(current.outbound - old.outbound) / elapsed
        }
        guard inbound.isFinite, outbound.isFinite else {
            smoothed = nil
            return (0, 0)
        }

        if let old = smoothed, !discontinuity {
            let tau = smoothingTimeConstant.isFinite ? max(0.1, smoothingTimeConstant) : 1.5
            let alpha = -expm1(-elapsed / tau)
            smoothed = (old.inbound + alpha * (inbound - old.inbound),
                        old.outbound + alpha * (outbound - old.outbound))
        } else {
            // Do not carry an old tunnel's smoothed rate after it disappears.
            smoothed = (inbound, outbound)
        }
        return smoothed ?? (0, 0)
    }
}

enum NetworkInterfaceReader {
    /// getifaddrs exposes 32-bit byte counts on macOS (wraps every 4 GiB).
    /// NET_RT_IFLIST2 supplies the kernel's 64-bit counters instead.
    static func read() -> [NetworkInterfaceID: NetworkByteCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        // A tunnel can appear between the size query and the actual read.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }
            guard size > 0 else { return [:] }
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes {
                sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0)
            }
            if result != 0 {
                if errno == ENOMEM { continue }
                return nil
            }
            guard size <= data.count else { return nil }
            data.count = size
            return parse(data)
        }
        return nil
    }

    static func parse(_ data: Data) -> [NetworkInterfaceID: NetworkByteCounters]? {
        data.withUnsafeBytes { bytes in
            var counters: [NetworkInterfaceID: NetworkByteCounters] = [:]
            var offset = 0
            while offset < bytes.count {
                // Every routing message starts with length, version and type.
                guard bytes.count - offset >= 4 else { return nil }
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, length <= bytes.count - offset,
                      bytes[offset + 2] == UInt8(RTM_VERSION) else { return nil }
                defer { offset += length }
                guard bytes[offset + 3] == UInt8(RTM_IFINFO2) else { continue }
                guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard message.ifm_flags & IFF_LOOPBACK == 0 else { continue }
                let stats = message.ifm_data
                let id = NetworkInterfaceID(
                    index: message.ifm_index,
                    changedAtSeconds: stats.ifi_lastchange.tv_sec,
                    changedAtMicroseconds: stats.ifi_lastchange.tv_usec
                )
                counters[id] = NetworkByteCounters(inbound: stats.ifi_ibytes, outbound: stats.ifi_obytes)
            }
            return counters
        }
    }
}
