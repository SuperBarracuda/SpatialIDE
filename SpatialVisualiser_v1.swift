import Cocoa
import SceneKit
import SwiftUI

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
        
        // Detect type declarations
        let declPatterns: [(String, Bool, Bool)] = [
            ("public class ", false, false), ("class ", false, false),
            ("public protocol ", true, false), ("protocol ", true, false),
            ("public enum ", false, true), ("enum ", false, true),
        ]
        
        for (prefix, isProt, isEn) in declPatterns {
            if trimmed.hasPrefix(prefix) && !trimmed.hasPrefix("//") {
                // Save previous
                if let name = currentName {
                    classes.append(ParsedClass(name: name, superclass: currentSuper, protocols: currentProtocols,
                                               methods: currentMethods, properties: currentProperties,
                                               isProtocol: isProtocol, isEnum: isEnum))
                }
                
                let afterPrefix = String(trimmed.dropFirst(prefix.count))
                let nameAndRest = afterPrefix.components(separatedBy: CharacterSet(charactersIn: " :{<"))
                let name = nameAndRest.first ?? afterPrefix
                
                // Parse inheritance
                var sup: String? = nil
                var prots: [String] = []
                if let colonRange = afterPrefix.range(of: ":") {
                    let inheritance = String(afterPrefix[colonRange.upperBound...])
                        .components(separatedBy: "{")[0]
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    
                    for (i, item) in inheritance.enumerated() {
                        let clean = item.components(separatedBy: " ").first ?? item
                        if i == 0 && !isProt && !isEn && clean.first?.isUpperCase == true
                            && !["Error", "CustomStringConvertible"].contains(clean) {
                            // Heuristic: first item starting with uppercase might be superclass
                            // but could also be protocol - check known classes
                            let knownProts = ["CalculatorDisplay", "Error", "CustomStringConvertible", "Codable", "Hashable", "Equatable"]
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
            
            // Methods
            if trimmed.contains("func ") && !trimmed.hasPrefix("//") {
                if let funcRange = trimmed.range(of: "func ") {
                    let afterFunc = String(trimmed[funcRange.upperBound...])
                    let methodName = afterFunc.components(separatedBy: "(").first ?? afterFunc
                    currentMethods.append(methodName)
                }
            }
            
            // Properties
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
    
    // Save last if still open
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
    static let white = NSColor(red: 0.9, green: 0.9, blue: 1, alpha: 1)
    
    static let all: [NSColor] = [cyan, magenta, green, orange, purple]
}

// MARK: - Scene Builder

class RezSceneBuilder {
    let scene = SCNScene()
    var classNodes: [String: SCNNode] = [:]
    
    func build(from classes: [ParsedClass]) {
        setupBackground()
        setupGrid()
        setupLighting()
        layoutClasses(classes)
        setupConnections(classes)
        addParticles()
    }
    
    private func setupBackground() {
        scene.background.contents = NSColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1)
        
        // Fog for depth
        scene.fogStartDistance = 30
        scene.fogEndDistance = 80
        scene.fogColor = NSColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1)
    }
    
    private func setupGrid() {
        // Ground grid
        let gridNode = SCNNode()
        let gridSize: Float = 60
        let spacing: Float = 2.0
        
        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = NSColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1)
        gridMaterial.emission.contents = NSColor(red: 0.02, green: 0.06, blue: 0.15, alpha: 1)
        
        for i in stride(from: -gridSize, through: gridSize, by: spacing) {
            // X lines
            let xGeo = SCNCylinder(radius: 0.015, height: CGFloat(gridSize * 2))
            xGeo.firstMaterial = gridMaterial
            let xNode = SCNNode(geometry: xGeo)
            xNode.position = SCNVector3(i, -5, 0)
            xNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            gridNode.addChildNode(xNode)
            
            // Z lines
            let zGeo = SCNCylinder(radius: 0.015, height: CGFloat(gridSize * 2))
            zGeo.firstMaterial = gridMaterial
            let zNode = SCNNode(geometry: zGeo)
            zNode.position = SCNVector3(0, -5, i)
            zNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            gridNode.addChildNode(zNode)
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
    
    private func makeWireframeBox(width: CGFloat, height: CGFloat, depth: CGFloat, color: NSColor) -> SCNNode {
        let node = SCNNode()
        let r: CGFloat = 0.03
        
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.emission.intensity = 0.8
        
        let hw = Float(width/2), hh = Float(height/2), hd = Float(depth/2)
        
        // 12 edges of a box
        let corners: [(Float,Float,Float)] = [
            (-hw,-hh,-hd), (hw,-hh,-hd), (hw,-hh,hd), (-hw,-hh,hd),
            (-hw,hh,-hd), (hw,hh,-hd), (hw,hh,hd), (-hw,hh,hd)
        ]
        let edges: [(Int,Int)] = [
            (0,1),(1,2),(2,3),(3,0), (4,5),(5,6),(6,7),(7,4),
            (0,4),(1,5),(2,6),(3,7)
        ]
        
        for (a,b) in edges {
            let (x1,y1,z1) = corners[a]
            let (x2,y2,z2) = corners[b]
            let dx = x2-x1, dy = y2-y1, dz = z2-z1
            let length = sqrt(dx*dx + dy*dy + dz*dz)
            
            let edge = SCNCylinder(radius: r, height: CGFloat(length))
            edge.firstMaterial = mat
            let edgeNode = SCNNode(geometry: edge)
            
            edgeNode.position = SCNVector3((x1+x2)/2, (y1+y2)/2, (z1+z2)/2)
            
            // Align cylinder to edge direction
            let up = SCNVector3(0, 1, 0)
            let dir = SCNVector3(dx, dy, dz)
            let cross = SCNVector3(up.y*dir.z - up.z*dir.y, up.z*dir.x - up.x*dir.z, up.x*dir.y - up.y*dir.x)
            let crossLen = sqrt(cross.x*cross.x + cross.y*cross.y + cross.z*cross.z)
            let dot = up.x*dir.x + up.y*dir.y + up.z*dir.z
            let angle = atan2(crossLen, dot)
            if crossLen > 0.001 {
                edgeNode.rotation = SCNVector4(cross.x/crossLen, cross.y/crossLen, cross.z/crossLen, angle)
            }
            
            node.addChildNode(edgeNode)
        }
        
        // Corner glow spheres
        for (x,y,z) in corners {
            let sphere = SCNSphere(radius: r * 2)
            sphere.firstMaterial = mat
            let sn = SCNNode(geometry: sphere)
            sn.position = SCNVector3(x, y, z)
            node.addChildNode(sn)
        }
        
        return node
    }
    
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
        // Center text
        let (min, max) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((max.x - min.x) / 2 + min.x, min.y, 0)
        
        // Billboard constraint so text faces camera
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        
        return node
    }
    
    private func addPulseAnimation(to node: SCNNode, duration: Double = 2.0) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.5
        pulse.duration = duration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(pulse, forKey: "pulse")
    }
    
    private func addFloatAnimation(to node: SCNNode, amplitude: Float = 0.15, duration: Double = 3.0) {
        let float = CABasicAnimation(keyPath: "position.y")
        float.fromValue = CGFloat(node.position.y) - CGFloat(amplitude)
        float.toValue = CGFloat(node.position.y) + CGFloat(amplitude)
        float.duration = duration
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(float, forKey: "float")
    }
    
    private func layoutClasses(_ classes: [ParsedClass]) {
        // Position assignments - manual layout for best look
        // Group: Calculator at center, ScientificCalculator above it, others around
        var positions: [String: SCNVector3] = [:]
        var colors: [String: NSColor] = [:]
        
        let typeNames = classes.map { $0.name }
        let colorList = NeonPalette.all
        for (i, cls) in classes.enumerated() {
            colors[cls.name] = colorList[i % colorList.count]
        }
        
        // Layout: spread horizontally, inheritance stacks vertically
        var placed: Set<String> = []
        var xPos: Float = 0
        let xSpacing: Float = 10
        
        // First place parents, then children above
        func placeClass(_ name: String, at pos: SCNVector3) {
            guard !placed.contains(name) else { return }
            positions[name] = pos
            placed.insert(name)
        }
        
        // Find root classes (no superclass within our set)
        let roots = classes.filter { c in c.superclass == nil || !typeNames.contains(c.superclass!) }
        let children = classes.filter { c in c.superclass != nil && typeNames.contains(c.superclass!) }
        
        for root in roots {
            placeClass(root.name, at: SCNVector3(xPos, 0, 0))
            xPos += xSpacing
        }
        
        for child in children {
            if let parentPos = positions[child.superclass!] {
                placeClass(child.name, at: SCNVector3(parentPos.x, parentPos.y + 6, parentPos.z))
            } else {
                placeClass(child.name, at: SCNVector3(xPos, 0, 0))
                xPos += xSpacing
            }
        }
        
        // Place any remaining
        for cls in classes where !placed.contains(cls.name) {
            placeClass(cls.name, at: SCNVector3(xPos, 0, 0))
            xPos += xSpacing
        }
        
        // Build nodes
        for cls in classes {
            guard let pos = positions[cls.name] else { continue }
            let color = colors[cls.name] ?? NeonPalette.cyan
            
            let containerNode = SCNNode()
            containerNode.position = pos
            containerNode.name = cls.name
            
            // Size based on complexity
            let w: CGFloat = CGFloat(3.0 + Float(cls.methods.count) * 0.2)
            let h: CGFloat = CGFloat(2.0 + Float(cls.methods.count) * 0.15)
            let d: CGFloat = 2.5
            
            // Wireframe box
            let box = makeWireframeBox(width: w, height: h, depth: d, color: color)
            containerNode.addChildNode(box)
            addPulseAnimation(to: box, duration: Double.random(in: 1.8...3.0))
            
            // Protocol conformance shell
            if !cls.protocols.isEmpty && !cls.isProtocol {
                let shell = makeWireframeBox(width: w + 0.8, height: h + 0.8, depth: d + 0.8,
                                             color: NeonPalette.purple)
                shell.opacity = 0.4
                containerNode.addChildNode(shell)
                addPulseAnimation(to: shell, duration: 4.0)
            }
            
            // Class name label
            let label = makeLabel(cls.isProtocol ? "«\(cls.name)»" : cls.name, color: color, size: 0.5)
            label.position = SCNVector3(0, Float(h/2) + 0.6, 0)
            containerNode.addChildNode(label)
            
            // Methods as small panels
            let methodSpacing: Float = 0.8
            let startY = Float(h/2) - 0.5
            for (i, method) in cls.methods.enumerated() {
                let panelWidth: CGFloat = 2.0
                let panelHeight: CGFloat = 0.4
                let panel = makeWireframeBox(width: panelWidth, height: panelHeight, depth: 0.1, color: color.withAlphaComponent(0.7))
                let yOff = startY - Float(i) * methodSpacing
                panel.position = SCNVector3(Float(w/2) + 1.5, yOff, 0)
                containerNode.addChildNode(panel)
                addFloatAnimation(to: panel, amplitude: 0.05, duration: Double.random(in: 2.0...4.0))
                
                let methodLabel = makeLabel(method, color: color, size: 0.2)
                methodLabel.position = SCNVector3(Float(w/2) + 1.5, yOff, 0.15)
                containerNode.addChildNode(methodLabel)
            }
            
            // Properties as small spheres
            for (i, prop) in cls.properties.enumerated() {
                let sphere = SCNSphere(radius: 0.15)
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.emission.contents = color
                mat.emission.intensity = 0.9
                sphere.firstMaterial = mat
                
                let sNode = SCNNode(geometry: sphere)
                let angle = Float(i) * (Float.pi * 2.0 / max(Float(cls.properties.count), 1))
                sNode.position = SCNVector3(
                    -Float(w/2) - 1.0,
                    Float(h/2) - 0.5 - Float(i) * 0.7,
                    0
                )
                containerNode.addChildNode(sNode)
                addPulseAnimation(to: sNode, duration: Double.random(in: 1.5...2.5))
                
                let propLabel = makeLabel(prop, color: color, size: 0.18)
                propLabel.position = SCNVector3(sNode.position.x - 0.4, sNode.position.y, sNode.position.z + 0.2)
                containerNode.addChildNode(propLabel)
            }
            
            // Gentle rotation
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 0.02))
            spin.duration = 8.0
            spin.autoreverses = true
            spin.repeatCount = .infinity
            containerNode.addAnimation(spin, forKey: "gentleSpin")
            
            addFloatAnimation(to: containerNode, amplitude: 0.2, duration: Double.random(in: 4.0...6.0))
            
            scene.rootNode.addChildNode(containerNode)
            classNodes[cls.name] = containerNode
        }
    }
    
    private func setupConnections(_ classes: [ParsedClass]) {
        for cls in classes {
            guard let superName = cls.superclass, let parentNode = classNodes[superName], let childNode = classNodes[cls.name] else { continue }
            
            let from = parentNode.position
            let to = childNode.position
            let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
            let length = sqrt(dx*dx + dy*dy + dz*dz)
            
            let mat = SCNMaterial()
            mat.diffuse.contents = NeonPalette.white
            mat.emission.contents = NeonPalette.cyan
            mat.emission.intensity = 0.6
            
            let cyl = SCNCylinder(radius: 0.04, height: CGFloat(length))
            cyl.firstMaterial = mat
            let connNode = SCNNode(geometry: cyl)
            connNode.position = SCNVector3((from.x+to.x)/2, (from.y+to.y)/2, (from.z+to.z)/2)
            
            let dir = SCNVector3(dx, dy, dz)
            let up = SCNVector3(0, 1, 0)
            let cross = SCNVector3(up.y*dir.z - up.z*dir.y, up.z*dir.x - up.x*dir.z, up.x*dir.y - up.y*dir.x)
            let crossLen = sqrt(cross.x*cross.x + cross.y*cross.y + cross.z*cross.z)
            let dot = up.x*dir.x + up.y*dir.y + up.z*dir.z
            let angle = atan2(crossLen, dot)
            if crossLen > 0.001 {
                connNode.rotation = SCNVector4(cross.x/crossLen, cross.y/crossLen, cross.z/crossLen, angle)
            }
            
            addPulseAnimation(to: connNode, duration: 1.5)
            scene.rootNode.addChildNode(connNode)
            
            // Animated data pulse traveling along the connection
            let pulseSphere = SCNSphere(radius: 0.1)
            let pulseMat = SCNMaterial()
            pulseMat.diffuse.contents = NeonPalette.cyan
            pulseMat.emission.contents = NeonPalette.cyan
            pulseMat.emission.intensity = 1.0
            pulseSphere.firstMaterial = pulseMat
            let pulseNode = SCNNode(geometry: pulseSphere)
            pulseNode.position = from
            scene.rootNode.addChildNode(pulseNode)
            
            let moveUp = SCNAction.move(to: to, duration: 2.0)
            let moveDown = SCNAction.move(to: from, duration: 2.0)
            let seq = SCNAction.sequence([moveUp, moveDown])
            pulseNode.runAction(SCNAction.repeatForever(seq))
        }
    }
    
    private func addParticles() {
        let particleNode = SCNNode()
        
        // Create simple floating particles
        for _ in 0..<80 {
            let sphere = SCNSphere(radius: CGFloat.random(in: 0.02...0.06))
            let mat = SCNMaterial()
            let color = NeonPalette.all.randomElement()!.withAlphaComponent(0.6)
            mat.diffuse.contents = color
            mat.emission.contents = color
            mat.emission.intensity = 0.8
            sphere.firstMaterial = mat
            
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(
                Float.random(in: -25...35),
                Float.random(in: -4...12),
                Float.random(in: -15...15)
            )
            
            addFloatAnimation(to: node, amplitude: Float.random(in: 0.3...1.0), duration: Double.random(in: 3.0...8.0))
            addPulseAnimation(to: node, duration: Double.random(in: 1.0...3.0))
            
            particleNode.addChildNode(node)
        }
        
        scene.rootNode.addChildNode(particleNode)
    }
}

