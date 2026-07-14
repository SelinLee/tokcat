import Foundation

/// Parses WorkBuddy (腾讯) local agent traces under `~/.workbuddy/traces/**/trace_*.json`.
///
/// Each file is a full JSON document that may grow as spans are appended, but
/// many real WorkBuddy traces are written once with a completed generation.
/// Generation spans embed OpenAI-style `usage` inside `toolOutput`.
///
/// Persistence uses `adapter_offset` keys:
/// - `"<file>"` → last observed file size
/// - `"<file>#<spanId>"` → 1 when that generation span has already been emitted
///
/// Performance / correctness model:
/// - `pollNewEvents()` is the **live** path: scan recently-touched worker dirs
///   and emit completed generation usage (including brand-new files).
/// - First-seen **old** files only checkpoint offsets, so thousands of historical
///   traces do not flood the pet on install.
/// - Incomplete generations (no usage yet) are left unmarked so a later rewrite
///   of the same span can emit once usage lands.
/// - `pollHistoricalBatch(maxFiles:)` resumes older files in small batches.
public final class WorkBuddyAdapter: AgentAdapter {
    public let source: AgentSource = .workBuddy

    private let tracesDirectory: URL
    private var pricingTable: PricingTable
    private let fileManager: FileManager
    private var offsets: [String: UInt64]
    private var dirtyOffsets: [String: UInt64] = [:]
    /// Kept for API compatibility with tests/call sites.
    /// Prefer `recentImportWindow` for live emission policy.
    private let bootstrapUnknownFiles: Bool
    /// True after a full historical pass finds nothing left to process.
    private var historyCaughtUp = false

    /// Paths that already have at least one remembered generation span marker.
    private var filesWithSpanMarkers: Set<String> = []
    /// Files with in-flight generation spans (seen, but no usage yet).
    private var pendingOpenFiles: Set<String> = []

    /// Full directory listing cache used by the historical scanner.
    private var catalog: [TraceEntry] = []
    private var catalogLoadedAt: Date = .distantPast
    private let catalogTTL: TimeInterval = 60

    /// Cursor into `catalog` for background resume.
    private var historyCursor = 0

    /// Live monitoring only cares about files / worker dirs touched recently.
    private let liveWindow: TimeInterval = 15 * 60
    /// First-seen files newer than this still emit (WorkBuddy often write-once).
    private let recentImportWindow: TimeInterval

