# SpatialIDE — Architecture Plan

## Current State
- Single 1,620-line Swift file (`SpatialVisualiser.swift`)
- Everything monolithic: parser, layout, rendering, UI, app lifecycle
- macOS ARM only (Cocoa + SceneKit)
- No tests, no modularity, no CLI interface
- v1-v5 evolution files preserved for reference

## Goals
1. **SDK**: Reusable Swift package — parser + layout engine usable by anyone
2. **x86 Support**: Runs on Intel Mac hardware (Mac Pro 2019) as well as Apple Silicon
3. **Clean Architecture**: Separated concerns, testable, extensible
4. **Preserve the Vibe**: Rez/Tron neon aesthetic stays — it's the soul of the project

---

## Proposed Structure

```
SpatialIDE/
├── Package.swift                    # Swift Package Manager manifest
├── ARCHITECTURE.md                  # This file
├── README.md
│
├── Sources/
│   ├── SpatialIDECore/              # 🧠 CROSS-PLATFORM SDK (pure Swift)
│   │   ├── Parser/
│   │   │   ├── SwiftParser.swift    # Swift source file parser
│   │   │   └── LanguageParser.swift # Protocol for future language support
│   │   ├── Model/
│   │   │   ├── ParsedClass.swift    # Class/struct/enum/protocol model
│   │   │   ├── ParsedMethod.swift   # Method model
│   │   │   ├── ParsedProperty.swift # Property model
│   │   │   ├── Workspace.swift      # Collection of parsed files
│   │   │   └── Connection.swift     # Inheritance/protocol relationships
│   │   ├── Layout/
│   │   │   ├── LayoutEngine.swift   # 3D positioning algorithm
│   │   │   ├── GraphLayout.swift    # Force-directed / orbital layout
│   │   │   └── LayoutConfig.swift   # Spacing, scaling parameters
│   │   └── Export/
│   │       ├── SceneExporter.swift  # Protocol for scene export
│   │       └── JSONExporter.swift   # Export scene graph as JSON
│   │
│   ├── SpatialIDECLI/               # 💻 COMMAND-LINE TOOL (cross-platform)
│   │   └── main.swift               # CLI entry point
│   │                                # - Parse directory/file
│   │                                # - Output JSON scene graph
│   │                                # - Stats/analysis mode
│   │
│   └── SpatialIDEApp/               # 🖥️ macOS APP (Apple platforms only)
│       ├── AppDelegate.swift        # App lifecycle
│       ├── SceneBuilder.swift       # SceneKit scene construction
│       ├── NeonPalette.swift        # Rez/Tron colour palette
│       ├── InspectorPanel.swift     # Click-to-inspect source viewer
│       ├── WorkspaceBrowser.swift   # File/directory picker
│       └── CameraController.swift  # 3D navigation
│
├── Tests/
│   ├── SpatialIDECoreTests/
│   │   ├── ParserTests.swift        # Parser accuracy tests
│   │   ├── LayoutTests.swift        # Layout algorithm tests
│   │   └── ExportTests.swift        # JSON export tests
│   └── Fixtures/
│       ├── Calculator.swift         # Test fixture (already have this)
│       └── SampleProject/           # Multi-file test fixture
│
└── Legacy/                          # 📦 ARCHIVED (v1-v5 monoliths)
    ├── SpatialVisualiser_v1.swift
    ├── SpatialVisualiser_v2.swift
    ├── SpatialVisualiser_v3.swift
    ├── SpatialVisualiser_v4.swift
    └── SpatialVisualiser_v5.swift
```

---

## Module Breakdown

### SpatialIDECore (the SDK)
**Platform:** macOS, Linux (x86_64 + ARM64)
**Dependencies:** None (pure Swift, Foundation only)

This is the heart. Anyone can `import SpatialIDECore` and:
- Parse Swift source files into structured models
- Run layout algorithms to get 3D positions
- Export scene graphs as JSON

The parser stays regex/string-based for now (no dependency on swift-syntax — keeps it lightweight and cross-platform). Can upgrade later.

### SpatialIDECLI
**Platform:** macOS, Linux (x86_64 + ARM64)
**Dependencies:** SpatialIDECore, ArgumentParser

```bash
# Parse a project and output JSON scene graph
spatial-ide analyse ~/Projects/MyApp --output scene.json

# Quick stats
spatial-ide stats ~/Projects/MyApp
# → 12 classes, 47 methods, 8 protocols, 23 connections

# Watch mode (re-parse on file changes)
spatial-ide watch ~/Projects/MyApp --output scene.json
```

### SpatialIDEApp
**Platform:** macOS only (Cocoa + SceneKit)
**Dependencies:** SpatialIDECore

The GUI app. Consumes the SDK for parsing/layout, handles rendering via SceneKit. All the Tron aesthetic lives here.

Future: visionOS version using RealityKit (Tier 3).

---

## Platform Support Matrix

| Component       | macOS ARM (M4 Mini) | macOS x86 (Mac Pro 2019) | visionOS |
|----------------|---------------------|--------------------------|----------|
| SpatialIDECore | ✅                   | ✅                        | ✅ Future |
| SpatialIDECLI  | ✅                   | ✅                        | ❌        |
| SpatialIDEApp  | ✅                   | ✅                        | Future   |

> x86 = Intel Mac Pro (16-core Xeon W, Vega II). All Apple frameworks available on both architectures.

---

## Implementation Phases

### Phase 1: Extract & Structure
- [ ] Create `Package.swift` with all targets
- [ ] Extract parser into `SpatialIDECore/Parser/`
- [ ] Extract models into `SpatialIDECore/Model/`
- [ ] Extract layout logic into `SpatialIDECore/Layout/`
- [ ] Move v1-v5 files to `Legacy/`
- [ ] Verify it compiles on ARM

### Phase 2: CLI + x86
- [ ] Build CLI with ArgumentParser
- [ ] Add JSON export
- [ ] Test compilation on x86 (build universal binary or test on Mac Pro directly)
- [ ] Basic test suite for parser

### Phase 3: Rebuild App
- [ ] Rebuild macOS app consuming the SDK
- [ ] Extract SceneKit rendering from monolith
- [ ] Restore click-to-inspect, workspace browser
- [ ] Verify feature parity with v5

### Phase 4: Extend (Future)
- [ ] Multi-language parser support (Kotlin, TypeScript)
- [ ] Web viewer (Three.js consuming JSON export)
- [ ] visionOS app (RealityKit)
- [ ] Live reload (watch filesystem, update scene)

---

## Open Questions
1. **swift-argument-parser** — OK as the only external dependency for CLI?
2. **App distribution** — Keep building with `swiftc` directly, or move to Xcode project for the app target?
3. **Web viewer priority** — Three.js frontend a priority, or CLI JSON output enough for now?
4. **Multi-language** — Just Swift for now, or stub out the `LanguageParser` protocol early?

---

*Last updated: 2026-03-13*
