import Cocoa
import SceneKit

// MARK: - Swift Source Parser

struct ParsedClass {
    let name: String
    let superclass: String?
    let protocols: [String]
    let methods: [ParsedMethod]
    let properties: [ParsedProperty]
    let isProtocol: Bool
    let isEnum: Bool
    let sourceCode: String
}

struct ParsedMethod {
    let name: String
    let signature: String
    let conditionals: [String]
    let loops: [String]
    let sourceCode: String
}

struct ParsedProperty {
    let name: String
    let typeName: String
    let fullLine: String
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
    var currentMethods: [ParsedMethod] = []
    var currentProperties: [ParsedProperty] = []
    var isProtocol = false
    var isEnum = false
    var braceDepth = 0
    var insideType = false
    var typeStartLine = 0

    var insideMethod = false
    var methodName: String = ""
    var methodSignature: String = ""
    var methodBraceStart = 0
    var methodConditionals: [String] = []
    var methodLoops: [String] = []
    var methodStartLine = 0

    for (lineIdx, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        let declPatterns: [(String, Bool, Bool)] = [
            ("public class ", false, false), ("class ", false, false),
            ("public protocol ", true, false), ("protocol ", true, false),
            ("public enum ", false, true), ("enum ", false, true),
        ]

        var matchedDecl = false
        for (prefix, isProt, isEn) in declPatterns {
            if trimmed.hasPrefix(prefix) && !trimmed.hasPrefix("//") {
                if let name = currentName {
                    if insideMethod {
                        let mSrc = lines[methodStartLine...min(lineIdx - 1, lines.count - 1)].joined(separator: "\n")
                        currentMethods.append(ParsedMethod(name: methodName, signature: methodSignature, conditionals: methodConditionals, loops: methodLoops, sourceCode: mSrc))
                        insideMethod = false
                    }
                    let cSrc = lines[typeStartLine...min(lineIdx - 1, lines.count - 1)].joined(separator: "\n")
                    classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                               methods: currentMethods, properties: currentProperties,
                                               isProtocol: isProtocol, isEnum: isEnum, sourceCode: cSrc))
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
                insideMethod = false
                braceDepth = 0
                typeStartLine = lineIdx
                matchedDecl = true
                break
            }
        }

