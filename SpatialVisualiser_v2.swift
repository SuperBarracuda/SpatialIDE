import Cocoa
import SceneKit

// MARK: - Swift Source Parser

struct ParsedClass {
    let name: String
    let superclass: String?
    let protocols: [String]
    let methods: [String]
    let properties: [String]
    let isProtocol: Bool
    let isEnum: Bool
}

func parseSwiftFile(_ path: String) -> [ParsedClass] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("Failed to read \(path)")
        return []
    }

    var classes: [ParsedClass] = []
    let lines = content.components(separatedBy: "\n")

    var currentName: String? = nil
    var currentSuper: String? = nil
    var currentProtocols: [String] = []
    var currentMethods: [String] = []
    var currentProperties: [String] = []
    var isProtocol = false
    var isEnum = false
    var braceDepth = 0
    var insideType = false

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        let declPatterns: [(String, Bool, Bool)] = [
            ("public class ", false, false), ("class ", false, false),
            ("public protocol ", true, false), ("protocol ", true, false),
            ("public enum ", false, true), ("enum ", false, true),
        ]

        for (prefix, isProt, isEn) in declPatterns {
            if trimmed.hasPrefix(prefix) && !trimmed.hasPrefix("//") {
                if let name = currentName {
                    classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                               methods: currentMethods, properties: currentProperties,
                                               isProtocol: isProtocol, isEnum: isEnum))
                }

                let afterPrefix = String(trimmed.dropFirst(prefix.count))
                let nameAndRest = afterPrefix.components(separatedBy: CharacterSet(charactersIn: " :{<"))
                let name = nameAndRest.first ?? afterPrefix

                var sup: String? = nil
                var prots: [String] = []
                if let colonRange = afterPrefix.range(of: ":") {
                    let inheritance = String(afterPrefix[colonRange.upperBound...])
                        .components(separatedBy: "{")[0]
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    let knownProts = ["CalculatorDisplay", "Error", "CustomStringConvertible", "Codable", "Hashable", "Equatable"]
                    for (i, item) in inheritance.enumerated() {
                        let clean = item.components(separatedBy: " ").first ?? item
                        if i == 0 && !isProt && !isEn && clean.first?.isUpperCase == true
                            && !["Error", "CustomStringConvertible"].contains(clean) {
                            if knownProts.contains(clean) {
                                prots.append(clean)
                            } else {
                                sup = clean
                            }
                        } else {
                            let clean2 = clean.components(separatedBy: " ").first ?? clean
                            if !clean2.isEmpty { prots.append(clean2) }
                        }
                    }
                }

                currentName = String(name)
                currentSuper = sup
                currentProtocols = prots
                currentMethods = []
                currentProperties = []
                isProtocol = isProt
                isEnum = isEn
                insideType = true
                braceDepth = 0
                break
            }
        }

        if insideType {
            braceDepth += line.filter({ $0 == "{" }).count
            braceDepth -= line.filter({ $0 == "}" }).count

            if trimmed.contains("func ") && !trimmed.hasPrefix("//") {
                if let funcRange = trimmed.range(of: "func ") {
                    let afterFunc = String(trimmed[funcRange.upperBound...])
                    let methodName = afterFunc.components(separatedBy: "(").first ?? afterFunc
                    currentMethods.append(methodName)
                }
            }

            if (trimmed.hasPrefix("public var ") || trimmed.hasPrefix("private var ") ||
                trimmed.hasPrefix("public let ") || trimmed.hasPrefix("private let ") ||
                trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ")) &&
                !trimmed.contains("func ") && !trimmed.hasPrefix("//") && braceDepth <= 1 {
                let words = trimmed.components(separatedBy: " ")
                if let varIdx = words.firstIndex(where: { $0 == "var" || $0 == "let" }), varIdx + 1 < words.count {
                    let propName = words[varIdx + 1].components(separatedBy: ":").first?
                        .components(separatedBy: "=").first ?? words[varIdx + 1]
                    currentProperties.append(propName)
                }
            }

            if braceDepth <= 0 && line.contains("}") && currentName != nil {
                if let name = currentName {
                    classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                               methods: currentMethods, properties: currentProperties,
                                               isProtocol: isProtocol, isEnum: isEnum))
                }
                currentName = nil
                insideType = false
            }
        }
    }

    if let name = currentName {
        classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                   methods: currentMethods, properties: currentProperties,
                                   isProtocol: isProtocol, isEnum: isEnum))
    }

    return classes
}