// MARK: - Custom SCNView with Controls

class FlyThroughView: SCNView {
    var cameraNode: SCNNode!
    var yaw: Float = 0
    var pitch: Float = 0
    var moveSpeed: Float = 0.3
    var keysDown: Set<UInt16> = []
    var isUserControlling = false
    var orbitAngle: Float = 0
    var orbitRadius: Float = 22
    var orbitCenter = SCNVector3(15, 3, 0)
    var lastMousePoint: NSPoint = .zero
    var isDragging = false
    
    func setupCamera() {
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 100
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.fieldOfView = 70
        
        // Bloom
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIntensity = 1.5
        cameraNode.camera?.bloomThreshold = 0.3
        cameraNode.camera?.bloomBlurRadius = 10
        cameraNode.camera?.colorFringeStrength = 2
        cameraNode.camera?.vignettingIntensity = 0.5
        cameraNode.camera?.vignettingPower = 1.0
        
        cameraNode.position = SCNVector3(15, 5, 22)
        cameraNode.look(at: SCNVector3(15, 2, 0))
        
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
            // Resume orbit after 5 seconds of no input
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
        let dx = Float(event.locationInWindow.x - lastMousePoint.x) * 0.005
        let dy = Float(event.locationInWindow.y - lastMousePoint.y) * 0.005
        lastMousePoint = event.locationInWindow
        
        yaw -= dx
        pitch = max(-Float.pi/3, min(Float.pi/3, pitch + dy))
        
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
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
            // WASD movement
            let speed = CGFloat(moveSpeed)
            let forward = cameraNode.worldFront
            let right = cameraNode.worldRight
            
            // W=13, S=1, A=0, D=2, Up=126, Down=125, Left=123, Right=124
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
            // Q=12 up, E=14 down
            if keysDown.contains(12) { cameraNode.position.y += speed }
            if keysDown.contains(14) { cameraNode.position.y -= speed }
        } else {
            // Auto orbit
            orbitAngle += 0.003
            let x = orbitCenter.x + CGFloat(orbitRadius) * CGFloat(cos(orbitAngle))
            let z = orbitCenter.z + CGFloat(orbitRadius) * CGFloat(sin(orbitAngle))
            let y: CGFloat = 5 + 2 * CGFloat(sin(orbitAngle * 0.3))
            
            cameraNode.position = SCNVector3(x, y, z)
            cameraNode.look(at: orbitCenter)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var sceneView: FlyThroughView!
    var displayLink: CVDisplayLink?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Parse
        let scriptDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] :
            (ProcessInfo.processInfo.environment["SPATIAL_IDE_DIR"] ?? ".")
        let swiftFile = scriptDir + "/Calculator.swift"
        
