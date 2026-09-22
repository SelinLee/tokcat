import Foundation

/// Read Codex's own conversation names; never derive titles from private message bodies.
public final class CodexSessionTitleReader {
    private let url: URL
    private var signature: String?
    private var cached: [String: String] = [:]

    public init(url: URL) { self.url = url }

    public func read() -> [String: String] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return cached }
        let next = "\(size):\(modified.timeIntervalSince1970)"
        guard signature != next else { return cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return cached }
        defer { try? handle.close() }
        let start = size > 2_097_152 ? size - 2_097_152 : 0
        do {
            try handle.seek(toOffset: start)
            let data = try handle.read(upToCount: 2_097_152) ?? Data()
            // Ignore a partial trailing line and retry it after the writer finishes.
            guard let end = data.lastIndex(of: 10) else { return cached }
            var lines = data.prefix(through: end).split(separator: 10)
            if start > 0 && !lines.isEmpty { lines.removeFirst() }
            var titles: [String: String] = [:]
            for line in lines {
                guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let id = row["id"] as? String, let raw = row["thread_name"] as? String else { continue }
                let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { titles[id] = String(title.prefix(200)) }
            }
            cached = titles
            signature = next
        } catch { return cached }
        return cached
    }
}
