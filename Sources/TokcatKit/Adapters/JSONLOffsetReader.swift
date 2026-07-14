import Foundation

/// Shared byte-offset JSONL tail reader used by multiple agent adapters.
public final class JSONLOffsetReader {
    public private(set) var readOffsets: [String: UInt64]
    private var dirtyOffsets: [String: UInt64] = [:]
    private let fileManager: FileManager
    /// When true, files never seen before jump to EOF so only newly appended
    /// lines are emitted (avoids one-shot import of huge historical logs).
    public var bootstrapUnknownFilesAtEnd: Bool

    public init(
        initialOffsets: [String: UInt64] = [:],
        fileManager: FileManager = .default,
        bootstrapUnknownFilesAtEnd: Bool = false
    ) {
        var normalized: [String: UInt64] = [:]
        for (path, offset) in initialOffsets {
            normalized[Self.normalizePath(path)] = offset
        }
        self.readOffsets = normalized
        self.fileManager = fileManager
        self.bootstrapUnknownFilesAtEnd = bootstrapUnknownFilesAtEnd
    }

    public var currentOffsets: [String: UInt64] { readOffsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        let pending = dirtyOffsets
        dirtyOffsets.removeAll(keepingCapacity: true)
        return pending
    }

    private func markOffset(_ key: String, _ value: UInt64) {
        readOffsets[key] = value
        dirtyOffsets[key] = value
    }

    public func mergeOffsets(_ offsets: [String: UInt64]) {
        for (path, offset) in offsets {
            let key = Self.normalizePath(path)
            let next = max(readOffsets[key] ?? 0, offset)
            markOffset(key, next)
        }
    }

    /// Returns newly completed lines (without trailing newlines) for `fileURL`.
    public func readNewCompleteLines(from fileURL: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        let path = Self.normalizePath(fileURL.path)
        guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return []
        }
        let size = UInt64(fileSize)

        if readOffsets[path] == nil {
            if bootstrapUnknownFilesAtEnd {
                markOffset(path, size)
                return []
            }
            markOffset(path, 0)
        }

        let startOffset = readOffsets[path] ?? 0
        guard size > startOffset else {
            return []
        }

        try? handle.seek(toOffset: startOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let completeData = data[data.startIndex...lastNewline]
        markOffset(path, startOffset + UInt64(completeData.count))

        return completeData
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .compactMap { slice -> String? in
                guard !slice.isEmpty else { return nil }
                return String(decoding: slice, as: UTF8.self)
            }
    }

    public func enumerateJSONLFiles(
        under root: URL,
        matching pathExtension: String = "jsonl",
        recursive: Bool = true
    ) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        if !recursive {
            let contents = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
            )) ?? []
            return contents.filter { $0.pathExtension == pathExtension }
        }

        var files: [URL] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == pathExtension {
                files.append(fileURL)
            }
        }
        return files
    }

    /// Canonicalize a filesystem path for offset-map keys.
    /// Prefer a cheap standardization pass; only resolve the final path component
    /// style via `standardizingPath` so bulk offset bootstrap stays O(n) and cheap.
    /// Symlink resolution is intentionally avoided here — it was dominating launch
    /// time when thousands of historical WorkBuddy span keys were reloaded.
    public static func normalizePath(_ path: String) -> String {
        if path.isEmpty { return path }
        // Preserve synthetic composite keys used by WorkBuddy (`file#spanId`).
        if let hashIndex = path.firstIndex(of: "#") {
            let filePart = String(path[..<hashIndex])
            let marker = String(path[hashIndex...])
            return (filePart as NSString).standardizingPath + marker
        }
        return (path as NSString).standardizingPath
    }
}

public enum AgentDateParsing {
    public static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoFractional.date(from: raw) ?? isoBasic.date(from: raw)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