extension Character {
    var isUpperCase: Bool { String(self) == String(self).uppercased() && String(self) != String(self).lowercased() }
}

// MARK: - Colors

struct NeonPalette {
    static let cyan = NSColor(red: 0, green: 1, blue: 1, alpha: 1)
    static let magenta = NSColor(red: 1, green: 0, blue: 0.8, alpha: 1)
    static let green = NSColor(red: 0, green: 1, blue: 0.4, alpha: 1)
    static let orange = NSColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    static let purple = NSColor(red: 0.7, green: 0.3, blue: 1, alpha: 1)
    static let yellow = NSColor(red: 1, green: 1, blue: 0.2, alpha: 1)
    static let white = NSColor(red: 0.9, green: 0.9, blue: 1, alpha: 1)
    static let pink = NSColor(red: 1, green: 0.4, blue: 0.7, alpha: 1)

    static let all: [NSColor] = [cyan, magenta, green, orange, purple, yellow]
}

// MARK: - Scene Builder

class RezSceneBuilder {
    let scene = SCNScene()
    var classNodes: [String: SCNNode] = [:]
    var classPositions: [String: SCNVector3] = [:]

    func build(from classes: [ParsedClass]) {
        setupBackground()
        setupGrid()
        setupLighting()
        layoutClasses(classes)
        setupConnections(classes)
        addParticles()
    }

