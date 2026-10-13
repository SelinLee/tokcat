import Foundation

/// On-demand, file-only history. Retains compact counters, never conversation bodies.
/// Reads are serialized by a lock, including access to the compact file cache.
public final class CodexQuotaHistoryReader: @unchecked Sendable {
    private let lock = NSLock()
    private struct FileCache {
        var size: Int
        var modified: Date
        var samples: [QuotaObservation]
    }
    private let directories: [URL]
    private var cache: [String: FileCache] = [:]
    public init(directories: [URL] = CodexLocalUsageReader.defaultDirectories()) { self.directories = directories }

    public func read(in interval: DateInterval) throws -> [QuotaEfficiencyDay] {
        lock.lock()
        defer { lock.unlock() }
        var observations: [QuotaObservation] = []
        var seen = Set<String>()
        for directory in directories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            var enumerationError: Error?
            guard let files = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles], errorHandler: { _, error in enumerationError = error; return false }) else { continue }
            for case let url as URL in files where url.pathExtension == "jsonl" {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true, let size = values.fileSize, let modified = values.contentModificationDate else { continue }
                seen.insert(url.path)
                // A file older than the range cannot contain newer local observations.
                guard modified >= interval.start else { continue }
                let entry: FileCache
                if let saved = cache[url.path], saved.size == size, saved.modified == modified { entry = saved }
                else {
                    entry = FileCache(size: size, modified: modified, samples: try readFile(url))
                    cache[url.path] = entry
                }
                observations += entry.samples.filter { $0.date >= interval.start && $0.date < interval.end }
            }
            if let enumerationError { throw enumerationError }
        }
        cache = cache.filter { seen.contains($0.key) }
        return QuotaEfficiency.daily(observations)
    }

    private func readFile(_ url: URL) throws -> [QuotaObservation] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result: [QuotaObservation] = []
        var pending = Data()
        var discard = false
        var previous: UsageTokenCounts?
        var session = url.deletingPathExtension().lastPathComponent
        var provider: String?
        var model = "未知模型"
        let formatter = ISO8601DateFormatter()
        let plainFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func process(_ data: Data) {
            guard data.range(of: Data("\"token_count\"".utf8)) != nil || data.range(of: Data("\"session_meta\"".utf8)) != nil || data.range(of: Data("\"turn_context\"".utf8)) != nil else { return }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any] else { return }
            if root["type"] as? String == "session_meta" {
                session = payload["id"] as? String ?? session
                provider = payload["model_provider"] as? String
                return
            }
            if root["type"] as? String == "turn_context" {
                if let name = payload["model"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model = ModelNameFormatting.shortDisplayName(name)
                } else { model = "未知模型" }
                return
            }
            guard root["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
                  provider == nil || provider == "openai",
                  let timestamp = root["timestamp"] as? String,
                  let date = formatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp) else { return }
            var delta = UsageTokenCounts()
            if let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] {
                func count(_ key: String) -> Int { max(0, (total[key] as? NSNumber)?.intValue ?? 0) }
                let input = count("input_tokens"), cached = min(input, count("cached_input_tokens"))
                let counts = UsageTokenCounts(input: input - cached, cacheRead: cached, output: count("output_tokens"))
                if let previous, counts.total >= previous.total {
                    delta = counts.delta(from: previous)
                } else if previous == nil, let last = info["last_token_usage"] as? [String: Any],
                          (last["input_tokens"] as? NSNumber)?.intValue == input,
                          (last["output_tokens"] as? NSNumber)?.intValue == counts.output {
                    // A fresh session's first request can count against a global quota baseline.
                    // A resumed/truncated log's lifetime total must never be imported as a delta.
                    delta = counts
                }
                previous = counts
            }
            var windows: [CodexUsageWindowKind: QuotaObservation.Window] = [:]
            let limits = payload["rate_limits"] as? [String: Any]
            if limits?["limit_id"] == nil || limits?["limit_id"] is NSNull || limits?["limit_id"] as? String == "codex" {
                for key in ["primary", "secondary"] {
                    guard let raw = limits?[key] as? [String: Any],
                          let percent = (raw["used_percent"] as? NSNumber)?.doubleValue,
                          let reset = (raw["resets_at"] as? NSNumber)?.doubleValue,
                          let minutes = (raw["window_minutes"] as? NSNumber)?.doubleValue,
                          minutes.isFinite, minutes > 0, minutes <= 525_600, reset.isFinite,
                          let kind = CodexUsageParser.classify(windowSeconds: Int(minutes * 60)) else { continue }
                    windows[kind] = .init(percent: percent, reset: reset, seconds: Int(minutes * 60))
                }
            }
            result.append(.init(date: date, id: "\(session)|\(timestamp)", tokens: delta,
                                windows: windows, plan: limits?["plan_type"] as? String, model: model))
        }
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            for part in chunk.split(separator: 10, omittingEmptySubsequences: false).enumerated() {
                if part.offset > 0 {
                    if !discard { process(pending) }
                    pending.removeAll(keepingCapacity: true); discard = false
                }
                if !discard {
                    if pending.count + part.element.count <= 1_048_576 { pending.append(contentsOf: part.element) }
                    else { pending.removeAll(keepingCapacity: true); discard = true }
                }
            }
        }
        // Ignore an unfinished final record until its newline is written.
        return result
    }
}
