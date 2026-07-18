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

    /// Cheap size probe (no open-for-read).
    /// Prefer `FileManager` attributes: `URL.resourceValues` can retain sizes
    /// cached during directory enumeration and miss mid-poll appends.
    public func fileSize(of fileURL: URL) -> UInt64? {
        if let number = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber {
            return number.uint64Value
        }
        var url = fileURL
        url.removeCachedResourceValue(forKey: .fileSizeKey)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return UInt64(size)
        }
        return nil
    }

    /// Whether `fileURL` may contain unread complete lines.
    /// Bootstrap-at-end files that were never seen are checkpointed here without
    /// opening the body — critical when trees contain thousands of historical logs.
    public func needsRead(fileURL: URL, knownSize: UInt64? = nil) -> Bool {
        let path = Self.normalizePath(fileURL.path)
        let size = knownSize ?? fileSize(of: fileURL)
        guard let size else { return false }

        if readOffsets[path] == nil {
            if bootstrapUnknownFilesAtEnd {
                markOffset(path, size)
                return false
            }
            return size > 0
        }
        return size > (readOffsets[path] ?? 0)
    }

    /// Filters a listing down to files that actually need I/O.
    /// Unknown (bootstrap) files use catalog size; tracked files re-stat so a
    /// mid-TTL append is still noticed.
    public func filesNeedingRead(from files: [CachedFileInfo]) -> [URL] {
        files.compactMap { info in
            let path = Self.normalizePath(info.url.path)
            if readOffsets[path] == nil {
                return needsRead(fileURL: info.url, knownSize: info.size) ? info.url : nil
            }
            return needsRead(fileURL: info.url) ? info.url : nil
        }
    }

    /// URL-only convenience (stats each path).
    public func filesNeedingRead(from files: [URL]) -> [URL] {
        files.filter { needsRead(fileURL: $0) }
    }

    /// Returns newly completed lines (without trailing newlines) for `fileURL`.
    public func readNewCompleteLines(from fileURL: URL) -> [String] {
        let path = Self.normalizePath(fileURL.path)
        guard let size = fileSize(of: fileURL) else { return [] }

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

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

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

    /// One row from a (possibly cached) directory walk.
    public struct CachedFileInfo: Sendable {
        public let url: URL
        public let size: UInt64
        public let modifiedAt: Date

        public init(url: URL, size: UInt64, modifiedAt: Date) {
            self.url = url
            self.size = size
            self.modifiedAt = modifiedAt
        }
    }

    /// Cached recursive directory listings. Live polls often re-walk the same
    /// huge trees (OpenClaw / Claude / Codex); short TTL + root mtime keep this
    /// cheap without missing brand-new session files for long.
    private struct FileListCacheEntry {
        var files: [CachedFileInfo]
        var rootModifiedAt: Date?
        var cachedAt: Date
    }

    private var fileListCache: [String: FileListCacheEntry] = [:]
    /// Default reuse window for recursive enumerations.
    public var fileListCacheTTL: TimeInterval = 12

    /// Returns JSONL (or other) files under `root` (URLs only).
    public func enumerateJSONLFiles(
        under root: URL,
        matching pathExtension: String = "jsonl",
        recursive: Bool = true
    ) -> [URL] {
        enumerateJSONLFileInfos(under: root, matching: pathExtension, recursive: recursive).map(\.url)
    }

    /// Recursive walks are cached briefly and capture size + mtime so live polls
    /// can skip both directory walks and bulk `stat` of historical logs.
    public func enumerateJSONLFileInfos(
        under root: URL,
        matching pathExtension: String = "jsonl",
        recursive: Bool = true
    ) -> [CachedFileInfo] {
        guard fileManager.fileExists(atPath: root.path) else {
            fileListCache.removeValue(forKey: cacheKey(root: root, pathExtension: pathExtension, recursive: recursive))
            return []
        }

        if !recursive {
            return listDirectoryFileInfos(at: root, matching: pathExtension)
        }

        let key = cacheKey(root: root, pathExtension: pathExtension, recursive: true)
        let rootModified = contentModificationDate(of: root)
        let now = Date()
        if let cached = fileListCache[key],
           now.timeIntervalSince(cached.cachedAt) < fileListCacheTTL {
            // Prefer reusing the listing. Root mtime is only a soft accelerator:
            // deep session trees often leave the root mtime untouched.
            return cached.files
        }
        _ = rootModified

        var files: [CachedFileInfo] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == pathExtension else { continue }
            let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
            if let isFile = values?.isRegularFile, !isFile { continue }
            let size = UInt64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? .distantPast
            files.append(CachedFileInfo(url: fileURL, size: size, modifiedAt: modified))
        }

        fileListCache[key] = FileListCacheEntry(
            files: files,
            rootModifiedAt: rootModified,
            cachedAt: now
        )
        return files
    }

    /// Live poll candidates:
    /// - bootstrap-at-end readers: recent + already-tracked files (cheap on huge trees)
    /// - full-import readers: entire cached catalog (still skip open via size checks)
    public func candidateFileInfos(
        under root: URL,
        matching pathExtension: String = "jsonl",
        recursive: Bool = true,
        recentWithin: TimeInterval = 48 * 60 * 60,
        now: Date = Date()
    ) -> [CachedFileInfo] {
        if bootstrapUnknownFilesAtEnd {
            return liveFileInfos(
                under: root,
                matching: pathExtension,
                recursive: recursive,
                recentWithin: recentWithin,
                now: now
            )
        }
        return enumerateJSONLFileInfos(under: root, matching: pathExtension, recursive: recursive)
    }

    /// Live-path candidates only:
    /// - recently modified files (discover + bootstrap-at-end for brand new sessions)
    /// - already-tracked files whose catalog size advanced past the stored offset
    ///
    /// Deliberately does **not** pull the entire historical tree on first launch;
    /// cold files stay unknown until they receive a fresh mtime.
    public func liveFileInfos(
        under root: URL,
        matching pathExtension: String = "jsonl",
        recursive: Bool = true,
        recentWithin: TimeInterval = 48 * 60 * 60,
        now: Date = Date()
    ) -> [CachedFileInfo] {
        let all = enumerateJSONLFileInfos(under: root, matching: pathExtension, recursive: recursive)
        guard recentWithin > 0 else { return all }
        let cutoff = now.addingTimeInterval(-recentWithin)
        return all.filter { info in
            let path = Self.normalizePath(info.url.path)
            // Always re-check files we already tail — catalog size/mtime may be stale
            // within the listing TTL while the file is still growing.
            if readOffsets[path] != nil { return true }
            return info.modifiedAt >= cutoff
        }
    }

    /// Drop cached listings (tests / forced refresh).
    public func invalidateFileListCache() {
        fileListCache.removeAll(keepingCapacity: true)
    }

    private func listDirectoryFileInfos(at root: URL, matching pathExtension: String) -> [CachedFileInfo] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var files: [CachedFileInfo] = []
        for fileURL in contents where fileURL.pathExtension == pathExtension {
            let values = try? fileURL.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey, .isRegularFileKey
            ])
            if let isFile = values?.isRegularFile, !isFile { continue }
            files.append(
                CachedFileInfo(
                    url: fileURL,
                    size: UInt64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            )
        }
        return files
    }

    private func cacheKey(root: URL, pathExtension: String, recursive: Bool) -> String {
        "\(Self.normalizePath(root.path))|\(pathExtension)|\(recursive ? "r" : "f")"
    }

    private func contentModificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
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
