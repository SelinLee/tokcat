import Foundation

/// A pluggable reader for a specific AI coding agent's local usage data.
/// Each conforming type owns tracking of what it has already read so
/// repeated calls to `pollNewEvents()` only return newly observed events.
public protocol AgentAdapter {
    var source: AgentSource { get }
    func pollNewEvents() -> [TokenEvent]
}