    private func setupBackground() {
        scene.background.contents = NSColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1)
        scene.fogStartDistance = 50
        scene.fogEndDistance = 120
        scene.fogColor = NSColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1)
    }

    private func setupGrid() {
        let gridNode = SCNNode()
        let gridSize: CGFloat = 80
        let spacing: CGFloat = 3.0

        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = NSColor(red: 0.03, green: 0.06, blue: 0.15, alpha: 1)
        gridMaterial.emission.contents = NSColor(red: 0.02, green: 0.04, blue: 0.12, alpha: 1)

        var i: CGFloat = -gridSize
        while i <= gridSize {
            let xGeo = SCNCylinder(radius: 0.012, height: gridSize * 2)
            xGeo.firstMaterial = gridMaterial
            let xNode = SCNNode(geometry: xGeo)
            xNode.position = SCNVector3(i, -8, 0)
            xNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            gridNode.addChildNode(xNode)

            let zGeo = SCNCylinder(radius: 0.012, height: gridSize * 2)
            zGeo.firstMaterial = gridMaterial
            let zNode = SCNNode(geometry: zGeo)
            zNode.position = SCNVector3(0, -8, i)
            zNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            gridNode.addChildNode(zNode)

            i += spacing
        }

        scene.rootNode.addChildNode(gridNode)
    }

    private func setupLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    // MARK: - Wireframe Box Builder

    private func makeWireframeBox(width w: CGFloat, height h: CGFloat, depth d: CGFloat, color: NSColor, edgeRadius: CGFloat = 0.035) -> SCNNode {
        let node = SCNNode()

        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 0.8

        let hw = w / 2, hh = h / 2, hd = d / 2

        let corners: [(CGFloat, CGFloat, CGFloat)] = [
            (-hw, -hh, -hd), (hw, -hh, -hd), (hw, -hh, hd), (-hw, -hh, hd),
            (-hw, hh, -hd), (hw, hh, -hd), (hw, hh, hd), (-hw, hh, hd)
        ]
        let edges: [(Int, Int)] = [
            (0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),
            (0,4),(1,5),(2,6),(3,7)
        ]

        for (a, b) in edges {
            let (x1, y1, z1) = corners[a]
            let (x2, y2, z2) = corners[b]
            let dx = x2 - x1, dy = y2 - y1, dz = z2 - z1
            let length = sqrt(dx * dx + dy * dy + dz * dz)

            let edge = SCNCylinder(radius: edgeRadius, height: length)
            edge.firstMaterial = mat
            let edgeNode = SCNNode(geometry: edge)
            edgeNode.position = SCNVector3((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2)

            let upX: CGFloat = 0, upY: CGFloat = 1, upZ: CGFloat = 0
            let crossX = upY * dz - upZ * dy
            let crossY = upZ * dx - upX * dz
            let crossZ = upX * dy - upY * dx
            let crossLen = sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ)
            let dot = upX * dx + upY * dy + upZ * dz
            let angle = atan2(crossLen, dot)
            if crossLen > 0.001 {
                edgeNode.rotation = SCNVector4(crossX / crossLen, crossY / crossLen, crossZ / crossLen, angle)
            }
            node.addChildNode(edgeNode)
        }

        // Corner glows
        for (x, y, z) in corners {
            let sphere = SCNSphere(radius: edgeRadius * 2.5)
            sphere.firstMaterial = mat
            let sn = SCNNode(geometry: sphere)
            sn.position = SCNVector3(x, y, z)
            node.addChildNode(sn)
        }

        return node
    }

    // MARK: - Label Builder

    private func makeLabel(_ text: String, color: NSColor, size: CGFloat = 0.4) -> SCNNode {
        let textGeo = SCNText(string: text, extrusionDepth: 0.02)
        textGeo.font = NSFont(name: "Menlo-Bold", size: size) ?? NSFont.systemFont(ofSize: size)
        textGeo.flatness = 0.1

        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 1.0
        textGeo.firstMaterial = mat

        let node = SCNNode(geometry: textGeo)
        let (mn, mx) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2 + mn.x, mn.y, 0)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]

        return node
    }

    // MARK: - Animations

    private func addPulseAnimation(to node: SCNNode, duration: Double = 2.0) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = duration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(pulse, forKey: "pulse")
    }

    private func addBreathAnimation(to node: SCNNode, duration: Double = 3.0) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.9
        pulse.toValue = 0.55
        pulse.duration = duration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(pulse, forKey: "breath")
    }

    private func addFloatAnimation(to node: SCNNode, amplitude: CGFloat = 0.15, duration: Double = 3.0) {
        let anim = CABasicAnimation(keyPath: "position.y")
        anim.fromValue = node.position.y - amplitude
        anim.toValue = node.position.y + amplitude
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(anim, forKey: "float")
    }

    // MARK: - Layout Classes

    private func layoutClasses(_ classes: [ParsedClass]) {
        // Assign colours per class
        let colorMap: [String: NSColor] = {
            var m: [String: NSColor] = [:]
            let palette: [NSColor] = [NeonPalette.cyan, NeonPalette.magenta, NeonPalette.green,
                                       NeonPalette.orange, NeonPalette.purple, NeonPalette.yellow]
            for (i, c) in classes.enumerated() {
                m[c.name] = palette[i % palette.count]
            }
            return m
        }()

        // Determine positions: spread on X, parents lower (y=0), children higher (y=+12)
        let typeNames = Set(classes.map { $0.name })
        let roots = classes.filter { $0.superclass == nil || !typeNames.contains($0.superclass!) }
        let children = classes.filter { $0.superclass != nil && typeNames.contains($0.superclass!) }

        var positions: [String: SCNVector3] = [:]
        var placed = Set<String>()
        let xSpacing: CGFloat = 16

        // Place roots along x at y=0
        var xCursor: CGFloat = 0
        for root in roots {
            positions[root.name] = SCNVector3(xCursor, 0, 0)
            placed.insert(root.name)
            xCursor += xSpacing
        }

        // Place children above their parents
        for child in children {
            if let parentPos = positions[child.superclass!] {
                positions[child.name] = SCNVector3(parentPos.x, parentPos.y + 12, 0)
            } else {
                positions[child.name] = SCNVector3(xCursor, 0, 0)
                xCursor += xSpacing
            }
            placed.insert(child.name)
        }

        for cls in classes where !placed.contains(cls.name) {
            positions[cls.name] = SCNVector3(xCursor, 0, 0)
            xCursor += xSpacing
            placed.insert(cls.name)
        }

        // Build each class cube
        for cls in classes {
            guard let pos = positions[cls.name] else { continue }
            let color = colorMap[cls.name] ?? NeonPalette.cyan

            let container = SCNNode()
            container.position = pos
            container.name = cls.name

            // CUBE size — big and square. Scale up for more content
            let contentCount = max(cls.methods.count, cls.properties.count)
            let cubeSize: CGFloat = max(CGFloat(7), CGFloat(4 + contentCount))

            // Main wireframe cube
            let cube = makeWireframeBox(width: cubeSize, height: cubeSize, depth: cubeSize, color: color, edgeRadius: 0.05)
            container.addChildNode(cube)
            addBreathAnimation(to: cube, duration: Double.random(in: 2.0...3.5))

            // Semi-transparent face panels for solidity
            let faceMat = SCNMaterial()
            faceMat.diffuse.contents = color.withAlphaComponent(0.03)
            faceMat.emission.contents = color.withAlphaComponent(0.02)
            faceMat.isDoubleSided = true
            let faceGeo = SCNBox(width: cubeSize - 0.1, height: cubeSize - 0.1, length: cubeSize - 0.1, chamferRadius: 0)
            faceGeo.firstMaterial = faceMat
            let faceNode = SCNNode(geometry: faceGeo)
            container.addChildNode(faceNode)

            // Class name label floating above cube
            let prefix = cls.isProtocol ? "«protocol» " : (cls.isEnum ? "«enum» " : "")
            let label = makeLabel(prefix + cls.name, color: color, size: 0.7)
            label.position = SCNVector3(0, cubeSize / 2 + 1.0, 0)
            container.addChildNode(label)
            addFloatAnimation(to: label, amplitude: 0.1, duration: 2.5)

            // --- Methods as rectangles INSIDE the cube ---
            let methodColor = color.blended(withFraction: 0.2, of: NSColor.white) ?? color
            let methodRectW: CGFloat = cubeSize * 0.7
            let methodRectH: CGFloat = 0.5
            let methodRectD: CGFloat = cubeSize * 0.3
            let methodStartY = cubeSize / 2 - 1.2
            let methodSpacing: CGFloat = max(0.9, (cubeSize - 2.0) / max(CGFloat(cls.methods.count), 1))

            for (i, method) in cls.methods.enumerated() {
                let yOff = methodStartY - CGFloat(i) * methodSpacing
                let methodBox = makeWireframeBox(width: methodRectW, height: methodRectH, depth: methodRectD,
                                                  color: methodColor, edgeRadius: 0.02)
                methodBox.position = SCNVector3(0, yOff, 0)
                container.addChildNode(methodBox)

                let mLabel = makeLabel(method, color: methodColor, size: 0.22)
                mLabel.position = SCNVector3(0, yOff + 0.35, 0)
                container.addChildNode(mLabel)

                addPulseAnimation(to: methodBox, duration: Double.random(in: 2.0...4.0))
            }

            // --- Properties as small diamond/octahedron shapes INSIDE the cube ---
            let propColor = NeonPalette.yellow.blended(withFraction: 0.3, of: color) ?? NeonPalette.yellow
            let propStartY = methodStartY - CGFloat(cls.methods.count) * methodSpacing - 0.5
            let propSpacing: CGFloat = 0.9

            for (i, prop) in cls.properties.enumerated() {
                let yOff = propStartY - CGFloat(i) * propSpacing
                // Small octahedron (sphere with low segment count for faceted look)
                let diamond = SCNSphere(radius: 0.25)
                diamond.segmentCount = 6  // faceted diamond look
                let pMat = SCNMaterial()
                pMat.diffuse.contents = propColor
                pMat.emission.contents = propColor
                pMat.emission.intensity = 0.9
                diamond.firstMaterial = pMat

                let pNode = SCNNode(geometry: diamond)
                pNode.position = SCNVector3(-cubeSize / 2 + 1.2, yOff, 0)
                container.addChildNode(pNode)
                addPulseAnimation(to: pNode, duration: Double.random(in: 1.5...2.5))

                let pLabel = makeLabel(prop, color: propColor, size: 0.2)
                pLabel.position = SCNVector3(-cubeSize / 2 + 2.0, yOff, 0)
                container.addChildNode(pLabel)
            }

            // Gentle hover
            addFloatAnimation(to: container, amplitude: 0.25, duration: Double.random(in: 4.5...6.5))

            scene.rootNode.addChildNode(container)
            classNodes[cls.name] = container
            classPositions[cls.name] = pos
        }
    }

    // MARK: - Connections

    private func makeConnectionLine(from: SCNVector3, to: SCNVector3, color: NSColor, radius: CGFloat = 0.04) -> SCNNode {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)

        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 0.7

        let cyl = SCNCylinder(radius: radius, height: length)
        cyl.firstMaterial = mat
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)

        let upX: CGFloat = 0, upY: CGFloat = 1, upZ: CGFloat = 0
        let crossX = upY * dz - upZ * dy
        let crossY = upZ * dx - upX * dz
        let crossZ = upX * dy - upY * dx
        let crossLen = sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ)
        let dot = upX * dx + upY * dy + upZ * dz
        let angle = atan2(crossLen, dot)
        if crossLen > 0.001 {
            node.rotation = SCNVector4(crossX / crossLen, crossY / crossLen, crossZ / crossLen, angle)
        }

        return node
    }

    private func makeArrowHead(at pos: SCNVector3, direction: SCNVector3, color: NSColor) -> SCNNode {
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.15, height: 0.4)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 0.9
        cone.firstMaterial = mat
        let node = SCNNode(geometry: cone)
        node.position = pos

        let dx = direction.x, dy = direction.y, dz = direction.z
        let upX: CGFloat = 0, upY: CGFloat = 1, upZ: CGFloat = 0
        let crossX = upY * dz - upZ * dy
        let crossY = upZ * dx - upX * dz
        let crossZ = upX * dy - upY * dx
        let crossLen = sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ)
        let dot = upX * dx + upY * dy + upZ * dz
        let angle = atan2(crossLen, dot)
        if crossLen > 0.001 {
            node.rotation = SCNVector4(crossX / crossLen, crossY / crossLen, crossZ / crossLen, angle)
        }

        return node
    }

    private func setupConnections(_ classes: [ParsedClass]) {
        for cls in classes {
            // Inheritance
            if let superName = cls.superclass,
               let parentPos = classPositions[superName],
               let childPos = classPositions[cls.name] {

                let lineColor = NeonPalette.cyan
                let line = makeConnectionLine(from: childPos, to: parentPos, color: lineColor, radius: 0.05)
                addPulseAnimation(to: line, duration: 1.5)
                scene.rootNode.addChildNode(line)

                // Arrow at parent end
                let dir = SCNVector3(parentPos.x - childPos.x, parentPos.y - childPos.y, parentPos.z - childPos.z)
                let arrow = makeArrowHead(at: parentPos, direction: dir, color: lineColor)
                scene.rootNode.addChildNode(arrow)

                // Label at midpoint
                let mid = SCNVector3((childPos.x + parentPos.x) / 2 + 0.5,
                                     (childPos.y + parentPos.y) / 2,
                                     (childPos.z + parentPos.z) / 2 + 0.5)
                let inheritLabel = makeLabel("inherits", color: lineColor, size: 0.35)
                inheritLabel.position = mid
                scene.rootNode.addChildNode(inheritLabel)

                // Pulse sphere traveling along connection
                let pulseSphere = SCNSphere(radius: 0.12)
                let pulseMat = SCNMaterial()
                pulseMat.diffuse.contents = lineColor
                pulseMat.emission.contents = lineColor
                pulseMat.emission.intensity = 1.0
                pulseSphere.firstMaterial = pulseMat
                let pulseNode = SCNNode(geometry: pulseSphere)
                pulseNode.position = childPos
                scene.rootNode.addChildNode(pulseNode)

                let moveUp = SCNAction.move(to: parentPos, duration: 2.0)
                let moveDown = SCNAction.move(to: childPos, duration: 2.0)
                pulseNode.runAction(SCNAction.repeatForever(SCNAction.sequence([moveUp, moveDown])))
            }

            // Protocol conformance
            for proto in cls.protocols {
                guard let protoPos = classPositions[proto],
                      let clsPos = classPositions[cls.name] else { continue }

                let lineColor = NeonPalette.purple
                let line = makeConnectionLine(from: clsPos, to: protoPos, color: lineColor, radius: 0.035)
                addPulseAnimation(to: line, duration: 2.0)
                scene.rootNode.addChildNode(line)

                let arrow = makeArrowHead(at: protoPos,
                                          direction: SCNVector3(protoPos.x - clsPos.x, protoPos.y - clsPos.y, protoPos.z - clsPos.z),
                                          color: lineColor)
                scene.rootNode.addChildNode(arrow)

                let mid = SCNVector3((clsPos.x + protoPos.x) / 2 - 0.5,
                                     (clsPos.y + protoPos.y) / 2,
                                     (clsPos.z + protoPos.z) / 2 - 0.5)
                let confLabel = makeLabel("conforms to", color: lineColor, size: 0.3)
                confLabel.position = mid
                scene.rootNode.addChildNode(confLabel)

                // Dashed pulse effect
                let pSphere = SCNSphere(radius: 0.08)
                let pMat = SCNMaterial()
                pMat.diffuse.contents = lineColor
                pMat.emission.contents = lineColor
                pMat.emission.intensity = 1.0
                pSphere.firstMaterial = pMat
                let pNode = SCNNode(geometry: pSphere)
                pNode.position = clsPos
                scene.rootNode.addChildNode(pNode)
                pNode.runAction(SCNAction.repeatForever(SCNAction.sequence([
                    SCNAction.move(to: protoPos, duration: 3.0),
                    SCNAction.move(to: clsPos, duration: 3.0)
                ])))
            }
        }
    }

    // MARK: - Particles

    private func addParticles() {
        let particleNode = SCNNode()

        for _ in 0..<100 {
            let sphere = SCNSphere(radius: CGFloat.random(in: 0.02...0.06))
            let mat = SCNMaterial()
            let color = NeonPalette.all.randomElement()!.withAlphaComponent(0.5)
            mat.diffuse.contents = color
            mat.emission.contents = color
            mat.emission.intensity = 0.8
            sphere.firstMaterial = mat

            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(
                CGFloat.random(in: -20...60),
                CGFloat.random(in: -6...20),
                CGFloat.random(in: -20...20)
            )
            addFloatAnimation(to: node, amplitude: CGFloat.random(in: 0.3...1.2), duration: Double.random(in: 3.0...8.0))
            addPulseAnimation(to: node, duration: Double.random(in: 1.0...3.0))
            particleNode.addChildNode(node)
        }

        scene.rootNode.addChildNode(particleNode)
    }
}