        if insideType {
            braceDepth += line.filter({ $0 == "{" }).count
            braceDepth -= line.filter({ $0 == "}" }).count

            if trimmed.contains("func ") && !trimmed.hasPrefix("//") && !matchedDecl {
                if insideMethod {
                    let mSrc = lines[methodStartLine...min(lineIdx - 1, lines.count - 1)].joined(separator: "\n")
                    currentMethods.append(ParsedMethod(name: methodName, signature: methodSignature, conditionals: methodConditionals, loops: methodLoops, sourceCode: mSrc))
                }
                if let funcRange = trimmed.range(of: "func ") {
                    let afterFunc = String(trimmed[funcRange.upperBound...])
                    methodName = afterFunc.components(separatedBy: "(").first ?? afterFunc
                    // Build signature up to the opening brace
                    let sigParts = trimmed.components(separatedBy: "{")
                    methodSignature = sigParts[0].trimmingCharacters(in: .whitespaces)
                }
                methodConditionals = []
                methodLoops = []
                methodBraceStart = braceDepth
                methodStartLine = lineIdx
                insideMethod = true
            }

            if insideMethod && !trimmed.hasPrefix("//") {
                if trimmed.hasPrefix("guard ") {
                    let cond = String(trimmed.prefix(50)).replacingOccurrences(of: " else {", with: "")
                        .replacingOccurrences(of: " else{", with: "")
                    methodConditionals.append(cond)
                } else if trimmed.hasPrefix("if ") {
                    let cond = String(trimmed.prefix(50)).replacingOccurrences(of: " {", with: "")
                    methodConditionals.append(cond)
                } else if trimmed.hasPrefix("switch ") {
                    let cond = String(trimmed.prefix(50)).replacingOccurrences(of: " {", with: "")
                    methodConditionals.append(cond)
                } else if trimmed.hasPrefix("for ") {
                    let loop = String(trimmed.prefix(50)).replacingOccurrences(of: " {", with: "")
                    methodLoops.append(loop)
                } else if trimmed.hasPrefix("while ") {
                    let loop = String(trimmed.prefix(50)).replacingOccurrences(of: " {", with: "")
                    methodLoops.append(loop)
                } else if trimmed.hasPrefix("repeat ") || trimmed == "repeat" || trimmed == "repeat{" {
                    methodLoops.append("repeat")
                }
            }

            if (trimmed.hasPrefix("public var ") || trimmed.hasPrefix("private var ") ||
                trimmed.hasPrefix("public let ") || trimmed.hasPrefix("private let ") ||
                trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ")) &&
                !trimmed.contains("func ") && !trimmed.hasPrefix("//") && braceDepth <= 1 && !insideMethod {
                let words = trimmed.components(separatedBy: " ")
                if let varIdx = words.firstIndex(where: { $0 == "var" || $0 == "let" }), varIdx + 1 < words.count {
                    let propRaw = words[varIdx + 1]
                    let propName = propRaw.components(separatedBy: ":").first?
                        .components(separatedBy: "=").first ?? propRaw
                    // Try to extract type
                    var typeName = "Unknown"
                    if let colonIdx = trimmed.range(of: ":") {
                        let afterColon = String(trimmed[colonIdx.upperBound...])
                            .components(separatedBy: "=")[0]
                            .trimmingCharacters(in: .whitespaces)
                        if !afterColon.isEmpty { typeName = afterColon }
                    }
                    currentProperties.append(ParsedProperty(name: propName, typeName: typeName, fullLine: trimmed))
                }
            }

            if braceDepth <= 0 && line.contains("}") && currentName != nil {
                if insideMethod {
                    let mSrc = lines[methodStartLine...min(lineIdx, lines.count - 1)].joined(separator: "\n")
                    currentMethods.append(ParsedMethod(name: methodName, signature: methodSignature, conditionals: methodConditionals, loops: methodLoops, sourceCode: mSrc))
                    insideMethod = false
                }
                if let name = currentName {
                    let cSrc = lines[typeStartLine...min(lineIdx, lines.count - 1)].joined(separator: "\n")
                    classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                               methods: currentMethods, properties: currentProperties,
                                               isProtocol: isProtocol, isEnum: isEnum, sourceCode: cSrc))
                }
                currentName = nil
                insideType = false
                insideMethod = false
            } else if insideMethod && braceDepth <= 1 && !trimmed.contains("func ") && line.contains("}") {
                let mSrc = lines[methodStartLine...min(lineIdx, lines.count - 1)].joined(separator: "\n")
                currentMethods.append(ParsedMethod(name: methodName, signature: methodSignature, conditionals: methodConditionals, loops: methodLoops, sourceCode: mSrc))
                insideMethod = false
            }
        }
    }

    if let name = currentName {
        if insideMethod {
            let mSrc = lines[methodStartLine...min(lines.count - 1, lines.count - 1)].joined(separator: "\n")
            currentMethods.append(ParsedMethod(name: methodName, signature: methodSignature, conditionals: methodConditionals, loops: methodLoops, sourceCode: mSrc))
        }
        let cSrc = lines[typeStartLine...lines.count - 1].joined(separator: "\n")
        classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                   methods: currentMethods, properties: currentProperties,
                                   isProtocol: isProtocol, isEnum: isEnum, sourceCode: cSrc))
    }

    return classes
}

extension Character {
    var isUpperCase: Bool { String(self) == String(self).uppercased() && String(self) != String(self).lowercased() }
}

// MARK: - Node Metadata

enum NodeKind {
    case classNode(ParsedClass)
    case methodNode(ParsedMethod, ParsedClass)
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
    static let redOrange = NSColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)
    static let gold = NSColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)

    static let all: [NSColor] = [cyan, magenta, green, orange, purple, yellow]
}

// MARK: - Scene Builder

class RezSceneBuilder {
    let scene = SCNScene()
    var classNodes: [String: SCNNode] = [:]
    var classPositions: [String: SCNVector3] = [:]
    var nodeMetadata: [String: NodeKind] = [:]
    var classColors: [String: NSColor] = [:]
    var connectionNodes: [String: [SCNNode]] = [:] // className -> connection line nodes

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
        mat.emission.intensity = 0.4

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

        for (x, y, z) in corners {
            let sphere = SCNSphere(radius: edgeRadius * 2.5)
            sphere.firstMaterial = mat
            let sn = SCNNode(geometry: sphere)
            sn.position = SCNVector3(x, y, z)
            node.addChildNode(sn)
        }

