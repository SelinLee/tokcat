import AppKit
import Foundation
import SceneKit
import UniformTypeIdentifiers

/// Built-in + imported desktop pet models.
enum PetModelLibrary {
    static let supportedExtensions = ["usdz", "usda", "usdc", "scn", "reality"]

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("TokenCat/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var customDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Custom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies a user-selected model into Application Support and returns the stored file name.
    static func importModel(from sourceURL: URL) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw PetModelLibraryError.unsupportedType(ext)
        }

        // Begin security-scoped access when coming from Open panel.
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let safeBase = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(safeBase)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let dest = customDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        // Best-effort: also copy sibling textures/ folder if present (for usdc workflows).
        let siblingTextures = sourceURL.deletingLastPathComponent().appendingPathComponent("textures")
        if FileManager.default.fileExists(atPath: siblingTextures.path) {
            let destTex = customDirectory.appendingPathComponent("textures-\(safeBase)", isDirectory: true)
            try? FileManager.default.removeItem(at: destTex)
            try? FileManager.default.copyItem(at: siblingTextures, to: destTex)
        }

        return fileName
    }

    static func customModelURL(fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let url = customDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func removeCustomModel(fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        let url = customDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func presentOpenPanel(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "导入桌面宠物模型"
        panel.message = "选择 .usdz / .scn / .reality 模型文件"
        panel.prompt = "导入"
        if #available(macOS 11.0, *) {
            var types: [UTType] = []
            if let usdz = UTType(filenameExtension: "usdz") { types.append(usdz) }
            if let usda = UTType(filenameExtension: "usda") { types.append(usda) }
            if let usdc = UTType(filenameExtension: "usdc") { types.append(usdc) }
            if let scn = UTType(filenameExtension: "scn") { types.append(scn) }
            if let reality = UTType(filenameExtension: "reality") { types.append(reality) }
            panel.allowedContentTypes = types
        } else {
            panel.allowedFileTypes = supportedExtensions
        }
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}

enum PetModelLibraryError: LocalizedError {
    case unsupportedType(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext):
            return "不支持的模型格式：.\(ext)"
        }
    }
}
