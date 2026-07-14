import Foundation
import SceneKit
import AppKit

/// Loads an optional bundled USDZ/SCN model for the desktop pet (pink cat / custom).
enum CatModelLoader {
    static let resourceSubdirectory = "Models/Catgirl"
    static let candidateNames = ["Catgirl", "TokcatCatgirl", "catgirl"]
    static let candidateExtensions = ["usdz", "usda", "usdc", "scn", "reality"]

    struct LoadedModel {
        let scene: SCNScene
        let root: SCNNode
        let cameraNode: SCNNode?
    }

    /// Loads the preferred model for a library skin.
    /// - Parameter preferredURL: optional custom/imported model URL.
    static func loadPreparedModel(preferredURL: URL? = nil) -> LoadedModel? {
        let urls: [URL]
        if let preferredURL {
            urls = [preferredURL] + candidateURLs()
        } else {
            urls = candidateURLs()
        }
        for url in urls {
            if let source = loadScene(from: url) {
                return prepareBundledScene(source, sourceURL: url)
            }
        }
        return nil
    }

    /// Back-compat alias for older call sites (pink-cat slot).
    static func loadPreparedCatgirl() -> LoadedModel? {
        loadPreparedModel(preferredURL: nil)
    }

    private static func firstExistingModelURL() -> URL? {
        candidateURLs().first
    }

