import AppKit
import SceneKit

/// Node handles for the built-in Q-version humanoid catgirl rig.
struct CatgirlRig {
    let root: SCNNode
    let hips: SCNNode
    let torso: SCNNode
    let head: SCNNode
    let leftEar: SCNNode
    let rightEar: SCNNode
    let leftEye: SCNNode
    let rightEye: SCNNode
    let leftArm: SCNNode
    let rightArm: SCNNode
    let leftForearm: SCNNode
    let rightForearm: SCNNode
    let leftLeg: SCNNode
    let rightLeg: SCNNode
    let leftShin: SCNNode
    let rightShin: SCNNode
    let tailSegments: [SCNNode]
    let skirt: SCNNode
}

/// Soft chibi catgirl assembled from rounded SceneKit primitives.
/// Goal: readable at ~200pt, cute proportions (big head / short limbs),
/// pastel palette, not a stack of hard boxes.
enum CatgirlSceneBuilder {
    // Soft pastel palette
    static let skin = NSColor(calibratedRed: 1.00, green: 0.93, blue: 0.90, alpha: 1)
    static let cheek = NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.78, alpha: 0.85)
    static let hair = NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.84, alpha: 1)
    static let hairShade = NSColor(calibratedRed: 0.92, green: 0.52, blue: 0.70, alpha: 1)
    static let hairTip = NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.92, alpha: 1)
    static let dress = NSColor(calibratedRed: 0.62, green: 0.72, blue: 1.00, alpha: 1)
    static let dressDeep = NSColor(calibratedRed: 0.45, green: 0.56, blue: 0.95, alpha: 1)
    static let apron = NSColor(calibratedRed: 0.98, green: 0.98, blue: 1.00, alpha: 1)
    static let ribbon = NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.68, alpha: 1)
    static let stocking = NSColor(calibratedRed: 0.86, green: 0.90, blue: 1.00, alpha: 1)
    static let shoe = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.78, alpha: 1)
    static let eyeWhite = NSColor(calibratedWhite: 1.0, alpha: 1)
    static let iris = NSColor(calibratedRed: 0.42, green: 0.78, blue: 0.98, alpha: 1)
    static let irisDeep = NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.82, alpha: 1)
    static let pupil = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.22, alpha: 1)
    static let nose = NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.70, alpha: 1)
    static let mouth = NSColor(calibratedRed: 0.92, green: 0.48, blue: 0.58, alpha: 1)

    static func buildScene(in scene: SCNScene) -> CatgirlRig {
        let rig = build()
        scene.rootNode.addChildNode(rig.root)
        installCameraAndLights(in: scene)
        return rig
    }

    static func installCameraAndLights(in scene: SCNScene) {
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 34
        camera.wantsHDR = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.25, 2.85)
        cameraNode.look(at: SCNVector3(0, 0.95, 0))
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 880
        keyLight.color = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.96, alpha: 1)
        key.light = keyLight
        key.eulerAngles = SCNVector3(-0.85, 0.55, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = 320
        fillLight.color = NSColor(calibratedRed: 0.78, green: 0.88, blue: 1.0, alpha: 1)
        fill.light = fillLight
        fill.eulerAngles = SCNVector3(-0.35, -0.9, 0)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.intensity = 180
        rimLight.color = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.95, alpha: 1)
        rim.light = rimLight
        rim.eulerAngles = SCNVector3(0.2, 2.6, 0)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 240
        ambientLight.color = NSColor(calibratedWhite: 1, alpha: 1)
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)
    }

    static func build() -> CatgirlRig {
        let root = SCNNode()
        root.name = "catgirl.root"

        // Super-deformed stance: short legs, large head.
        let hips = SCNNode()
        hips.name = "catgirl.hips"
        hips.position = SCNVector3(0, 0.62, 0)
        root.addChildNode(hips)

        // Soft hip / lower torso
        let pelvis = roundedBox(0.38, 0.16, 0.24, dressDeep, radius: 0.06)
        pelvis.position = SCNVector3(0, 0.04, 0)
        hips.addChildNode(pelvis)

        // Flared skirt layers
        let skirt = skirtStack()
        skirt.position = SCNVector3(0, -0.02, 0)
        hips.addChildNode(skirt)

        // Torso (short, rounded)
        let torso = roundedBox(0.36, 0.34, 0.22, dress, radius: 0.08)
        torso.position = SCNVector3(0, 0.28, 0)
        torso.pivot = SCNMatrix4MakeTranslation(0, -0.14, 0)
        hips.addChildNode(torso)

        // Chest ribbon / bow
        let bowLeft = roundedBox(0.10, 0.08, 0.04, ribbon, radius: 0.03)
        bowLeft.position = SCNVector3(-0.06, 0.10, 0.12)
        bowLeft.eulerAngles.z = 0.35
        torso.addChildNode(bowLeft)
        let bowRight = roundedBox(0.10, 0.08, 0.04, ribbon, radius: 0.03)
        bowRight.position = SCNVector3(0.06, 0.10, 0.12)
        bowRight.eulerAngles.z = -0.35
        torso.addChildNode(bowRight)
        let bowKnot = sphere(0.035, ribbon)
        bowKnot.position = SCNVector3(0, 0.10, 0.13)
        torso.addChildNode(bowKnot)

        // Apron panel
        let apronNode = roundedBox(0.20, 0.16, 0.04, apron, radius: 0.04)
        apronNode.position = SCNVector3(0, -0.02, 0.12)
        torso.addChildNode(apronNode)

        // Head — oversized chibi sphere
        let head = SCNNode()
        head.name = "catgirl.head"
        head.position = SCNVector3(0, 0.42, 0.02)
        torso.addChildNode(head)

        let face = sphere(0.28, skin)
        face.scale = SCNVector3(1.0, 1.02, 0.95)
        head.addChildNode(face)

        // Hair cap + bangs + side locks + twin tails
        buildHair(on: head)

        // Cat ears
        let leftEar = catEar(side: -1)
        leftEar.position = SCNVector3(-0.13, 0.22, -0.02)
        head.addChildNode(leftEar)
        let rightEar = catEar(side: 1)
        rightEar.position = SCNVector3(0.13, 0.22, -0.02)
        head.addChildNode(rightEar)

        // Eyes
        let leftEye = animeEye(side: -1)
        leftEye.position = SCNVector3(-0.09, 0.02, 0.22)
        head.addChildNode(leftEye)
        let rightEye = animeEye(side: 1)
        rightEye.position = SCNVector3(0.09, 0.02, 0.22)
        head.addChildNode(rightEye)

        // Cheeks
        let leftCheek = sphere(0.035, cheek)
        leftCheek.position = SCNVector3(-0.15, -0.05, 0.20)
        leftCheek.opacity = 0.9
        head.addChildNode(leftCheek)
        let rightCheek = sphere(0.035, cheek)
        rightCheek.position = SCNVector3(0.15, -0.05, 0.20)
        rightCheek.opacity = 0.9
        head.addChildNode(rightCheek)

        // Tiny nose + smile
        let noseNode = sphere(0.012, nose)
        noseNode.position = SCNVector3(0, -0.04, 0.255)
        head.addChildNode(noseNode)

        let mouthNode = roundedBox(0.05, 0.012, 0.01, mouth, radius: 0.005)
        mouthNode.position = SCNVector3(0, -0.09, 0.245)
        head.addChildNode(mouthNode)

        // Arms
        let leftArm = capsuleLimb(radius: 0.045, height: 0.20, color: skin)
        leftArm.position = SCNVector3(-0.24, 0.22, 0)
        leftArm.pivot = SCNMatrix4MakeTranslation(0, 0.08, 0)
        leftArm.eulerAngles.z = 0.25
        torso.addChildNode(leftArm)

        let leftForearm = capsuleLimb(radius: 0.04, height: 0.18, color: skin)
        leftForearm.position = SCNVector3(0, -0.18, 0)
        leftForearm.pivot = SCNMatrix4MakeTranslation(0, 0.07, 0)
        leftArm.addChildNode(leftForearm)
        let leftHand = sphere(0.045, skin)
        leftHand.position = SCNVector3(0, -0.12, 0)
        leftForearm.addChildNode(leftHand)

        let rightArm = capsuleLimb(radius: 0.045, height: 0.20, color: skin)
        rightArm.position = SCNVector3(0.24, 0.22, 0)
        rightArm.pivot = SCNMatrix4MakeTranslation(0, 0.08, 0)
        rightArm.eulerAngles.z = -0.25
        torso.addChildNode(rightArm)

        let rightForearm = capsuleLimb(radius: 0.04, height: 0.18, color: skin)
        rightForearm.position = SCNVector3(0, -0.18, 0)
        rightForearm.pivot = SCNMatrix4MakeTranslation(0, 0.07, 0)
        rightArm.addChildNode(rightForearm)
        let rightHand = sphere(0.045, skin)
        rightHand.position = SCNVector3(0, -0.12, 0)
        rightForearm.addChildNode(rightHand)

        // Legs
        let leftLeg = capsuleLimb(radius: 0.05, height: 0.18, color: stocking)
        leftLeg.position = SCNVector3(-0.09, -0.08, 0)
        leftLeg.pivot = SCNMatrix4MakeTranslation(0, 0.08, 0)
        hips.addChildNode(leftLeg)

        let leftShin = capsuleLimb(radius: 0.045, height: 0.18, color: stocking)
        leftShin.position = SCNVector3(0, -0.18, 0)
        leftShin.pivot = SCNMatrix4MakeTranslation(0, 0.08, 0)
        leftLeg.addChildNode(leftShin)
        let leftShoe = shoeNode()
        leftShoe.position = SCNVector3(0, -0.12, 0.02)
        leftShin.addChildNode(leftShoe)

        let rightLeg = capsuleLimb(radius: 0.05, height: 0.18, color: stocking)
        rightLeg.position = SCNVector3(0.09, -0.08, 0)
        rightLeg.pivot = SCNMatrix4MakeTranslation(0, 0.08, 0)
        hips.addChildNode(rightLeg)

        let rightShin = capsuleLimb(radius: 0.045, height: 0.18, color: stocking)
        rightShin.position = SCNVector3(0, -0.18, 0)
        rightShin.pivot = SCNMatrix4MakeTranslation(0, 0.08, 0)
        rightLeg.addChildNode(rightShin)
        let rightShoe = shoeNode()
        rightShoe.position = SCNVector3(0, -0.12, 0.02)
        rightShin.addChildNode(rightShoe)

        // Fluffy segmented tail
        var tailSegments: [SCNNode] = []
        var parent: SCNNode = hips
        var attach = SCNVector3(0, 0.04, -0.12)
        for i in 0..<5 {
            let r: CGFloat = 0.045 - CGFloat(i) * 0.004
            let seg = sphere(r, i % 2 == 0 ? hair : hairTip)
            seg.position = attach
            parent.addChildNode(seg)
            tailSegments.append(seg)
            parent = seg
            attach = SCNVector3(0.01 * CGFloat((i % 2 == 0) ? 1 : -1), 0.03, -0.09)
        }

        return CatgirlRig(
            root: root,
            hips: hips,
            torso: torso,
            head: head,
            leftEar: leftEar,
            rightEar: rightEar,
            leftEye: leftEye,
            rightEye: rightEye,
            leftArm: leftArm,
            rightArm: rightArm,
            leftForearm: leftForearm,
            rightForearm: rightForearm,
            leftLeg: leftLeg,
            rightLeg: rightLeg,
            leftShin: leftShin,
            rightShin: rightShin,
            tailSegments: tailSegments,
            skirt: skirt
        )
    }

    // MARK: - Parts

    private static func buildHair(on head: SCNNode) {
        // Main bob cap
        let cap = sphere(0.30, hair)
        cap.position = SCNVector3(0, 0.06, -0.02)
        cap.scale = SCNVector3(1.05, 0.85, 1.05)
        head.addChildNode(cap)

        // Crown puff
        let puff = sphere(0.14, hairTip)
        puff.position = SCNVector3(0, 0.22, -0.02)
        head.addChildNode(puff)

        // Bangs
        let bangCenter = sphere(0.09, hairShade)
        bangCenter.position = SCNVector3(0, 0.10, 0.22)
        bangCenter.scale = SCNVector3(1.4, 0.7, 0.5)
        head.addChildNode(bangCenter)

        let bangL = sphere(0.07, hair)
        bangL.position = SCNVector3(-0.10, 0.08, 0.21)
        bangL.scale = SCNVector3(0.9, 1.1, 0.5)
        bangL.eulerAngles.z = 0.25
        head.addChildNode(bangL)

        let bangR = sphere(0.07, hair)
        bangR.position = SCNVector3(0.10, 0.08, 0.21)
        bangR.scale = SCNVector3(0.9, 1.1, 0.5)
        bangR.eulerAngles.z = -0.25
        head.addChildNode(bangR)

        // Side locks
        let sideL = capsuleLimb(radius: 0.045, height: 0.22, color: hair)
        sideL.position = SCNVector3(-0.22, -0.02, 0.04)
        sideL.eulerAngles.z = 0.15
        head.addChildNode(sideL)

        let sideR = capsuleLimb(radius: 0.045, height: 0.22, color: hair)
        sideR.position = SCNVector3(0.22, -0.02, 0.04)
        sideR.eulerAngles.z = -0.15
        head.addChildNode(sideR)

        // Twin tails
        let tailL = twinTail(side: -1)
        tailL.position = SCNVector3(-0.20, 0.08, -0.08)
        head.addChildNode(tailL)
        let tailR = twinTail(side: 1)
        tailR.position = SCNVector3(0.20, 0.08, -0.08)
        head.addChildNode(tailR)

        // Hair ribbons on twin tails
        let ribL = sphere(0.035, ribbon)
        ribL.position = SCNVector3(-0.20, 0.10, -0.06)
        head.addChildNode(ribL)
        let ribR = sphere(0.035, ribbon)
        ribR.position = SCNVector3(0.20, 0.10, -0.06)
        head.addChildNode(ribR)
    }

    private static func twinTail(side: CGFloat) -> SCNNode {
        let root = SCNNode()
        let upper = capsuleLimb(radius: 0.05, height: 0.20, color: hair)
        upper.eulerAngles.z = side * 0.55
        upper.eulerAngles.x = 0.25
        root.addChildNode(upper)
        let lower = sphere(0.07, hairTip)
        lower.position = SCNVector3(side * 0.08, -0.18, -0.04)
        root.addChildNode(lower)
        let tip = sphere(0.05, hair)
        tip.position = SCNVector3(side * 0.10, -0.26, -0.05)
        root.addChildNode(tip)
        return root
    }

    private static func catEar(side: CGFloat) -> SCNNode {
        let ear = SCNNode()
        // Outer ear: tapered cone-ish via scaled sphere stack
        let outer = sphere(0.08, hair)
        outer.scale = SCNVector3(0.75, 1.25, 0.55)
        outer.eulerAngles.z = side * 0.35
        outer.eulerAngles.x = -0.15
        ear.addChildNode(outer)

        let tip = sphere(0.035, hairTip)
        tip.position = SCNVector3(side * 0.01, 0.09, 0)
        ear.addChildNode(tip)

        let inner = sphere(0.035, cheek)
        inner.position = SCNVector3(0, 0.01, 0.03)
        inner.scale = SCNVector3(0.7, 1.0, 0.4)
        ear.addChildNode(inner)
        return ear
    }

    private static func animeEye(side: CGFloat) -> SCNNode {
        let eye = SCNNode()

        // Soft white base
        let white = sphere(0.065, eyeWhite)
        white.scale = SCNVector3(0.95, 1.15, 0.45)
        eye.addChildNode(white)

        // Iris
        let irisNode = sphere(0.042, iris)
        irisNode.position = SCNVector3(0, -0.005, 0.025)
        irisNode.scale = SCNVector3(0.95, 1.1, 0.5)
        eye.addChildNode(irisNode)

        // Iris depth ring
        let deep = sphere(0.028, irisDeep)
        deep.position = SCNVector3(0, -0.008, 0.035)
        deep.scale = SCNVector3(0.95, 1.05, 0.5)
        eye.addChildNode(deep)

        // Pupil
        let pupilNode = sphere(0.016, pupil)
        pupilNode.position = SCNVector3(side * 0.002, -0.006, 0.045)
        eye.addChildNode(pupilNode)

        // Highlights
        let hi1 = sphere(0.012, eyeWhite)
        hi1.position = SCNVector3(-0.012, 0.018, 0.05)
        eye.addChildNode(hi1)
        let hi2 = sphere(0.007, eyeWhite)
        hi2.position = SCNVector3(0.012, -0.01, 0.05)
        eye.addChildNode(hi2)

        // Lash / upper lid shadow
        let lid = roundedBox(0.10, 0.018, 0.02, hairShade, radius: 0.008)
        lid.position = SCNVector3(0, 0.05, 0.03)
        lid.eulerAngles.x = -0.2
        eye.addChildNode(lid)

        return eye
    }

    private static func skirtStack() -> SCNNode {
        let root = SCNNode()
        let upper = roundedBox(0.46, 0.10, 0.30, dress, radius: 0.05)
        upper.position = SCNVector3(0, 0.02, 0)
        root.addChildNode(upper)

        let mid = roundedBox(0.54, 0.12, 0.36, dressDeep, radius: 0.06)
        mid.position = SCNVector3(0, -0.06, 0)
        root.addChildNode(mid)

        let hem = roundedBox(0.58, 0.05, 0.38, hairTip, radius: 0.025)
        hem.position = SCNVector3(0, -0.13, 0)
        // soft pink hem accent
        if let mat = hem.geometry?.firstMaterial {
            mat.diffuse.contents = ribbon
        }
        root.addChildNode(hem)
        return root
    }

    private static func shoeNode() -> SCNNode {
        let shoeRoot = SCNNode()
        let body = roundedBox(0.12, 0.06, 0.16, shoe, radius: 0.03)
        shoeRoot.addChildNode(body)
        let toe = sphere(0.04, shoe)
        toe.position = SCNVector3(0, -0.01, 0.07)
        shoeRoot.addChildNode(toe)
        return shoeRoot
    }

    // MARK: - Primitives

    private static func sphere(_ radius: CGFloat, _ color: NSColor) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 24
        geometry.materials = [mat(color)]
        return SCNNode(geometry: geometry)
    }

    private static func capsuleLimb(radius: CGFloat, height: CGFloat, color: NSColor) -> SCNNode {
        // SCNCapsule height includes hemispheres.
        let geometry = SCNCapsule(capRadius: radius, height: height)
        geometry.materials = [mat(color)]
        return SCNNode(geometry: geometry)
    }

    private static func roundedBox(
        _ w: CGFloat,
        _ h: CGFloat,
        _ l: CGFloat,
        _ color: NSColor,
        radius: CGFloat
    ) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: l, chamferRadius: radius)
        geometry.materials = [mat(color)]
        return SCNNode(geometry: geometry)
    }

    private static func mat(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .blinn
        material.shininess = 0.35
        material.specular.contents = NSColor(calibratedWhite: 1, alpha: 0.35)
        material.isDoubleSided = false
        return material
    }
}