        return node
    }

    // MARK: - Hit-testable solid box (invisible, for click detection)

    private func makeHitBox(width w: CGFloat, height h: CGFloat, depth d: CGFloat, name: String) -> SCNNode {
        let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.clear
        mat.transparency = 0.001
        box.firstMaterial = mat
        let node = SCNNode(geometry: box)
        node.name = name
        return node
    }

    // MARK: - Pyramid Builder

    private func makePyramid(size: CGFloat, color: NSColor) -> SCNNode {
        let pyramid = SCNPyramid(width: size, height: size * 1.2, length: size)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 0.5
        mat.isDoubleSided = true
        pyramid.firstMaterial = mat
        let node = SCNNode(geometry: pyramid)
        node.pivot = SCNMatrix4MakeTranslation(0, size * 0.6, 0)
        return node
    }

    // MARK: - Glowing Sphere Builder

    private func makeGlowSphere(radius: CGFloat, color: NSColor) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 0.5
        sphere.firstMaterial = mat
        let node = SCNNode(geometry: sphere)
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
        mat.emission.intensity = 0.5
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

    private func addSpinAnimation(to node: SCNNode, duration: Double = 3.0) {
        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, CGFloat.pi * 2))
        spin.duration = duration
        spin.repeatCount = .infinity
        node.addAnimation(spin, forKey: "spin")
    }

    // MARK: - Layout Classes

    private func layoutClasses(_ classes: [ParsedClass]) {
        let colorMap: [String: NSColor] = {
            var m: [String: NSColor] = [:]
            let palette: [NSColor] = [NeonPalette.cyan, NeonPalette.magenta, NeonPalette.green,
                                       NeonPalette.orange, NeonPalette.purple, NeonPalette.yellow]
            for (i, c) in classes.enumerated() {
                m[c.name] = palette[i % palette.count]
            }
            return m
        }()
        self.classColors = colorMap

        let typeNames = Set(classes.map { $0.name })
        let roots = classes.filter { $0.superclass == nil || !typeNames.contains($0.superclass!) }
        let children = classes.filter { $0.superclass != nil && typeNames.contains($0.superclass!) }

        var positions: [String: SCNVector3] = [:]
        var placed = Set<String>()
        let xSpacing: CGFloat = 16

        var xCursor: CGFloat = 0
        for root in roots {
            positions[root.name] = SCNVector3(xCursor, 0, 0)
            placed.insert(root.name)
            xCursor += xSpacing
        }

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

        for cls in classes {
            guard let pos = positions[cls.name] else { continue }
            let color = colorMap[cls.name] ?? NeonPalette.cyan

            let container = SCNNode()
            container.position = pos
            container.name = "class_\(cls.name)"

            // Register metadata
            nodeMetadata["class_\(cls.name)"] = .classNode(cls)

            let totalInnerItems = cls.methods.reduce(0) { $0 + 1 + $1.conditionals.count + $1.loops.count }
            let contentCount = max(totalInnerItems, cls.properties.count)
            let cubeSize: CGFloat = max(CGFloat(8), CGFloat(4 + contentCount))

            // Main wireframe cube
            let cube = makeWireframeBox(width: cubeSize, height: cubeSize, depth: cubeSize, color: color, edgeRadius: 0.05)
            container.addChildNode(cube)
            addBreathAnimation(to: cube, duration: Double.random(in: 2.0...3.5))

            // Invisible hit-test box for the class
            let hitBox = makeHitBox(width: cubeSize, height: cubeSize, depth: cubeSize, name: "class_\(cls.name)")
            container.addChildNode(hitBox)

            // Semi-transparent face panels
            let faceMat = SCNMaterial()
            faceMat.diffuse.contents = color.withAlphaComponent(0.03)
            faceMat.emission.contents = color.withAlphaComponent(0.02)
            faceMat.isDoubleSided = true
            let faceGeo = SCNBox(width: cubeSize - 0.1, height: cubeSize - 0.1, length: cubeSize - 0.1, chamferRadius: 0)
            faceGeo.firstMaterial = faceMat
            let faceNode = SCNNode(geometry: faceGeo)
            container.addChildNode(faceNode)

            // Class name label
            let prefix = cls.isProtocol ? "«protocol» " : (cls.isEnum ? "«enum» " : "")
            let label = makeLabel(prefix + cls.name, color: color, size: 0.7)
            label.position = SCNVector3(0, cubeSize / 2 + 1.0, 0)
            container.addChildNode(label)
            addFloatAnimation(to: label, amplitude: 0.1, duration: 2.5)

            // --- Methods as rectangles INSIDE the cube ---
            let methodColor = color.blended(withFraction: 0.2, of: NSColor.white) ?? color
            let methodRectW: CGFloat = cubeSize * 0.65
            let methodRectD: CGFloat = cubeSize * 0.3

            var yCursor = cubeSize / 2 - 1.2

            for method in cls.methods {
                let innerCount = method.conditionals.count + method.loops.count
                let methodRectH: CGFloat = max(0.6, CGFloat(innerCount) * 0.55 + 0.6)

                let methodBox = makeWireframeBox(width: methodRectW, height: methodRectH, depth: methodRectD,
                                                  color: methodColor, edgeRadius: 0.02)
                methodBox.position = SCNVector3(0, yCursor, 0)
                methodBox.renderingOrder = 10
                container.addChildNode(methodBox)

                // Invisible hit box for method
                let methodKey = "method_\(cls.name)_\(method.name)"
                let mHit = makeHitBox(width: methodRectW, height: methodRectH, depth: methodRectD, name: methodKey)
                mHit.position = SCNVector3(0, yCursor, 0)
                container.addChildNode(mHit)
                nodeMetadata[methodKey] = .methodNode(method, cls)

                let mLabel = makeLabel(method.name, color: methodColor, size: 0.22)
                mLabel.position = SCNVector3(0, yCursor + methodRectH / 2 + 0.2, 0)
                container.addChildNode(mLabel)

                addPulseAnimation(to: methodBox, duration: Double.random(in: 2.0...4.0))

                // --- Conditionals as PYRAMIDS ---
                let condColor = NeonPalette.redOrange
                var innerX: CGFloat = -methodRectW / 2 + 0.6
                let innerY = yCursor
                let innerSpacingX: CGFloat = 1.2

                for cond in method.conditionals {
                    let pyramidNode = makePyramid(size: 0.35, color: condColor)
                    pyramidNode.position = SCNVector3(innerX, innerY, 0)
                    container.addChildNode(pyramidNode)
                    addPulseAnimation(to: pyramidNode, duration: Double.random(in: 1.5...2.5))

                    let shortCond = cond.count > 20 ? String(cond.prefix(20)) + "…" : cond
                    let cLabel = makeLabel(shortCond, color: condColor, size: 0.13)
                    cLabel.position = SCNVector3(innerX, innerY - 0.3, 0)
                    container.addChildNode(cLabel)

                    innerX += innerSpacingX
                }

                // --- Loops as SPHERES ---
                let loopColor = NeonPalette.gold
                for loop in method.loops {
                    let sphereNode = makeGlowSphere(radius: 0.2, color: loopColor)
                    sphereNode.position = SCNVector3(innerX, innerY, 0)
                    container.addChildNode(sphereNode)
                    addSpinAnimation(to: sphereNode, duration: Double.random(in: 2.0...4.0))
                    addPulseAnimation(to: sphereNode, duration: Double.random(in: 1.5...2.5))

                    let lLabel = makeLabel(loop.count > 20 ? String(loop.prefix(20)) + "…" : loop, color: loopColor, size: 0.13)
                    lLabel.position = SCNVector3(innerX, innerY - 0.3, 0)
                    container.addChildNode(lLabel)

                    innerX += innerSpacingX
                }

                yCursor -= methodRectH + 0.4
            }

            // --- Properties as small diamonds ---
            let propColor = NeonPalette.yellow.blended(withFraction: 0.3, of: color) ?? NeonPalette.yellow
            let propSpacing: CGFloat = 0.9

            for (i, prop) in cls.properties.enumerated() {
                let yOff = yCursor - CGFloat(i) * propSpacing
                let diamond = SCNSphere(radius: 0.25)
                diamond.segmentCount = 6
                let pMat = SCNMaterial()
                pMat.diffuse.contents = propColor
                pMat.emission.contents = propColor
                pMat.emission.intensity = 0.45
                diamond.firstMaterial = pMat

                let pNode = SCNNode(geometry: diamond)
                pNode.position = SCNVector3(-cubeSize / 2 + 1.2, yOff, 0)
                container.addChildNode(pNode)
                addPulseAnimation(to: pNode, duration: Double.random(in: 1.5...2.5))

                let pLabel = makeLabel(prop.name, color: propColor, size: 0.2)
                pLabel.position = SCNVector3(-cubeSize / 2 + 2.0, yOff, 0)
                container.addChildNode(pLabel)
            }

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
        mat.emission.intensity = 0.35

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
        mat.emission.intensity = 0.45
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
            var clsConnections: [SCNNode] = []

            if let superName = cls.superclass,
               let parentPos = classPositions[superName],
               let childPos = classPositions[cls.name] {

                let lineColor = NeonPalette.cyan
                let line = makeConnectionLine(from: childPos, to: parentPos, color: lineColor, radius: 0.05)
                line.name = "conn_\(cls.name)"
                addPulseAnimation(to: line, duration: 1.5)
                scene.rootNode.addChildNode(line)
                clsConnections.append(line)

                let dir = SCNVector3(parentPos.x - childPos.x, parentPos.y - childPos.y, parentPos.z - childPos.z)
                let arrow = makeArrowHead(at: parentPos, direction: dir, color: lineColor)
                arrow.name = "conn_\(cls.name)"
                scene.rootNode.addChildNode(arrow)
                clsConnections.append(arrow)

                let mid = SCNVector3((childPos.x + parentPos.x) / 2 + 0.5,
                                     (childPos.y + parentPos.y) / 2,
                                     (childPos.z + parentPos.z) / 2 + 0.5)
                let inheritLabel = makeLabel("inherits", color: lineColor, size: 0.35)
                inheritLabel.position = mid
                inheritLabel.name = "conn_\(cls.name)"
                scene.rootNode.addChildNode(inheritLabel)
                clsConnections.append(inheritLabel)

                let pulseSphere = SCNSphere(radius: 0.12)
                let pulseMat = SCNMaterial()
                pulseMat.diffuse.contents = lineColor
                pulseMat.emission.contents = lineColor
                pulseMat.emission.intensity = 0.5
                pulseSphere.firstMaterial = pulseMat
                let pulseNode = SCNNode(geometry: pulseSphere)
                pulseNode.position = childPos
                pulseNode.name = "conn_\(cls.name)"
                scene.rootNode.addChildNode(pulseNode)
                clsConnections.append(pulseNode)

                let moveUp = SCNAction.move(to: parentPos, duration: 2.0)
                let moveDown = SCNAction.move(to: childPos, duration: 2.0)
                pulseNode.runAction(SCNAction.repeatForever(SCNAction.sequence([moveUp, moveDown])))
            }

            for proto in cls.protocols {
                guard let protoPos = classPositions[proto],
                      let clsPos = classPositions[cls.name] else { continue }

                let lineColor = NeonPalette.purple
                let line = makeConnectionLine(from: clsPos, to: protoPos, color: lineColor, radius: 0.035)
                line.name = "conn_\(cls.name)"
                addPulseAnimation(to: line, duration: 2.0)
                scene.rootNode.addChildNode(line)
                clsConnections.append(line)

                let arrow = makeArrowHead(at: protoPos,
                                          direction: SCNVector3(protoPos.x - clsPos.x, protoPos.y - clsPos.y, protoPos.z - clsPos.z),
                                          color: lineColor)
                arrow.name = "conn_\(cls.name)"
                scene.rootNode.addChildNode(arrow)
                clsConnections.append(arrow)

                let mid = SCNVector3((clsPos.x + protoPos.x) / 2 - 0.5,
                                     (clsPos.y + protoPos.y) / 2,
                                     (clsPos.z + protoPos.z) / 2 - 0.5)
                let confLabel = makeLabel("conforms to", color: lineColor, size: 0.3)
                confLabel.position = mid
                confLabel.name = "conn_\(cls.name)"
                scene.rootNode.addChildNode(confLabel)
                clsConnections.append(confLabel)

                let pSphere = SCNSphere(radius: 0.08)
                let pMat = SCNMaterial()
                pMat.diffuse.contents = lineColor
                pMat.emission.contents = lineColor
                pMat.emission.intensity = 0.5
                pSphere.firstMaterial = pMat
                let pNode = SCNNode(geometry: pSphere)
                pNode.position = clsPos
                pNode.name = "conn_\(cls.name)"
                scene.rootNode.addChildNode(pNode)
                clsConnections.append(pNode)
                pNode.runAction(SCNAction.repeatForever(SCNAction.sequence([
                    SCNAction.move(to: protoPos, duration: 3.0),
                    SCNAction.move(to: clsPos, duration: 3.0)
                ])))
            }

            connectionNodes[cls.name] = clsConnections
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
            mat.emission.intensity = 0.4
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

// MARK: - Detail Overlay Panel

class DetailOverlayPanel: NSPanel {
    let scrollView: NSScrollView
    let textView: NSTextView

    init() {
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 560))
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 560))

        let panelRect = NSRect(x: 100, y: 100, width: 480, height: 580)
        super.init(contentRect: panelRect,
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        self.isFloatingPanel = true
        self.level = .floating
        self.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 0.92)
        self.isOpaque = false
        self.hasShadow = true
        self.title = "Inspector"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 580))

        // Neon border view
        let borderView = NeonBorderView(frame: NSRect(x: 4, y: 4, width: 472, height: 572))
        container.addSubview(borderView)

        scrollView.frame = NSRect(x: 10, y: 10, width: 460, height: 560)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isRichText = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        container.addSubview(scrollView)

        self.contentView = container
    }

    func showClassDetail(_ cls: ParsedClass, color: NSColor) {
        let attrStr = NSMutableAttributedString()

        let titleFont = NSFont(name: "Menlo-Bold", size: 18) ?? NSFont.boldSystemFont(ofSize: 18)
        let headingFont = NSFont(name: "Menlo-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        let bodyFont = NSFont(name: "Menlo", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let codeFont = NSFont(name: "Menlo", size: 10) ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let neonColor = color
        let dimColor = NSColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1)
        let brightWhite = NSColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1)

        // Title
        let kind = cls.isProtocol ? "«protocol»" : (cls.isEnum ? "«enum»" : "«class»")
        attrStr.append(NSAttributedString(string: "\(kind)\n", attributes: [.foregroundColor: dimColor, .font: bodyFont]))
        attrStr.append(NSAttributedString(string: "\(cls.name)\n\n", attributes: [.foregroundColor: neonColor, .font: titleFont]))

        // Inheritance
        if let sup = cls.superclass {
            attrStr.append(NSAttributedString(string: "Inherits from: ", attributes: [.foregroundColor: dimColor, .font: headingFont]))
            attrStr.append(NSAttributedString(string: "\(sup)\n", attributes: [.foregroundColor: NeonPalette.cyan, .font: headingFont]))
        }

        // Protocols
        if !cls.protocols.isEmpty {
            attrStr.append(NSAttributedString(string: "Conforms to: ", attributes: [.foregroundColor: dimColor, .font: headingFont]))
            attrStr.append(NSAttributedString(string: "\(cls.protocols.joined(separator: ", "))\n", attributes: [.foregroundColor: NeonPalette.purple, .font: headingFont]))
        }
        attrStr.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))

        // Properties
        if !cls.properties.isEmpty {
            attrStr.append(NSAttributedString(string: "━━ Properties ━━\n", attributes: [.foregroundColor: NeonPalette.yellow, .font: headingFont]))
            for prop in cls.properties {
                attrStr.append(NSAttributedString(string: "  ◆ \(prop.name)", attributes: [.foregroundColor: NeonPalette.yellow, .font: bodyFont]))
                attrStr.append(NSAttributedString(string: " : \(prop.typeName)\n", attributes: [.foregroundColor: dimColor, .font: bodyFont]))
            }
            attrStr.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        }

        // Methods
        if !cls.methods.isEmpty {
            attrStr.append(NSAttributedString(string: "━━ Methods ━━\n", attributes: [.foregroundColor: NeonPalette.green, .font: headingFont]))
            for method in cls.methods {
                attrStr.append(NSAttributedString(string: "  ▸ \(method.signature)\n", attributes: [.foregroundColor: brightWhite, .font: bodyFont]))
                for c in method.conditionals {
                    attrStr.append(NSAttributedString(string: "    🔺 \(c)\n", attributes: [.foregroundColor: NeonPalette.redOrange, .font: codeFont]))
                }
                for l in method.loops {
                    attrStr.append(NSAttributedString(string: "    🔵 \(l)\n", attributes: [.foregroundColor: NeonPalette.gold, .font: codeFont]))
                }
            }
            attrStr.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        }

        // Source code
        attrStr.append(NSAttributedString(string: "━━ Source Code ━━\n", attributes: [.foregroundColor: neonColor, .font: headingFont]))
        attrStr.append(NSAttributedString(string: cls.sourceCode + "\n", attributes: [.foregroundColor: dimColor, .font: codeFont]))

        textView.textStorage?.setAttributedString(attrStr)
        self.title = "⚡ \(cls.name)"
        self.orderFront(nil)
    }

    func showMethodDetail(_ method: ParsedMethod, parentClass: ParsedClass, color: NSColor) {
        let attrStr = NSMutableAttributedString()

        let titleFont = NSFont(name: "Menlo-Bold", size: 16) ?? NSFont.boldSystemFont(ofSize: 16)
        let headingFont = NSFont(name: "Menlo-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        let bodyFont = NSFont(name: "Menlo", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let codeFont = NSFont(name: "Menlo", size: 10) ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let neonColor = color
        let dimColor = NSColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1)

        attrStr.append(NSAttributedString(string: "Method\n", attributes: [.foregroundColor: dimColor, .font: bodyFont]))
        attrStr.append(NSAttributedString(string: "\(method.name)\n", attributes: [.foregroundColor: neonColor, .font: titleFont]))
        attrStr.append(NSAttributedString(string: "in \(parentClass.name)\n\n", attributes: [.foregroundColor: dimColor, .font: bodyFont]))

        // Signature
        attrStr.append(NSAttributedString(string: "━━ Signature ━━\n", attributes: [.foregroundColor: NeonPalette.green, .font: headingFont]))
        attrStr.append(NSAttributedString(string: "\(method.signature)\n\n", attributes: [.foregroundColor: NSColor.white, .font: bodyFont]))

        // Conditionals
        if !method.conditionals.isEmpty {
            attrStr.append(NSAttributedString(string: "━━ Conditionals ━━\n", attributes: [.foregroundColor: NeonPalette.redOrange, .font: headingFont]))
            for c in method.conditionals {
                attrStr.append(NSAttributedString(string: "  🔺 \(c)\n", attributes: [.foregroundColor: NeonPalette.redOrange, .font: bodyFont]))
            }
            attrStr.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        }

        // Loops
        if !method.loops.isEmpty {
            attrStr.append(NSAttributedString(string: "━━ Loops ━━\n", attributes: [.foregroundColor: NeonPalette.gold, .font: headingFont]))
            for l in method.loops {
                attrStr.append(NSAttributedString(string: "  🔵 \(l)\n", attributes: [.foregroundColor: NeonPalette.gold, .font: bodyFont]))
            }
            attrStr.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        }

        // Source
        attrStr.append(NSAttributedString(string: "━━ Source Code ━━\n", attributes: [.foregroundColor: neonColor, .font: headingFont]))
        attrStr.append(NSAttributedString(string: method.sourceCode + "\n", attributes: [.foregroundColor: dimColor, .font: codeFont]))

        textView.textStorage?.setAttributedString(attrStr)
        self.title = "⚡ \(parentClass.name).\(method.name)()"
        self.orderFront(nil)
    }
}

