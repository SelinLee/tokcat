import Foundation
import Darwin

/// Registry timestamps describe status changes, not heartbeats or successful turn ends.
final class ClaudeSessionRegistryReader {
    struct Registration {
        var sessionID: String
        var projectPath: String?
        var title: String?
        var status: String?
        var statusAt: Date
        var logPath: String?
        var modelName: String?
    }

    private struct Entry: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String?
        var name: String?
        var kind: String?
        var agentId: String?
        var status: String?
        var statusUpdatedAt: Double?
        var updatedAt: Double?
        var startedAt: Double
        var procStart: String?
        var pidDomain: String?
    }

    private let directory: URL
    private let projectsDirectory: URL
    private let validateProcess: (Int32, String?, Date) -> Bool
    private var entries: [URL: Entry] = [:]
    private var metadata: [String: (signature: String, record: AgentTaskRecord?)] = [:]
    private(set) var isAvailable = false
    private(set) var ignoredSessionIDs: Set<String> = []

    init(directory: URL, projectsDirectory: URL = ClaudeCodeAdapter.defaultProjectsDirectory,
         validateProcess: @escaping (Int32, String?, Date) -> Bool = ClaudeSessionRegistryReader.isLocalProcess) {
        self.directory = directory
        self.projectsDirectory = projectsDirectory
        self.validateProcess = validateProcess
    }

    func poll(now: Date) -> [Registration] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            isAvailable = false
            return []
        }
        isAvailable = true
        ignoredSessionIDs = []
        let filesToRead = Set(files.filter { $0.pathExtension == "json" })
        entries = entries.filter { filesToRead.contains($0.key) }
        var result: [String: Registration] = [:]
        for file in filesToRead {
            guard let pid = Int32(file.deletingPathExtension().lastPathComponent), pid > 0 else { continue }
            if let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true, (values.fileSize ?? 0) <= 65_536,
               let data = try? Data(contentsOf: file),
               let entry = try? JSONDecoder().decode(Entry.self, from: data) {
                entries[file] = entry
            }
            // A partially rewritten registry file is retried without losing a live session.
            guard let entry = entries[file], entry.pid == pid,
                  !entry.sessionId.isEmpty, entry.sessionId.count <= 200,
                  entry.sessionId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  entry.pidDomain == nil || entry.pidDomain == "darwin",
                  entry.startedAt.isFinite, entry.startedAt > 0 else { continue }
            let startedAt = Date(timeIntervalSince1970: entry.startedAt / 1000)
            guard startedAt <= now.addingTimeInterval(5), validateProcess(pid, entry.procStart, startedAt) else { continue }
            guard entry.agentId == nil, entry.kind == nil || entry.kind == "interactive" else {
                ignoredSessionIDs.insert(entry.sessionId)
                continue
            }
            let milliseconds = entry.statusUpdatedAt ?? entry.updatedAt ?? entry.startedAt
            guard milliseconds.isFinite, milliseconds > 0 else { continue }
            let statusAt = Date(timeIntervalSince1970: milliseconds / 1000)
            guard statusAt <= now.addingTimeInterval(5) else { continue }
            let log = transcript(sessionID: entry.sessionId, cwd: entry.cwd)
            let record = log.flatMap { transcriptMetadata($0) }
            let registration = Registration(sessionID: entry.sessionId, projectPath: entry.cwd,
                title: entry.name.map { String($0.prefix(120)) } ?? record?.title,
                status: entry.status, statusAt: statusAt, logPath: log?.path, modelName: record?.modelName)
            if result[entry.sessionId].map({ $0.statusAt > statusAt }) == true { continue }
            result[entry.sessionId] = registration
        }
        let liveLogs = Set(result.values.compactMap(\.logPath))
        metadata = metadata.filter { liveLogs.contains($0.key) }
        return result.values.sorted { $0.sessionID < $1.sessionID }
    }

    private func transcript(sessionID: String, cwd: String?) -> URL? {
        guard let cwd else { return nil }
        let project = String(cwd.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        })
        let url = projectsDirectory.appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent(sessionID + ".jsonl")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func transcriptMetadata(_ url: URL) -> AgentTaskRecord? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate else { return nil }
        let signature = "\(values.fileSize ?? 0):\(modifiedAt.timeIntervalSince1970)"
        if let cached = metadata[url.path], cached.signature == signature { return cached.record }
        let record = RecentAgentTaskReader.read(url: url, source: .claudeCode, modifiedAt: modifiedAt)
        metadata[url.path] = (signature, record)
        return record
    }

    static func isLocalProcess(pid: Int32, procStart: String?, startedAt: Date) -> Bool {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == Int32(size),
              info.pbi_uid == getuid(), info.pbi_status != UInt32(SZOMB) else { return false }
        var name = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return false }
        let processName = String(cString: name).lowercased()
        guard processName.contains("claude") || processName == "node" else { return false }
        let processStart = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec))
        if let procStart {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            guard let expected = formatter.date(from: procStart) else { return false }
            return abs(processStart.timeIntervalSince(expected)) < 1
        }
        // Older records lack procStart. A reused PID must not inherit their busy state.
        return (0...10).contains(startedAt.timeIntervalSince(processStart))
    }
}