// MARK: - Fly-Through View with Controls

class FlyThroughView: SCNView {
    var cameraNode: SCNNode!
    var yaw: CGFloat = 0
    var pitch: CGFloat = 0
    var moveSpeed: CGFloat = 0.3
    var keysDown: Set<UInt16> = []
    var isUserControlling = false
    var orbitAngle: CGFloat = 0
    var orbitRadius: CGFloat = 30
    var orbitCenter = SCNVector3(20 as CGFloat, 4 as CGFloat, 0 as CGFloat)
    var lastMousePoint: NSPoint = .zero
    var isDragging = false

    func setupCamera() {
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 150
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.fieldOfView = 70

        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIntensity = 1.8
        cameraNode.camera?.bloomThreshold = 0.2
        cameraNode.camera?.bloomBlurRadius = 12
        cameraNode.camera?.colorFringeStrength = 2.5
        cameraNode.camera?.vignettingIntensity = 0.6
        cameraNode.camera?.vignettingPower = 1.2

        cameraNode.position = SCNVector3(20 as CGFloat, 8 as CGFloat, 30 as CGFloat)
        cameraNode.look(at: SCNVector3(20 as CGFloat, 4 as CGFloat, 0 as CGFloat))

        self.scene?.rootNode.addChildNode(cameraNode)
        self.pointOfView = cameraNode
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        keysDown.insert(event.keyCode)
        isUserControlling = true
    }