// MARK: - Neon Border View

class NeonBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        path.lineWidth = 2.0
        NeonPalette.cyan.withAlphaComponent(0.6).setStroke()
        path.stroke()
    }
}

// MARK: - Fly-Through View with Controls + Hit Testing

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

    var sceneBuilder: RezSceneBuilder?
    var detailPanel: DetailOverlayPanel?

    // Hover tracking
    var hoveredNodeName: String? = nil
    var selectedNodeName: String? = nil

    // Original emission intensities for restore
    var originalEmissions: [String: CGFloat] = [:]

    func setupCamera() {
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 150
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.fieldOfView = 70

        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIntensity = 0.8
        cameraNode.camera?.bloomThreshold = 0.2
        cameraNode.camera?.bloomBlurRadius = 6
        cameraNode.camera?.colorFringeStrength = 2.5
        cameraNode.camera?.vignettingIntensity = 0.6
        cameraNode.camera?.vignettingPower = 1.2

        cameraNode.position = SCNVector3(20 as CGFloat, 8 as CGFloat, 30 as CGFloat)
        cameraNode.look(at: SCNVector3(20 as CGFloat, 4 as CGFloat, 0 as CGFloat))

        self.scene?.rootNode.addChildNode(cameraNode)
        self.pointOfView = cameraNode
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Keyboard

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

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        lastMousePoint = event.locationInWindow
        isDragging = false

        // Hit test for click inspection
        let loc = self.convert(event.locationInWindow, from: nil)
        let hits = self.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

        for hit in hits {
            if let nodeName = findMetadataName(hit.node) {
                handleClick(nodeName: nodeName)
                return
            }
        }

        // Clicked empty space - dismiss panel
        if let panel = detailPanel, panel.isVisible {
            panel.orderOut(nil)
        }
        clearSelection()

        isDragging = true
        isUserControlling = true
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        let dx = CGFloat(event.locationInWindow.x - lastMousePoint.x) * 0.005
        let dy = CGFloat(event.locationInWindow.y - lastMousePoint.y) * 0.005
        lastMousePoint = event.locationInWindow

        yaw -= dx
        pitch = max(-CGFloat.pi / 3, min(CGFloat.pi / 3, pitch + dy))

        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0 as CGFloat)
        isUserControlling = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.keysDown.isEmpty == true && self?.isDragging == false {
                self?.isUserControlling = false
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        let hits = self.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

        var foundName: String? = nil
        for hit in hits {
            if let name = findMetadataName(hit.node) {
                foundName = name
                break
            }
        }

        if foundName != hoveredNodeName {
            // Unhover previous
            if let prev = hoveredNodeName, prev != selectedNodeName {
                setNodeGlow(prev, bright: false)
            }
            // Hover new
            if let name = foundName {
                setNodeGlow(name, bright: true)
            }
            hoveredNodeName = foundName

            // Cursor
            if foundName != nil {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func scrollWheel(with event: NSEvent) {
        let forward = cameraNode.worldFront
        let delta = CGFloat(event.deltaY) * 0.5
        cameraNode.position.x += forward.x * delta
        cameraNode.position.y += forward.y * delta
        cameraNode.position.z += forward.z * delta
        isUserControlling = true
    }

    // MARK: - Hit test helpers

    private func findMetadataName(_ node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let n = current {
            if let name = n.name, sceneBuilder?.nodeMetadata[name] != nil {
                return name
            }
            current = n.parent
        }
        return nil
    }

    private func classNameFromNodeName(_ nodeName: String) -> String {
        if nodeName.hasPrefix("class_") {
            return String(nodeName.dropFirst(6))
        } else if nodeName.hasPrefix("method_") {
            let parts = nodeName.dropFirst(7).components(separatedBy: "_")
            return parts.first ?? ""
        }
        return ""
    }

    // MARK: - Glow / Selection

    private func setNodeGlow(_ nodeName: String, bright: Bool) {
        let className = classNameFromNodeName(nodeName)
        guard let builder = sceneBuilder, let containerNode = builder.classNodes[className] else { return }

        let intensity: CGFloat = bright ? 1.0 : 0.4
        applyEmissionIntensity(containerNode, intensity: intensity)

        // Also glow connection lines
        if let conns = builder.connectionNodes[className] {
            let connIntensity: CGFloat = bright ? 2.0 : 0.7
            for conn in conns {
                applyEmissionIntensity(conn, intensity: connIntensity)
            }
        }
    }

    private func applyEmissionIntensity(_ node: SCNNode, intensity: CGFloat) {
        if let geo = node.geometry {
            for mat in geo.materials {
                mat.emission.intensity = intensity
            }
        }
        for child in node.childNodes {
            applyEmissionIntensity(child, intensity: intensity)
        }
    }

    private func clearSelection() {
        if let prev = selectedNodeName {
            setNodeGlow(prev, bright: false)
        }
        selectedNodeName = nil
    }

    // MARK: - Click handler

    private func handleClick(nodeName: String) {
        guard let builder = sceneBuilder, let meta = builder.nodeMetadata[nodeName] else { return }

        // Clear previous
        clearSelection()
        selectedNodeName = nodeName

        // Highlight selected
        setNodeGlow(nodeName, bright: true)

        // Pulse animation on selected container
        let className = classNameFromNodeName(nodeName)
        if let container = builder.classNodes[className] {
            let scaleUp = SCNAction.scale(to: 1.08, duration: 0.15)
            let scaleDown = SCNAction.scale(to: 1.0, duration: 0.15)
            container.runAction(SCNAction.sequence([scaleUp, scaleDown, scaleUp, scaleDown]))
        }

        let color = builder.classColors[className] ?? NeonPalette.cyan

        if detailPanel == nil {
            detailPanel = DetailOverlayPanel()
        }

        // Position panel near the window
        if let win = self.window {
            let winFrame = win.frame
            let panelX = winFrame.maxX + 10
            let panelY = winFrame.midY - 290
            detailPanel?.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        }

        switch meta {
        case .classNode(let cls):
            detailPanel?.showClassDetail(cls, color: color)
        case .methodNode(let method, let cls):
            detailPanel?.showMethodDetail(method, parentClass: cls, color: color)
        }
    }

    // MARK: - Tick

    func tick() {
        if isUserControlling {
            let speed = moveSpeed
            let forward = cameraNode.worldFront
            let right = cameraNode.worldRight

            if keysDown.contains(13) || keysDown.contains(126) {
                cameraNode.position.x += forward.x * speed
                cameraNode.position.y += forward.y * speed
                cameraNode.position.z += forward.z * speed
            }
            if keysDown.contains(1) || keysDown.contains(125) {
                cameraNode.position.x -= forward.x * speed
                cameraNode.position.y -= forward.y * speed
                cameraNode.position.z -= forward.z * speed
            }
            if keysDown.contains(0) || keysDown.contains(123) {
                cameraNode.position.x -= right.x * speed
                cameraNode.position.y -= right.y * speed
                cameraNode.position.z -= right.z * speed
            }
            if keysDown.contains(2) || keysDown.contains(124) {
                cameraNode.position.x += right.x * speed
                cameraNode.position.y += right.y * speed
                cameraNode.position.z += right.z * speed
            }
            if keysDown.contains(12) { cameraNode.position.y += speed }
            if keysDown.contains(14) { cameraNode.position.y -= speed }
        } else {
            orbitAngle += 0.001
            let x = orbitCenter.x + orbitRadius * cos(orbitAngle)
            let z = orbitCenter.z + orbitRadius * sin(orbitAngle)
            let y: CGFloat = orbitCenter.y

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
        let swiftFile: String
        if CommandLine.arguments.count > 1 {
            swiftFile = CommandLine.arguments[1] + "/Calculator.swift"
        } else if let resourcePath = Bundle.main.path(forResource: "Calculator", ofType: "swift") {
            swiftFile = resourcePath
        } else {
            let execPath = CommandLine.arguments[0]
            let scriptDir = (execPath as NSString).deletingLastPathComponent
            swiftFile = scriptDir + "/Calculator.swift"
        }

        print("🔍 Parsing \(swiftFile)...")
        let classes = parseSwiftFile(swiftFile)
        print("📦 Found \(classes.count) types:")
        for c in classes {
            let kind = c.isProtocol ? "protocol" : (c.isEnum ? "enum" : "class")
            print("  \(kind) \(c.name): \(c.methods.count) methods, \(c.properties.count) properties")
            if let sup = c.superclass { print("    ↑ inherits: \(sup)") }
            if !c.protocols.isEmpty { print("    ◇ conforms: \(c.protocols.joined(separator: ", "))") }
            for m in c.methods {
                if !m.conditionals.isEmpty { print("    🔺 \(m.name) conditionals: \(m.conditionals)") }
                if !m.loops.isEmpty { print("    🔵 \(m.name) loops: \(m.loops)") }
            }
        }

        let builder = RezSceneBuilder()
        builder.build(from: classes)

        let frame = NSRect(x: 80, y: 80, width: 1400, height: 900)
        window = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        window.title = "⚡ Spatial IDE V4 — Rez Visualiser (Click to Inspect)"
        window.backgroundColor = .black

        sceneView = FlyThroughView(frame: frame)
        sceneView.scene = builder.scene
        sceneView.sceneBuilder = builder
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
        print("   🖱️  CLICK on class cubes or method rectangles to inspect!")
        print("   Auto-orbit resumes after 5s idle")
        print("   🔺 Pyramids = conditionals (if/guard/switch)")
        print("   🟡 Spheres = loops (for/while/repeat)")
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