    public init(
        tracesDirectory: URL = WorkBuddyAdapter.defaultTracesDirectory,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:],
        bootstrapUnknownFiles: Bool = true,
        recentImportWindow: TimeInterval = 24 * 60 * 60
    ) {
        self.tracesDirectory = tracesDirectory
        self.pricingTable = pricingTable
        self.fileManager = fileManager
        self.bootstrapUnknownFiles = bootstrapUnknownFiles
        self.recentImportWindow = max(0, recentImportWindow)

        let rootPath = JSONLOffsetReader.normalizePath(tracesDirectory.path)
        var normalized: [String: UInt64] = [:]
        var marked: Set<String> = []
        for (path, offset) in initialOffsets {
            // Shared store map includes every adapter; keep only our keys.
            let normalizedKey = JSONLOffsetReader.normalizePath(path)
            let fileKey = Self.fileKey(from: normalizedKey)
            guard fileKey.hasPrefix(rootPath) else { continue }
            normalized[normalizedKey] = offset
            if normalizedKey.contains("#") {
                marked.insert(fileKey)
            }
        }
        self.offsets = normalized
        self.filesWithSpanMarkers = marked
    }

    public var currentOffsets: [String: UInt64] { offsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        let pending = dirtyOffsets
        dirtyOffsets.removeAll(keepingCapacity: true)
        return pending
    }

    private func markOffset(_ key: String, _ value: UInt64) {
        offsets[key] = value
        dirtyOffsets[key] = value
    }

    public static var defaultTracesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".workbuddy/traces", isDirectory: true)
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    /// Live/hot path: inspect recently-touched worker directories / traces.
    public func pollNewEvents() -> [TokenEvent] {
        // Full recursive walks are expensive (~7k files). The live path only
        // lists worker dirs under `traces/` that were touched recently, so new
        // write-once traces are visible within one poll interval.
        let cutoff = Date().addingTimeInterval(-liveWindow)
        var events: [TokenEvent] = []
        for entry in scanLiveTraceEntries(cutoff: cutoff) {
            let fresh = refreshEntry(entry)
            let path = JSONLOffsetReader.normalizePath(fresh.path)
            let isUnknown = offsets[path] == nil
            // Keep unknown brand-new files even if mtime clock skew lands just
            // outside the live window after refresh.
            guard fresh.modifiedAt >= cutoff || isUnknown else { continue }
            if offsets[path] != fresh.size {
                historyCaughtUp = false
            }
            // Live discovery is already time-bounded; emit brand-new completed
            // generations immediately (WorkBuddy often write-once).
            events.append(contentsOf: processIfNeeded(fresh, emitNewFiles: true))
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Background resume path: process a small batch of older/unknown files.
    /// Call repeatedly; cursor advances and offsets are updated for checkpointing.
    public func pollHistoricalBatch(maxFiles: Int = 40) -> [TokenEvent] {
        if historyCaughtUp {
            return []
        }

        let entries = loadCatalogIfNeeded(maxAge: catalogTTL)
        guard !entries.isEmpty else {
            historyCaughtUp = true
            return []
        }

        if historyCursor >= entries.count {
            historyCursor = 0
        }

        var events: [TokenEvent] = []
        var processed = 0
        var skipped = 0

        // Walk at most one full catalog cycle per call.
        while processed < maxFiles, skipped < entries.count {
            if historyCursor >= entries.count {
                historyCursor = 0
            }
            let entry = entries[historyCursor]
            historyCursor += 1

            let path = JSONLOffsetReader.normalizePath(entry.path)
            if let known = offsets[path], known == entry.size {
                skipped += 1
                continue
            }

            // Historical resume keeps install flood protection for first-seen files.
            events.append(contentsOf: processIfNeeded(entry, emitNewFiles: false))
            processed += 1
            skipped = 0
        }

        // If we only saw already-checkpointed files, historical work is done.
        if processed == 0 {
            historyCaughtUp = true
            catalogLoadedAt = .distantPast
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Catalog

    private struct TraceEntry {
        let path: String
        let size: UInt64
        let modifiedAt: Date
    }

    private func refreshEntry(_ entry: TraceEntry) -> TraceEntry {
        guard let attrs = try? fileManager.attributesOfItem(atPath: entry.path) else {
            return entry
        }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? entry.size
        let modified = (attrs[.modificationDate] as? Date) ?? entry.modifiedAt
        let next = TraceEntry(path: entry.path, size: size, modifiedAt: modified)
        upsertCatalog(next)
        return next
    }

    /// Live discovery: list only recently-touched worker directories.
    /// WorkBuddy layout is `traces/<workerPid>/trace_*.json`.
    private func scanLiveTraceEntries(cutoff: Date) -> [TraceEntry] {
        guard fileManager.fileExists(atPath: tracesDirectory.path) else {
            return []
        }

        var byPath: [String: TraceEntry] = [:]

        // Warm catalog entries still help when a file keeps growing inside an
        // older worker directory whose directory mtime stopped moving.
        for entry in loadCatalogIfNeeded(maxAge: catalogTTL) where entry.modifiedAt >= cutoff {
            byPath[entry.path] = entry
        }

        let workerDirs = (try? fileManager.contentsOfDirectory(
            at: tracesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for dirURL in workerDirs {
            let dirValues = try? dirURL.resourceValues(forKeys: [
                .isDirectoryKey, .contentModificationDateKey
            ])
            // Treat missing isDirectory as "maybe directory" and verify by listing.
            if dirValues?.isDirectory == false { continue }
            let dirModified = dirValues?.contentModificationDate ?? .distantPast
            let dirPath = dirURL.path
            let hasRecentCatalogChild = byPath.keys.contains { $0.hasPrefix(dirPath + "/") }
            guard dirModified >= cutoff || hasRecentCatalogChild else { continue }

            let files = (try? fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files {
                let name = fileURL.lastPathComponent
                guard name.hasPrefix("trace_"), name.hasSuffix(".json") else { continue }
                let values = try? fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey, .isRegularFileKey
                ])
                if values?.isRegularFile == false { continue }

                let size: UInt64
                if let fileSize = values?.fileSize {
                    size = UInt64(fileSize)
                } else if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                          let number = attrs[.size] as? NSNumber {
                    size = number.uint64Value
                } else {
                    continue
                }
                let modified = values?.contentModificationDate
                    ?? (try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date)
                    ?? .distantPast

                let path = fileURL.path
                let normalized = JSONLOffsetReader.normalizePath(path)
                let isUnknown = offsets[normalized] == nil
                guard modified >= cutoff || isUnknown else { continue }

                let entry = TraceEntry(path: path, size: size, modifiedAt: modified)
                byPath[path] = entry
                upsertCatalog(entry)
            }
        }

        return Array(byPath.values)
    }

    private func upsertCatalog(_ entry: TraceEntry) {
        if let idx = catalog.firstIndex(where: { $0.path == entry.path }) {
            catalog[idx] = entry
        } else {
            catalog.append(entry)
        }
    }

    private func loadCatalogIfNeeded(maxAge: TimeInterval) -> [TraceEntry] {
        let now = Date()
        if !catalog.isEmpty, now.timeIntervalSince(catalogLoadedAt) < maxAge {
            return catalog
        }

        guard fileManager.fileExists(atPath: tracesDirectory.path),
              let enumerator = fileManager.enumerator(
                at: tracesDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            catalog = []
            catalogLoadedAt = now
            historyCursor = 0
            return []
        }

        var next: [TraceEntry] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("trace_"), name.hasSuffix(".json") else { continue }

            let values = try? fileURL.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey
            ])
            let size: UInt64
            if let fileSize = values?.fileSize {
                size = UInt64(fileSize)
            } else if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                      let number = attrs[.size] as? NSNumber {
                size = number.uint64Value
            } else {
                continue
            }
            let modified = values?.contentModificationDate
                ?? (try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date)
                ?? .distantPast

            next.append(TraceEntry(path: fileURL.path, size: size, modifiedAt: modified))
        }

        // Newest first so live + early historical work favors current activity.
        next.sort { $0.modifiedAt > $1.modifiedAt }
        catalog = next
        catalogLoadedAt = now
        // Keep cursor in range after refresh.
        if historyCursor > next.count {
            historyCursor = 0
        }
        return next
    }

    // MARK: - File processing

    private func processIfNeeded(_ entry: TraceEntry, emitNewFiles: Bool) -> [TokenEvent] {
        let path = JSONLOffsetReader.normalizePath(entry.path)
        let knownSize = offsets[path]
        // Revisit same-size rewrites when a generation is still waiting for usage.
        if let knownSize, knownSize == entry.size, !pendingOpenFiles.contains(path) {
            // If we only stored a size checkpoint and never marked any generation
            // span, re-open recent live files once. This recovers edge cases where
            // a previous pass saw incomplete JSON and froze the size too early.
            if filesWithSpanMarkers.contains(path) || !emitNewFiles {
                return []
            }
            let age = Date().timeIntervalSince(entry.modifiedAt)
            if age > recentImportWindow {
                return []
            }
        }

        return processFile(
            URL(fileURLWithPath: entry.path),
            normalizedPath: path,
            size: entry.size,
            knownSize: knownSize,
            emitNewFiles: emitNewFiles
        )
    }

    private func processFile(
        _ fileURL: URL,
        normalizedPath path: String,
        size: UInt64,
        knownSize: UInt64?,
        emitNewFiles: Bool
    ) -> [TokenEvent] {
        let isNewFile = knownSize == nil

        guard let data = try? Data(contentsOf: fileURL),
              let rootObject = try? JSONSerialization.jsonObject(with: data),
              let root = JSONDict.dictionary(rootObject)
        else {
            // Incomplete / mid-write JSON: keep the file open for the next poll
            // unless we already checkpointed a stable size.
            if !isNewFile {
                markOffset(path, size)
            }
            return []
        }

        let resolvedSize = max(size, UInt64(data.count))
        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let fileModifiedAt = (attrs?[.modificationDate] as? Date) ?? Date()
        let age = Date().timeIntervalSince(fileModifiedAt)
        let isRecentFile = age <= recentImportWindow
        // Emission policy:
        // - bootstrap disabled: import everything
        // - live path (`emitNewFiles`): always emit newly completed generations
        // - historical first-seen: only emit when file is inside recentImportWindow
        // - already-tracked files: emit new spans / usage as they appear
        let shouldEmit: Bool
        if !bootstrapUnknownFiles {
            shouldEmit = true
        } else if isNewFile {
            shouldEmit = emitNewFiles || isRecentFile
        } else {
            shouldEmit = true
        }

        let trace = JSONDict.dictionary(root["trace"]) ?? [:]
        let modelInfo = JSONDict.dictionary(trace["modelInfo"])
        let models = modelInfo?["models"] as? [Any]
        let fallbackModel = models?.compactMap(JSONDict.string).first
            ?? JSONDict.string(trace["agentName"])
            ?? "workbuddy"
        let requestId = JSONDict.string(trace["sessionId"])

        var events: [TokenEvent] = []
        var hasOpenGeneration = false
        let spans = root["spans"] as? [Any] ?? []
        for spanAny in spans {
            guard let span = JSONDict.dictionary(spanAny),
                  JSONDict.string(span["type"]) == "generation"
                  || JSONDict.string(span["name"]) == "generation"
            else {
                continue
            }

            let spanId = JSONDict.string(span["spanId"]) ?? UUID().uuidString
            let spanKey = "\(path)#\(spanId)"
            if offsets[spanKey] != nil {
                continue
            }

            guard let event = makeEvent(
                from: span,
                fallbackModel: fallbackModel,
                requestId: requestId
            ) else {
                // No usage yet (in-flight generation). Leave unmarked so a later
                // rewrite of this same span can emit once toolOutput lands.
                hasOpenGeneration = true
                continue
            }

            if shouldEmit {
                events.append(event)
            }
            // Mark only after we successfully parsed usage. Bootstrapping an old
            // file still marks spans so they are not re-emitted later.
            markOffset(spanKey, 1)
            filesWithSpanMarkers.insert(path)
        }

        // If usage is still pending, keep the file on a revisit list. WorkBuddy
        // may rewrite the same path in place (sometimes without a size change).
        if hasOpenGeneration {
            pendingOpenFiles.insert(path)
            historyCaughtUp = false
            if !isNewFile, let knownSize, resolvedSize > knownSize {
                markOffset(path, resolvedSize)
            }
            upsertCatalog(
                TraceEntry(
                    path: fileURL.path,
                    size: resolvedSize,
                    modifiedAt: max(fileModifiedAt, Date())
                )
            )
        } else {
            pendingOpenFiles.remove(path)
            markOffset(path, resolvedSize)
            upsertCatalog(
                TraceEntry(
                    path: fileURL.path,
                    size: resolvedSize,
                    modifiedAt: fileModifiedAt
                )
            )
        }
        return events
    }

    private static func fileKey(from offsetKey: String) -> String {
        if let hash = offsetKey.firstIndex(of: "#") {
            return String(offsetKey[..<hash])
        }
        return offsetKey
    }

    private func makeEvent(
        from span: [String: Any],
        fallbackModel: String,
        requestId: String? = nil
    ) -> TokenEvent? {
        let timestamp = AgentDateParsing.parseISO8601(JSONDict.string(span["endedAt"]))
            ?? AgentDateParsing.parseISO8601(JSONDict.string(span["startedAt"]))
            ?? Date()

        var model = fallbackModel
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var completionId: String?

        if let parsed = parseToolOutput(span["toolOutput"]) {
            if !parsed.model.isEmpty { model = parsed.model }
            inputTokens = parsed.inputTokens
            outputTokens = parsed.outputTokens
            cachedTokens = parsed.cachedTokens
            completionId = parsed.completionId
        }

        if inputTokens + outputTokens + cachedTokens == 0,
           let usage = JSONDict.dictionary(span["usage"]) {
            inputTokens = JSONDict.int(usage["prompt_tokens"] ?? usage["input_tokens"] ?? usage["input"])
            outputTokens = JSONDict.int(usage["completion_tokens"] ?? usage["output_tokens"] ?? usage["output"])
            if let details = JSONDict.dictionary(usage["prompt_tokens_details"]) {
                cachedTokens = JSONDict.int(details["cached_tokens"])
            } else {
                cachedTokens = JSONDict.int(usage["cached_tokens"] ?? usage["cacheRead"])
            }
        }

        guard inputTokens + outputTokens + cachedTokens > 0 else { return nil }

        let nonCachedInput = max(0, inputTokens - cachedTokens)
        let billedInput = nonCachedInput > 0 ? nonCachedInput : inputTokens
        let costUSD = pricingTable.cost(
            model: model,
            inputTokens: billedInput,
            outputTokens: outputTokens,
            cacheWriteTokens: 0,
            cacheReadTokens: cachedTokens
        )

        var latencyMs: Double?
        if let duration = span["duration"] as? Double {
            latencyMs = duration
        } else if let duration = span["duration"] as? Int {
            latencyMs = Double(duration)
        } else if let n = span["duration"] as? NSNumber {
            latencyMs = n.doubleValue
        } else if let start = AgentDateParsing.parseISO8601(JSONDict.string(span["startedAt"])),
                  let end = AgentDateParsing.parseISO8601(JSONDict.string(span["endedAt"])) {
            latencyMs = end.timeIntervalSince(start) * 1000
        }

        return TokenEvent(
            timestamp: timestamp,
            source: .workBuddy,
            model: model,
            requestId: completionId ?? requestId,
            inputTokens: billedInput,
            outputTokens: outputTokens,
            cacheReadTokens: cachedTokens,
            cacheWriteTokens: 0,
            costUSD: costUSD,
            latencyMs: latencyMs
        )
    }

    private struct ParsedUsage {
        var model: String
        var inputTokens: Int
        var outputTokens: Int
        var cachedTokens: Int
        var completionId: String?
    }

    private func parseToolOutput(_ toolOutput: Any?) -> ParsedUsage? {
        guard let toolOutput else { return nil }

        let object: Any?
        if let text = toolOutput as? String {
            object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        } else {
            object = toolOutput
        }

        let candidates: [[String: Any]]
        if let arr = object as? [Any] {
            candidates = arr.compactMap(JSONDict.dictionary)
        } else if let dict = JSONDict.dictionary(object) {
            candidates = [dict]
        } else {
            return nil
        }

        for item in candidates.reversed() {
            guard let usage = JSONDict.dictionary(item["usage"]) else { continue }
            let input = JSONDict.int(usage["prompt_tokens"] ?? usage["input_tokens"])
            let output = JSONDict.int(usage["completion_tokens"] ?? usage["output_tokens"])
            let cached: Int
            if let details = JSONDict.dictionary(usage["prompt_tokens_details"]) {
                cached = JSONDict.int(details["cached_tokens"])
            } else {
                cached = JSONDict.int(usage["cached_tokens"])
            }
            if input + output + cached > 0 {
                return ParsedUsage(
                    model: JSONDict.string(item["model"]) ?? "",
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: cached,
                    completionId: JSONDict.string(item["id"])
                )
            }
        }
        return nil
    }
}