    private static func loadScene(from url: URL) -> SCNScene? {
        do {
            let scene = try SCNScene(url: url, options: [
                SCNSceneSource.LoadingOption.convertToYUp: true,
                SCNSceneSource.LoadingOption.convertUnitsToMeters: true,
                SCNSceneSource.LoadingOption.createNormalsIfAbsent: true
            ])
            if meshCount(in: scene.rootNode) == 0 {
                NSLog("[Tokcat] model has no meshes: %@", url.lastPathComponent)
                return nil
            }
            NSLog("[Tokcat] loaded pet model: %@", url.path)
            return scene
        } catch {
            NSLog("[Tokcat] failed to load %@: %@", url.lastPathComponent, "\(error)")
            return nil
        }
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        for bundle in [Bundle.module, Bundle.main] {
            for name in candidateNames {
                for ext in candidateExtensions {
                    if let url = bundle.url(
                        forResource: name,
                        withExtension: ext,
                        subdirectory: resourceSubdirectory
                    ) {
                        urls.append(url)
                    }
                    if let url = bundle.url(forResource: name, withExtension: ext) {
                        urls.append(url)
                    }
                }
            }
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    static func prepareBundledScene(_ source: SCNScene, sourceURL: URL? = nil) -> LoadedModel {
        let content = SCNNode()
        content.name = "pet.bundled.root"

        for child in source.rootNode.childNodes {
            child.removeFromParentNode()
            content.addChildNode(child)
        }
        source.rootNode.addChildNode(content)
        source.background.contents = NSColor.clear

        stripHelperMeshes(content)
        reorientToYUpIfNeeded(content)
        faceCamera(content)
        applyCasualPose(content)
        normalize(content)
        sanitizeMaterials(content, modelURL: sourceURL ?? candidateURLs().first)
        let cameraNode = installCameraAndLights(in: source, framingRoot: content)
        return LoadedModel(scene: source, root: content, cameraNode: cameraNode)
    }

    // MARK: - Cleanup / facing

    /// Remove ground/preview cubes that appear as a white card under the pet.
    private static func stripHelperMeshes(_ root: SCNNode) {
        var doomed: [SCNNode] = []
        root.enumerateHierarchy { node, _ in
            guard let raw = node.name?.lowercased() else { return }
            let name = raw.replacingOccurrences(of: " ", with: "")
            let helpers = ["cube", "plane", "ground", "floor", "backdrop", "platform", "shadowcaster"]
            if helpers.contains(where: { name == $0 || name.hasPrefix($0) || name.hasSuffix($0) }) {
                doomed.append(node)
            }
        }
        for node in doomed {
            NSLog("[Tokcat] stripping helper mesh: %@", node.name ?? "?")
            node.removeFromParentNode()
        }
    }

    /// Face +Z toward the pet camera.
    private static func faceCamera(_ root: SCNNode) {
        root.eulerAngles.y += .pi
    }

    // MARK: - Pose

    private static func applyCasualPose(_ root: SCNNode) {
        let armPairs: [(String, CGFloat)] = [
            ("mixamorig_LeftArm", 0.55),
            ("LeftArm", 0.55),
            ("J_Bip_L_UpperArm", 0.55),
            ("mixamorig_RightArm", -0.55),
            ("RightArm", -0.55),
            ("J_Bip_R_UpperArm", -0.55),
            ("mixamorig_LeftForeArm", 0.25),
            ("LeftForeArm", 0.25),
            ("mixamorig_RightForeArm", -0.25),
            ("RightForeArm", -0.25)
        ]
        root.enumerateHierarchy { node, _ in
            guard let name = node.name else { return }
            for (token, angle) in armPairs where name.localizedCaseInsensitiveContains(token) {
                if abs(node.eulerAngles.z) < 0.05 {
                    node.eulerAngles.z = angle
                }
            }
        }
    }

    // MARK: - Orientation / bounds

    private static func reorientToYUpIfNeeded(_ node: SCNNode) {
        let (minB, maxB) = worldBounds(of: node)
        let sizeY = maxB.y - minB.y
        let sizeZ = maxB.z - minB.z
        if sizeZ > sizeY * 1.15 {
            node.eulerAngles.x = -.pi / 2
            NSLog("[Tokcat] reoriented Z-up model to Y-up")
        }
    }

    private static func normalize(_ node: SCNNode) {
        node.transform = node.transform
        let (minB, maxB) = worldBounds(of: node)
        let height = max(maxB.y - minB.y, 0.0001)
        let targetHeight: CGFloat = 1.55
        let scale = targetHeight / height
        node.scale = SCNVector3(node.scale.x * scale, node.scale.y * scale, node.scale.z * scale)

        let (min2, max2) = worldBounds(of: node)
        let midX = (min2.x + max2.x) * 0.5
        let midZ = (min2.z + max2.z) * 0.5
        node.position = SCNVector3(
            node.position.x - midX,
            node.position.y - min2.y,
            node.position.z - midZ
        )
    }

    static func worldBounds(of root: SCNNode) -> (SCNVector3, SCNVector3) {
        var minV = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxV = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var any = false

        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (bmin, bmax) = node.boundingBox
            let corners: [SCNVector3] = [
                SCNVector3(bmin.x, bmin.y, bmin.z),
                SCNVector3(bmax.x, bmin.y, bmin.z),
                SCNVector3(bmin.x, bmax.y, bmin.z),
                SCNVector3(bmax.x, bmax.y, bmin.z),
                SCNVector3(bmin.x, bmin.y, bmax.z),
                SCNVector3(bmax.x, bmin.y, bmax.z),
                SCNVector3(bmin.x, bmax.y, bmax.z),
                SCNVector3(bmax.x, bmax.y, bmax.z)
            ]
            for corner in corners {
                let world = node.convertPosition(corner, to: nil)
                minV.x = min(minV.x, world.x)
                minV.y = min(minV.y, world.y)
                minV.z = min(minV.z, world.z)
                maxV.x = max(maxV.x, world.x)
                maxV.y = max(maxV.y, world.y)
                maxV.z = max(maxV.z, world.z)
                any = true
            }
        }
        if !any { return (SCNVector3Zero, SCNVector3(1, 1, 1)) }
        return (minV, maxV)
    }

    private static func meshCount(in root: SCNNode) -> Int {
        var count = 0
        root.enumerateHierarchy { node, _ in
            if node.geometry != nil { count += 1 }
        }
        return count
    }

    // MARK: - Material quality gates

    static func hasUsefulMaterials(_ root: SCNNode) -> Bool {
        var textured = 0
        var total = 0
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                total += 1
                if contentsLooksTextured(material.diffuse.contents)
                    || contentsLooksTextured(material.multiply.contents)
                    || contentsLooksTextured(material.normal.contents) {
                    textured += 1
                    continue
                }
                if let color = material.diffuse.contents as? NSColor {
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                    if r < 0.92 || g < 0.92 || b < 0.92 {
                        textured += 1
                    }
                }
            }
        }
        let ok = total > 0 && textured > 0
        NSLog("[Tokcat] materials useful=%@ textured=%d/%d", ok ? "yes" : "no", textured, total)
        return ok
    }

    private static func contentsLooksTextured(_ contents: Any?) -> Bool {
        guard let contents else { return false }
        if contents is NSImage || contents is URL || contents is String { return true }
        let desc = String(describing: contents)
        if desc.contains("offset=") || desc.contains(".png") || desc.contains(".jpg")
            || desc.contains("usdz") || desc.contains("CGImage") || desc.contains("Texture") {
            return true
        }
        return false
    }

    static func looksLikeBareMannequin(_ root: SCNNode) -> Bool {
        var meshCount = 0
        var mixamo = false
        var animalHint = false
        var skinnieHint = false
        root.enumerateHierarchy { node, _ in
            if node.geometry != nil { meshCount += 1 }
            let name = (node.name ?? "").lowercased()
            if name.contains("mixamo") { mixamo = true }
            if name.contains("skinnie") || name.contains("mannequin") { skinnieHint = true }
            if name.contains("cat") || name.contains("tubby") || name.contains("neko") || name.contains("animal") {
                animalHint = true
            }
        }
        if animalHint { return false }
        let bare = (mixamo || skinnieHint) && meshCount <= 3
        if bare {
            NSLog("[Tokcat] rejecting bare mannequin base (meshes=%d)", meshCount)
        }
        return bare
    }

    static func isVisuallyUsable(_ root: SCNNode) -> Bool {
        let (minB, maxB) = worldBounds(of: root)
        let height = maxB.y - minB.y
        let width = maxB.x - minB.x
        let depth = maxB.z - minB.z
        let ok = height > 0.3 && height < 5 && width > 0.05 && depth > 0.05
            && minB.y > -1.5 && maxB.y < 4
        if !ok {
            NSLog(
                "[Tokcat] pet model bounds unusable h=%f w=%f d=%f minY=%f maxY=%f",
                height, width, depth, minB.y, maxB.y
            )
        }
        return ok
    }

    // MARK: - Materials

    private static func sanitizeMaterials(_ root: SCNNode, modelURL: URL?) {
        let texture = loadPreferredTexture(near: modelURL)

        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .blinn
                material.isDoubleSided = true
                material.transparency = 1
                material.writesToDepthBuffer = true
                material.readsFromDepthBuffer = true
                material.metalness.contents = 0.0
                material.roughness.contents = 0.8
                material.specular.contents = NSColor(calibratedWhite: 0.12, alpha: 1)
                material.shininess = 0.08

                if let texture {
                    // Prefer real albedo for all body materials that are flat/pink/white.
                    if !contentsLooksTextured(material.diffuse.contents)
                        || isNearWhiteOrFlatPink(material.diffuse.contents) {
                        material.diffuse.contents = texture
                    }
                } else if material.diffuse.contents == nil || isNearWhiteOrFlatPink(material.diffuse.contents) {
                    material.diffuse.contents = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.82, alpha: 1)
                }
            }
        }
    }

    private static func isNearWhiteOrFlatPink(_ contents: Any?) -> Bool {
        guard let color = contents as? NSColor else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let nearWhite = r > 0.93 && g > 0.93 && b > 0.93
        // Solid magenta/pink from missing texture often lands around high R, mid G/B.
        let flatPink = r > 0.85 && g > 0.35 && g < 0.75 && b > 0.55 && b < 0.95 && abs(g - b) < 0.25
        return nearWhite || flatPink
    }

    private static func extractTextureFromUSDZ(_ usdzURL: URL) -> NSImage? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-usdz-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", usdzURL.path, "-d", tmp.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        let exts = ["png", "jpg", "jpeg"]
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: tmp.path)) ?? []
        var best: (URL, Int)?
        for rel in files {
            let url = tmp.appendingPathComponent(rel)
            guard exts.contains(url.pathExtension.lowercased()) else { continue }
            let name = url.lastPathComponent.lowercased()
            if name.contains("normal") || name.contains("orm") || name.contains("rough") || name.contains("metal") {
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var score = size
            if name.contains("basecolor") || name.contains("albedo") || name.contains("diffuse") || name.contains("tubby") {
                score += 1_000_000
            }
            if best == nil || score > best!.1 {
                best = (url, score)
            }
        }
        if let best, let image = NSImage(contentsOf: best.0) {
            NSLog("[Tokcat] extracted usdz texture %@", best.0.lastPathComponent)
            return image
        }
        return nil
    }

    private static func loadPreferredTexture(near modelURL: URL?) -> NSImage? {
        if let modelURL, modelURL.pathExtension.lowercased() == "usdz",
           let image = extractTextureFromUSDZ(modelURL) {
            return image
        }

        var searchDirs: [URL] = []
        if let modelURL {
            searchDirs.append(modelURL.deletingLastPathComponent())
            searchDirs.append(modelURL.deletingLastPathComponent().appendingPathComponent("textures"))
        }
        for bundle in [Bundle.module, Bundle.main] {
            searchDirs.append(bundle.bundleURL)
            if let tex = bundle.resourceURL?.appendingPathComponent("textures") {
                searchDirs.append(tex)
            }
        }

        let exts = ["jpg", "jpeg", "png"]
        for dir in searchDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            let images = files
                .filter { exts.contains($0.pathExtension.lowercased()) }
                .sorted {
                    let a = (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let b = (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return a > b
                }
            for url in images {
                let name = url.lastPathComponent.lowercased()
                if name.contains("normal") { continue }
                if let image = NSImage(contentsOf: url), image.size.width > 8 {
                    NSLog("[Tokcat] using texture %@", url.lastPathComponent)
                    return image
                }
            }
        }
        return nil
    }

    // MARK: - Camera

    @discardableResult
    static func installCameraAndLights(in scene: SCNScene, framingRoot: SCNNode? = nil) -> SCNNode {
        scene.rootNode.childNodes
            .filter { $0.name?.hasPrefix("tokcat.") == true }
            .forEach { $0.removeFromParentNode() }

        let (minB, maxB) = worldBounds(of: framingRoot ?? scene.rootNode)
        let height = max(maxB.y - minB.y, 0.5)
        let midY = (minB.y + maxB.y) * 0.52
        let distance = max(height * 2.0, 2.4)

        let cameraNode = SCNNode()
        cameraNode.name = "tokcat.camera"
        let camera = SCNCamera()
        camera.fieldOfView = 28
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, midY + height * 0.05, distance)
        cameraNode.look(at: SCNVector3(0, midY, 0))
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.name = "tokcat.keyLight"
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 950
        keyLight.color = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.96, alpha: 1)
        key.light = keyLight
        key.eulerAngles = SCNVector3(-0.85, 0.55, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.name = "tokcat.fillLight"
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = 520
        fillLight.color = NSColor(calibratedRed: 0.85, green: 0.9, blue: 1.0, alpha: 1)
        fill.light = fillLight
        fill.eulerAngles = SCNVector3(-0.25, -0.9, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.name = "tokcat.ambient"
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 450
        ambientLight.color = NSColor.white
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)

        return cameraNode
    }
}
