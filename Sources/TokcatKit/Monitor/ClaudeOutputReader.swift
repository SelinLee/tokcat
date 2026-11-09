import Foundation
import CoreFoundation

/// Reconstructs a recent output window without importing conversation text or billing totals.
final class ClaudeOutputReader {
    private struct Cached {
        var sessionID: String
        var size: UInt64
        var modifiedAt: Date
        var since: Date?
        var through: Date?
        var rate: SessionOutputRate?
    }
    private struct Observation {
        var at: Date
        var output: Int?
    }
    private var cache: [String: Cached] = [:]
    private let maxBytes: UInt64 = 2_097_152

    func read(url: URL, sessionID: String, since: Date? = nil, through: Date? = nil) -> SessionOutputRate? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modifiedAt = attributes[.modificationDate] as? Date else { return nil }
        if let old = cache[url.path], old.sessionID == sessionID, old.size == size,
           old.modifiedAt == modifiedAt, old.since == since, old.through == through { return old.rate }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let start = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(maxBytes)) else { return nil }
        var observations: [String: Observation] = [:]
        var cursor = 0
        for end in data.indices where data[end] == 10 {
            defer { cursor = end + 1 }
            if start > 0 && cursor == 0 { continue }
            guard let row = try? JSONSerialization.jsonObject(with: data.subdata(in: cursor..<end)) as? [String: Any],
                  row["isSidechain"] as? Bool != true, row["isMeta"] as? Bool != true,
                  (row["sessionId"] as? String).map({ $0 == sessionID }) ?? true,
                  let at = AgentDateParsing.parseISO8601(row["timestamp"] as? String),
                  since.map({ at >= $0 }) ?? true, through.map({ at <= $0 }) ?? true,
                  let message = row["message"] as? [String: Any] else { continue }
            let id = row["uuid"] as? String ?? String(cursor)
            if row["type"] as? String == "user" {
                let content = message["content"]
                let blocks = content as? [[String: Any]]
                guard row["sourceToolAssistantUUID"] == nil,
                      blocks?.contains(where: { $0["type"] as? String == "tool_result" }) != true,
                      content is String || blocks?.contains(where: {
                          ["text", "image", "document"].contains($0["type"] as? String ?? "")
                      }) == true else { continue }
                observations["user:" + id] = Observation(at: at, output: nil)
            } else if row["type"] as? String == "assistant",
                      let usage = message["usage"] as? [String: Any],
                      let number = usage["output_tokens"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0,
                      number.doubleValue < Double(Int.max),
                      number.doubleValue.rounded(.towardZero) == number.doubleValue {
                let key = "output:" + (message["id"] as? String ?? id)
                let output = number.intValue
                // Content blocks repeat response-wide usage; a trailing zero must not erase it.
                if let old = observations[key], let previous = old.output, previous >= output { continue }
                observations[key] = Observation(at: at, output: output)
            }
        }
        var rate: SessionOutputRate?
        var total = 0
        for (_, observation) in observations.sorted(by: {
            if $0.value.at != $1.value.at { return $0.value.at < $1.value.at }
            if ($0.value.output == nil) != ($1.value.output == nil) { return $0.value.output == nil }
            return $0.key < $1.key
        }) {
            if let output = observation.output {
                let addition = total.addingReportingOverflow(output)
                guard !addition.overflow else { continue }
                total = addition.partialValue
                if rate == nil { rate = SessionOutputRate() }
                rate?.observe(total: total, scope: "claude-output", at: observation.at, turnStart: since)
            } else {
                rate = SessionOutputRate()
                total = 0
                rate?.observe(total: 0, scope: "claude-output", at: observation.at, turnStart: nil)
            }
        }
        cache[url.path] = Cached(sessionID: sessionID, size: size, modifiedAt: modifiedAt,
            since: since, through: through, rate: rate)
        return rate
    }

    func retain(paths: Set<String>) {
        cache = cache.filter { paths.contains($0.key) }
    }
}
