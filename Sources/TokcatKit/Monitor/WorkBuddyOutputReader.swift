import Foundation

/// Replays only output counters and user-turn boundaries from a bounded log tail.
/// WorkBuddy writes usage on assistant messages AND tool calls, often after the
/// corresponding streaming row, and repeats it in several provider formats.
final class WorkBuddyOutputReader {
    private struct Cached {
        var size: UInt64
        var modifiedAt: Date
        var rate: SessionOutputRate?
    }
    private var cache: [String: Cached] = [:]
    private let maxBytes: UInt64 = 2_097_152

    func read(url: URL, sessionID: String) -> SessionOutputRate? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modifiedAt = attributes[.modificationDate] as? Date else { return nil }
        if let old = cache[url.path], old.size == size, old.modifiedAt == modifiedAt { return old.rate }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let start = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(maxBytes)) else { return nil }
        let rate = Self.parse(data, sessionID: sessionID, skipsFirstLine: start > 0)
        cache[url.path] = Cached(size: size, modifiedAt: modifiedAt, rate: rate)
        return rate
    }

    private struct Observation {
        var at: Date
        var requestID: String?
        /// nil is an explicit user-turn boundary; zero is valid output usage.
        var output: Int?
    }

    private static func parse(_ data: Data, sessionID: String, skipsFirstLine: Bool) -> SessionOutputRate? {
        var observations: [String: Observation] = [:]
        var cursor = 0
        for end in data.indices where data[end] == 10 {
            defer { cursor = end + 1 }
            if skipsFirstLine && cursor == 0 { continue }
            guard let row = try? JSONSerialization.jsonObject(with: data.subdata(in: cursor..<end)) as? [String: Any],
                  (row["sessionId"] as? String).map({ $0 == sessionID }) ?? true,
                  let at = timestamp(row["timestamp"]) else { continue }
            let kind = row["type"] as? String
            let provider = row["providerData"] as? [String: Any]
            let requestID = provider?["conversationRequestId"] as? String
            let rowID = row["id"] as? String ?? String(cursor)
            if kind == "message", row["role"] as? String == "user" {
                observations["user:" + rowID] = Observation(at: at, requestID: requestID, output: nil)
                continue
            }
            // Reasoning and tool results can repeat provider metadata. Their
            // tokens are already included in the model response's output count.
            guard kind == "function_call" || (kind == "message" && row["role"] as? String == "assistant") else { continue }
            let message = row["message"] as? [String: Any]
            let usage = message?["usage"] as? [String: Any]
            let providerUsage = provider?["usage"] as? [String: Any]
            let rawUsage = provider?["rawUsage"] as? [String: Any]
            guard let output = (usage?["output_tokens"] ?? providerUsage?["outputTokens"]
                ?? rawUsage?["completion_tokens"]) as? Int, output >= 0 else { continue }
            let id = provider?["messageId"] as? String ?? rowID
            // Parallel tool calls may share one model response; streaming
            // replacements must replace that response's usage, never add it.
            observations["output:" + id] = Observation(at: at, requestID: requestID, output: output)
        }

        var rate: SessionOutputRate?
        var requestID: String?
        var total = 0
        for (_, observation) in observations.sorted(by: {
            if $0.value.at != $1.value.at { return $0.value.at < $1.value.at }
            if ($0.value.output == nil) != ($1.value.output == nil) { return $0.value.output == nil }
            return $0.key < $1.key
        }) {
            if observation.output == nil {
                rate = SessionOutputRate()
                total = 0
                requestID = observation.requestID
                rate?.observe(total: 0, scope: "output", at: observation.at, turnStart: nil)
            } else if let output = observation.output {
                if let incoming = observation.requestID, let previous = requestID, incoming != previous {
                    rate = nil
                    total = 0
                }
                requestID = observation.requestID ?? requestID
                total += output
                if rate == nil { rate = SessionOutputRate() }
                // Without a visible turn start, the first output establishes a
                // baseline; older lifetime usage cannot create a speed spike.
                rate?.observe(total: total, scope: "output", at: observation.at, turnStart: nil)
            }
        }
        return rate
    }

    private static func timestamp(_ value: Any?) -> Date? {
        if let ms = value as? NSNumber, ms.doubleValue.isFinite {
            return Date(timeIntervalSince1970: ms.doubleValue / 1000)
        }
        return AgentDateParsing.parseISO8601(value as? String)
    }
}
