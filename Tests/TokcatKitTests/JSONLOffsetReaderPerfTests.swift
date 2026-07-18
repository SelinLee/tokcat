import XCTest
@testable import TokcatKit

final class JSONLOffsetReaderPerfTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-jsonl-cache-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeJSONL(name: String, lines: [String], age: TimeInterval? = nil) throws -> URL {
        let file = tempDir.appendingPathComponent(name)
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        if let age {
            let date = Date().addingTimeInterval(-age)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
        return file
    }

    func testEnumerateCachesRepeatedWalks() throws {
        _ = try writeJSONL(name: "a.jsonl", lines: [#"{"x":1}"#])
        _ = try writeJSONL(name: "b.jsonl", lines: [#"{"x":2}"#])
        let reader = JSONLOffsetReader(bootstrapUnknownFilesAtEnd: true)
        reader.fileListCacheTTL = 30

        let first = reader.enumerateJSONLFileInfos(under: tempDir, recursive: true)
        XCTAssertEqual(first.count, 2)
        let second = reader.enumerateJSONLFileInfos(under: tempDir, recursive: true)
        XCTAssertEqual(second.map(\.url.path).sorted(), first.map(\.url.path).sorted())
    }

    func testLiveFileInfosSkipsStaleUnknownFiles() throws {
        let recent = try writeJSONL(
            name: "recent.jsonl",
            lines: [#"{"type":"assistant"}"#],
            age: 60
        )
        _ = try writeJSONL(
            name: "old.jsonl",
            lines: [#"{"type":"assistant"}"#],
            age: 10 * 24 * 60 * 60
        )
        let reader = JSONLOffsetReader(bootstrapUnknownFilesAtEnd: true)
        let live = reader.liveFileInfos(under: tempDir, recursive: true, recentWithin: 48 * 60 * 60)
        XCTAssertEqual(live.map(\.url.lastPathComponent), ["recent.jsonl"])

        // Bootstrap-at-end should checkpoint recent without emitting body.
        let needing = reader.filesNeedingRead(from: live)
        XCTAssertTrue(needing.isEmpty)
        XCTAssertNotNil(reader.currentOffsets[JSONLOffsetReader.normalizePath(recent.path)])
    }

    func testNeedsReadDetectsAppendOnTrackedFile() throws {
        let file = try writeJSONL(name: "grow.jsonl", lines: [#"{"a":1}"#])
        let reader = JSONLOffsetReader(bootstrapUnknownFilesAtEnd: true)
        // First live pass bootstraps to EOF.
        let first = reader.liveFileInfos(under: tempDir, recursive: true)
        XCTAssertTrue(reader.filesNeedingRead(from: first).isEmpty)

        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(#"{"a":2}"#.data(using: .utf8)!)
        handle.write("\n".data(using: .utf8)!)
        try handle.close()

        // Force catalog refresh so size advances in listing.
        reader.invalidateFileListCache()
        let second = reader.liveFileInfos(under: tempDir, recursive: true)
        let needing = reader.filesNeedingRead(from: second)
        XCTAssertEqual(needing.map(\.lastPathComponent), ["grow.jsonl"])
        let lines = reader.readNewCompleteLines(from: file)
        XCTAssertEqual(lines.count, 1)
    }
}

final class SystemMetricsSampleOptionsTests: XCTestCase {
    func testSelectivePollSkipsDisabledProbes() {
        let monitor = SystemMetricsMonitor()
        let full = monitor.poll(options: .all)
        XCTAssertGreaterThan(full.memoryTotalBytes, 0)

        let cpuOnly = monitor.poll(options: SystemMetricsSampleOptions(
            cpu: true, gpu: false, memory: false, network: false, thermal: false
        ))
        XCTAssertTrue(cpuOnly.cpuPercent.isFinite)
        XCTAssertEqual(cpuOnly.gpuPercent, 0, accuracy: 0.0001)
        XCTAssertEqual(cpuOnly.networkInBytesPerSecond, 0, accuracy: 0.0001)

        let none = monitor.poll(options: .none)
        XCTAssertTrue(none.sampledAt.timeIntervalSince1970 > 0)
    }
}