    override func keyUp(with event: NSEvent) {
        keysDown.remove(event.keyCode)
        if keysDown.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.keysDown.isEmpty == true && self?.isDragging == false {
                    self?.isUserControlling = false
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        lastMousePoint = event.locationInWindow
        isDragging = true
        isUserControlling = true
    }

    override func mouseDragged(with event: NSEvent) {
        let dx = CGFloat(event.locationInWindow.x - lastMousePoint.x) * 0.005
        let dy = CGFloat(event.locationInWindow.y - lastMousePoint.y) * 0.005
        lastMousePoint = event.locationInWindow

        yaw -= dx
        pitch = max(-CGFloat.pi / 3, min(CGFloat.pi / 3, pitch + dy))

        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0 as CGFloat)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.keysDown.isEmpty == true && self?.isDragging == false {
                self?.isUserControlling = false
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let forward = cameraNode.worldFront
        let delta = CGFloat(event.deltaY) * 0.5
        cameraNode.position.x += forward.x * delta
        cameraNode.position.y += forward.y * delta
        cameraNode.position.z += forward.z * delta
        isUserControlling = true
    }

    func tick() {
        if isUserControlling {
            let speed = moveSpeed
            let forward = cameraNode.worldFront
            let right = cameraNode.worldRight

            if keysDown.contains(13) || keysDown.contains(126) { // W / Up
                cameraNode.position.x += forward.x * speed
                cameraNode.position.y += forward.y * speed
                cameraNode.position.z += forward.z * speed
            }
            if keysDown.contains(1) || keysDown.contains(125) { // S / Down
                cameraNode.position.x -= forward.x * speed
                cameraNode.position.y -= forward.y * speed
                cameraNode.position.z -= forward.z * speed
            }
            if keysDown.contains(0) || keysDown.contains(123) { // A / Left
                cameraNode.position.x -= right.x * speed
                cameraNode.position.y -= right.y * speed
                cameraNode.position.z -= right.z * speed
            }
            if keysDown.contains(2) || keysDown.contains(124) { // D / Right
                cameraNode.position.x += right.x * speed
                cameraNode.position.y += right.y * speed
                cameraNode.position.z += right.z * speed
            }
            if keysDown.contains(12) { cameraNode.position.y += speed } // Q
            if keysDown.contains(14) { cameraNode.position.y -= speed } // E
        } else {
            orbitAngle += 0.003
            let x = orbitCenter.x + orbitRadius * cos(orbitAngle)
            let z = orbitCenter.z + orbitRadius * sin(orbitAngle)
            let y: CGFloat = orbitCenter.y + 3.0 * sin(orbitAngle * 0.3)

            cameraNode.position = SCNVector3(x, y, z)
            cameraNode.look(at: orbitCenter)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var sceneView: FlyThroughView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scriptDir: String
        if CommandLine.arguments.count > 1 {
            scriptDir = CommandLine.arguments[1]
        } else {
            // Derive from executable path
            let execPath = CommandLine.arguments[0]
            scriptDir = (execPath as NSString).deletingLastPathComponent
        }
        let swiftFile = scriptDir + "/Calculator.swift"

        print("🔍 Parsing \(swiftFile)...")
        let classes = parseSwiftFile(swiftFile)
        print("📦 Found \(classes.count) types:")
        for c in classes {
            let kind = c.isProtocol ? "protocol" : (c.isEnum ? "enum" : "class")
            print("  \(kind) \(c.name): \(c.methods.count) methods, \(c.properties.count) properties")
            if let sup = c.superclass { print("    ↑ inherits: \(sup)") }
            if !c.protocols.isEmpty { print("    ◇ conforms: \(c.protocols.joined(separator: ", "))") }
        }

        let builder = RezSceneBuilder()
        builder.build(from: classes)

        let frame = NSRect(x: 80, y: 80, width: 1400, height: 900)
        window = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        window.title = "⚡ Spatial IDE V2 — Rez Visualiser"
        window.backgroundColor = .black

        sceneView = FlyThroughView(frame: frame)
        sceneView.scene = builder.scene
        sceneView.backgroundColor = NSColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1)
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.setupCamera()

        window.contentView = sceneView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(sceneView)

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.sceneView.tick()
        }

        print("\n🎮 Controls: WASD/arrows=move, mouse drag=look, scroll=zoom, Q/E=up/down")
        print("   Auto-orbit resumes after 5s idle")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Main

@main
struct SpatialVisualiserApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