        print("Parsing \(swiftFile)...")
        let classes = parseSwiftFile(swiftFile)
        print("Found \(classes.count) types:")
        for c in classes {
            let kind = c.isProtocol ? "protocol" : (c.isEnum ? "enum" : "class")
            print("  \(kind) \(c.name): \(c.methods.count) methods, \(c.properties.count) properties")
            if let sup = c.superclass { print("    inherits: \(sup)") }
            if !c.protocols.isEmpty { print("    conforms: \(c.protocols.joined(separator: ", "))") }
        }
        
        // Build scene
        let builder = RezSceneBuilder()
        builder.build(from: classes)
        
        // Window
        let frame = NSRect(x: 100, y: 100, width: 1280, height: 800)
        window = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        window.title = "⚡ Spatial IDE — Rez Visualiser"
        window.backgroundColor = .black
        
        // Scene view
        sceneView = FlyThroughView(frame: frame)
        sceneView.scene = builder.scene
        sceneView.backgroundColor = NSColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1)
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.setupCamera()
        
        window.contentView = sceneView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(sceneView)
        
        // Render loop
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.sceneView.tick()
        }
        
        print("\n🎮 Controls: WASD/arrows to move, mouse drag to look, scroll to zoom, Q/E up/down")
        print("   Auto-orbit resumes after 5s of no input")
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
