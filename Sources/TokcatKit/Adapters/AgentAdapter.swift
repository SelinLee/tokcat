import Foundation

/// A pluggable reader for a specific AI coding agent's local usage data.
/// Each conforming type owns tracking of what it has already read so
/// repeated calls to `pollNewEvents()` only return newly observed events.
public protocol AgentAdapter: AnyObject {
    var source: AgentSource { get }
    var currentOffsets: [String: UInt64] { get }
    /// Hot path: recent / live token usage only. Must stay cheap.
    func pollNewEvents() -> [TokenEvent]
    /// Optional cold path: slowly resume historical logs in small batches.
    /// Returns events found in this batch (usually empty when bootstrap is on).
    func pollHistoricalBatch(maxFiles: Int) -> [TokenEvent]
    /// Offsets changed since the previous drain. Used for cheap SQLite checkpoints.
    func drainDirtyOffsets() -> [String: UInt64]
    func updatePricingTable(_ table: PricingTable)
}

public extension AgentAdapter {
    func updatePricingTable(_ table: PricingTable) {
        // Optional for adapters that don't price locally.
    }

    func pollHistoricalBatch(maxFiles: Int) -> [TokenEvent] {
        _ = maxFiles
        return []
    }

    func drainDirtyOffsets() -> [String: UInt64] {
        [:]
    }
}

/// Polls multiple adapters and merges their offset maps for persistence.
public final class CompositeAgentAdapter {
    private var adapters: [AgentAdapter]
    private var enabled: Set<AgentSource>

    public init(adapters: [AgentAdapter], enabled: Set<AgentSource>) {
        self.adapters = adapters
        self.enabled = enabled
    }

    public var sources: [AgentSource] {
        adapters.map(\.source)
    }

    public func setEnabled(_ sources: Set<AgentSource>) {
        enabled = sources
    }

    public func updatePricingTable(_ table: PricingTable) {
        for adapter in adapters {
            adapter.updatePricingTable(table)
        }
    }

    /// Live monitoring path used by the main timer.
    public func pollNewEvents() -> [TokenEvent] {
        var events: [TokenEvent] = []
        for adapter in adapters where enabled.contains(adapter.source) {
            events.append(contentsOf: adapter.pollNewEvents())
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Background resume path for historical logs. Processes a small batch
    /// so callers can checkpoint offsets between rounds.
    @discardableResult
    public func pollHistoricalBatch(maxFilesPerAdapter: Int = 40) -> [TokenEvent] {
        var events: [TokenEvent] = []
        for adapter in adapters where enabled.contains(adapter.source) {
            events.append(contentsOf: adapter.pollHistoricalBatch(maxFiles: maxFilesPerAdapter))
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Cheap checkpoint payload: only keys mutated since last drain.
    public func drainDirtyOffsets() -> [String: UInt64] {
        var merged: [String: UInt64] = [:]
        for adapter in adapters {
            for (path, offset) in adapter.drainDirtyOffsets() {
                merged[path] = max(merged[path] ?? 0, offset)
            }
        }
        return merged
    }

    public var currentOffsets: [String: UInt64] {
        var merged: [String: UInt64] = [:]
        for adapter in adapters {
            for (path, offset) in adapter.currentOffsets {
                merged[path] = max(merged[path] ?? 0, offset)
            }
        }
        return merged
    }
}
