import Foundation

/// A task source whose state is written by the agent itself rather than inferred
/// from billing records or transcript volume.
///
/// Readers are polled only when their source is enabled, and `isAvailable == false`
/// means "no local data", never "idle". An available reader is authoritative: its
/// result replaces the session list for that source, so a session it no longer
/// reports is dropped instead of lingering as a stale dot.
protocol ExternalTaskReader: AnyObject {
    var isAvailable: Bool { get }
    /// Sessions the reader recognises but deliberately does not surface, such as a
    /// CLI's internal delegated runs. Records an earlier build wrote for them are
    /// stale and must be dropped rather than kept as tasks.
    var ignoredSessionIDs: Set<String> { get }
    func poll(now: Date) -> [AgentTaskRecord]
}

extension ExternalTaskReader {
    var ignoredSessionIDs: Set<String> { [] }
}
