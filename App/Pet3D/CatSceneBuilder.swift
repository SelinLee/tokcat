import AppKit
import SceneKit

/// Node references needed to animate the cat after it's been built.
struct CatRig {
    let root: SCNNode
    let body: SCNNode
    let head: SCNNode
    let leftEar: SCNNode
    let rightEar: SCNNode
    let leftEye: SCNNode
    let rightEye: SCNNode
    let tailSegments: [SCNNode]
}

/// Builds a blocky, "geometric pixel" style low-poly cat purely from primitive
/// SceneKit geometry (no external model assets). Flat-shaded boxes read as
/// 3D once lit from an angle, which is the whole trick here.
enum CatSceneBuilder {
    static let coatColor = NSColor(calibratedRed: 0.90, green: 0.58, blue: 0.32, alpha: 1)
    static let darkColor = NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.10, alpha: 1)
    static let eyeColor = NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.55, alpha: 1)
    static let noseColor = NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.55, alpha: 1)

    /// Builds the cat rig and everything else the scene needs (camera,
    /// lighting) directly into `scene`.
    static func buildScene(in scene: SCNScene) -> CatRig {
        let rig = build()
        scene.rootNode.addChildNode(rig.root)

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 40
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.1, 3.4)
        cameraNode.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(cameraNode)

        let keyLightNode = SCNNode()
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 900
        keyLightNode.light = keyLight
        keyLightNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLightNode)

        let ambientNode = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 300
        ambientLight.color = NSColor(calibratedWhite: 1, alpha: 1)
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        return rig
    }

    static func build() -> CatRig {
        let root = SCNNode()

        let body = boxNode(width: 1.2, height: 0.9, length: 1.8, color: coatColor)
        body.position = SCNVector3(0, 0.55, 0)
        root.addChildNode(body)

        let head = boxNode(width: 0.9, height: 0.8, length: 0.85, color: coatColor)
        head.position = SCNVector3(0, 0.55, 1.05)
        head.pivot = SCNMatrix4MakeTranslation(0, 0, -0.4)
        root.addChildNode(head)

        let leftEar = earNode()
        leftEar.position = SCNVector3(-0.28, 0.5, -0.1)
        head.addChildNode(leftEar)

        let rightEar = earNode()
        rightEar.position = SCNVector3(0.28, 0.5, -0.1)
        head.addChildNode(rightEar)

        let leftEye = eyeNode()
        leftEye.position = SCNVector3(-0.22, 0.05, 0.43)
        head.addChildNode(leftEye)

        let rightEye = eyeNode()
        rightEye.position = SCNVector3(0.22, 0.05, 0.43)
        head.addChildNode(rightEye)

        let nose = boxNode(width: 0.12, height: 0.1, length: 0.08, color: noseColor)
        nose.position = SCNVector3(0, -0.18, 0.45)
        head.addChildNode(nose)

        let legPositions: [(Float, Float)] = [(-0.4, 0.75), (0.4, 0.75), (-0.4, -0.75), (0.4, -0.75)]
        for (x, z) in legPositions {
            let leg = boxNode(width: 0.22, height: 0.5, length: 0.22, color: darkColor)
            leg.position = SCNVector3(x, 0.0, z)
            root.addChildNode(leg)
        }

        var tailSegments: [SCNNode] = []
        var previousParent = body
        var attachPoint = SCNVector3(0, 0.3, -0.95)
        for i in 0..<3 {
            let segment = boxNode(width: 0.2, height: 0.2, length: 0.4, color: coatColor)
            segment.position = attachPoint
            segment.pivot = SCNMatrix4MakeTranslation(0, 0, 0.18)
            previousParent.addChildNode(segment)
            tailSegments.append(segment)
            previousParent = segment
            attachPoint = SCNVector3(0, 0.05 * Float(i + 1), -0.36)
        }

        return CatRig(
            root: root,
            body: body,
            head: head,
            leftEar: leftEar,
            rightEar: rightEar,
            leftEye: leftEye,
            rightEye: rightEye,
            tailSegments: tailSegments
        )
    }

    private static func boxNode(width: CGFloat, height: CGFloat, length: CGFloat, color: NSColor) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func earNode() -> SCNNode {
        boxNode(width: 0.22, height: 0.28, length: 0.12, color: coatColor)
    }

    private static func eyeNode() -> SCNNode {
        boxNode(width: 0.16, height: 0.16, length: 0.05, color: eyeColor)
    }
}
