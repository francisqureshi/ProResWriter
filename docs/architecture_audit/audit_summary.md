# SourcePrint Architecture Audit - Executive Summary

**Date:** 2025-10-28
**Auditor:** Claude Code Architecture Analysis
**Project:** SourcePrint - Professional Video Post-Production Workflow

---

## Current Architecture Assessment

### Overview
SourcePrint is a Swift-based macOS application for professional video post-production workflows, featuring a **dual-architecture design**:

- **Core Library:** `SourcePrintCore/` - Swift Package containing business logic (13 Swift files)
- **UI Layer:** `SourcePrint/SourcePrint/` - macOS SwiftUI application (25 Swift files)

The project demonstrates **strong architectural discipline** with business logic generally well-separated into the core library. However, there are **critical violations** where complex business operations have leaked into the UI layer.

### Architectural Strengths

1. **Clean Core Library Design**
   - `SourcePrintCore` contains essential business logic:
     - `importProcess.swift` - Media file analysis and metadata extraction
     - `linkingProcess.swift` - Segment-to-OCF matching algorithm
     - `printProcessFFmpeg.swift` - SwiftFFmpeg-based video composition
     - `blankRushIntermediate.swift` - ProRes 4444 generation
     - `FrameOwnershipAnalyzer.swift` - VFX priority and frame overlap resolution
     - `SMPTE.swift` - Professional timecode calculations
     - `FrameRateManager.swift` - Rational frame rate arithmetic

2. **Display Abstraction Layer**
   - `DisplayMediaInfo.swift` provides GUI-friendly data structures
   - Eliminates SwiftFFmpeg dependencies from UI
   - Clean separation of technical data from display formatting

3. **Feature-Based UI Organization**
   - UI reorganized from monolithic (1276 lines) to modular structure
   - Feature directories: MediaImport, Linking, Render, Overview, ProjectManagement
   - Views are primarily declarative with minimal embedded logic

### Critical Architectural Violations

Despite the strong foundation, **three major areas violate separation of concerns**:

## 1. Complex Video Rendering Logic in UI Layer

**Violation Scope:** High Severity

**Location:** `LinkingResultsView.swift`, `CompressorStyleOCFCard.swift`

**Issue:** The UI layer contains complete implementations of:
- Batch render queue management (lines 170-238 in LinkingResultsView)
- Blank rush creation workflow (lines 220-260 in CompressorStyleOCFCard)
- FFmpeg segment processing and composition (lines 262-400+ in both files)
- Timecode conversion using SMPTE library (lines 286-389)
- CMTime calculations for video segment positioning
- SwiftFFmpeg compositor invocation and settings construction

**Business Logic Found in Views:**
```swift
// LinkingResultsView.swift lines 332-438
@MainActor
private func renderOCFInQueue(parent: OCFParent, blankRushURL: URL) async {
    // Complete video composition logic in a SwiftUI View
    let compositor = SwiftFFmpegProResCompositor()
    var ffmpegGradedSegments: [FFmpegGradedSegment] = []

    // SMPTE timecode calculations
    for child in parent.children {
        let smpte = SMPTE(fps: Double(segmentFrameRateFloat), ...)
        let segmentFrames = try smpte.getFrames(tc: segmentTC)
        // ... complex CMTime arithmetic
    }
    // ... compositor invocation with progress handling
}
```

**Impact:**
- 500+ lines of business logic embedded in SwiftUI views
- Impossible to test rendering logic without UI framework
- Cannot reuse render queue logic for CLI or automation
- Violates single responsibility principle

---

## 2. File System Operations and State Management in UI Models

**Violation Scope:** High Severity

**Location:** `Project.swift` (1,167 lines in UI layer)

**Issue:** The `Project` class (marked as `@ObservableObject` for SwiftUI) contains extensive business logic:

**File System Operations (lines 432-494):**
```swift
private func getFileModificationDate(for url: URL) -> Date?
private func getFileSize(for url: URL) -> Int64?
private func calculatePartialHash(for url: URL) -> String?
```

**Watch Folder Integration (lines 517-999):**
- Complete FileMonitor integration with callbacks
- Video file detection and validation (670+ lines)
- Automatic import triggering with async media analysis
- Offline file detection using size comparison and SHA256 hashing
- Modification tracking and print status updates

**File Change Detection Business Logic (lines 578-661):**
```swift
private func checkForChangedFilesOnStartup(gradePath: String?, vfxPath: String?) {
    // Compare stored file sizes with current sizes
    // Hash-based validation for changed files
    // Automatic print status updates when segments modified
}
```

**Media Analysis Invocation (lines 844-878):**
```swift
private func analyzeDetectedFiles(urls: [URL], isVFX: Bool) async -> [MediaFileInfo] {
    for url in urls {
        let mediaFile = try await MediaAnalyzer().analyzeMediaFile(at: url, type: .gradedSegment)
        // VFX flag assignment
    }
}
```

**Impact:**
- UI model contains 1000+ lines of business logic
- File system operations tightly coupled to SwiftUI lifecycle
- Cannot reuse watch folder logic outside macOS GUI
- Testing requires full SwiftUI environment
- Violates the principle that models should be dumb data containers

---

## 3. Project Management and Persistence Logic in UI Layer

**Violation Scope:** Medium Severity

**Location:** `ProjectManager.swift` (427 lines in UI layer)

**Issue:** ProjectManager contains business logic that should be in core:

**Import Process Integration (lines 338-367):**
```swift
func importOCFFiles(for project: Project, from directory: URL) async -> [MediaFileInfo] {
    let importProcess = ImportProcess()
    let files = try await importProcess.importOriginalCameraFiles(from: directory)
    project.addOCFFiles(files)
    return files
}

func performLinking(for project: Project) {
    // Filter offline segments
    let onlineSegments = project.segments.filter { !project.offlineMediaFiles.contains($0.fileName) }

    let linker = SegmentOCFLinker()
    let result = linker.linkSegments(onlineSegments, withOCFParents: project.ocfFiles)

    project.updateLinkingResult(result)
    project.refreshPrintStatus()
}
```

**Blank Rush Orchestration (lines 399-426):**
```swift
func createBlankRushes(for project: Project) async {
    let blankRushIntermediate = BlankRushIntermediate(projectDirectory: ...)

    for parent in linkingResult.parentsWithChildren {
        project.updateBlankRushStatus(ocfFileName: parent.ocf.fileName, status: .inProgress)
    }

    let results = await blankRushIntermediate.createBlankRushes(from: linkingResult)
    // Status updates based on results
}
```

**Impact:**
- 200+ lines of workflow orchestration in UI layer
- Business rules for filtering and validation in ProjectManager
- Cannot expose these workflows through CLI without UI framework
- Tight coupling between persistence and business operations

---

## 4. Media Import Parallel Processing in UI Tab

**Violation Scope:** Medium Severity

**Location:** `MediaImportTab.swift` (lines 234-315)

**Issue:** Complex concurrent processing logic embedded in SwiftUI view:

```swift
private func analyzeMediaFilesInParallel(urls: [URL], isOCF: Bool) async -> [MediaFileInfo] {
    let maxConcurrentTasks = min(urls.count, 50)

    return await withTaskGroup(of: (Int, MediaFileInfo?).self, ...) { taskGroup in
        // Complex TaskGroup management
        // Progress throttling logic
        // Result ordering and filtering
    }
}
```

**File Discovery Logic (lines 169-211):**
```swift
private func getAllVideoFiles(from directoryURL: URL) async -> [URL] {
    guard let enumerator = FileManager.default.enumerator(...) { ... }

    for case let fileURL as URL in enumerator {
        // Video extension validation
        // Recursive directory traversal
    }

    return videoFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
}
```

**Impact:**
- 80+ lines of concurrent processing strategy in UI
- File system traversal logic cannot be reused
- Import performance tuning requires modifying UI code

---

## Summary Statistics

| Metric | Count | Notes |
|--------|-------|-------|
| **UI Layer Swift Files** | 25 | Should contain only views and view models |
| **Core Library Swift Files** | 13 | Business logic well-encapsulated here |
| **Lines of Business Logic in UI** | ~2000+ | Estimated across violations |
| **Files with Major Violations** | 4 | Project.swift, ProjectManager.swift, LinkingResultsView.swift, CompressorStyleOCFCard.swift |
| **Files with Minor Violations** | 2 | MediaImportTab.swift, LinkingTab.swift |

---

## Key Problems Identified

### 1. **Testability Crisis**
- Cannot unit test rendering logic without SwiftUI runtime
- File system operations require full macOS environment
- Watch folder logic cannot be tested in isolation

### 2. **Code Reuse Impossible**
- CLI cannot leverage render queue system
- Automation scripts cannot use watch folder detection
- Import parallelization strategy is UI-locked

### 3. **Architecture Erosion**
- Clear drift from "views display data, core contains logic"
- SwiftUI views making FFmpeg calls directly
- UI models performing cryptographic hashing

### 4. **Maintenance Burden**
- Business rule changes require UI code modifications
- Cannot optimize rendering without touching SwiftUI views
- Difficult to reason about where logic lives

---

## Recommended Architecture

### Target Separation

```
SourcePrintCore/
├── Workflows/
│   ├── RenderQueueManager.swift       // Batch rendering orchestration
│   ├── WatchFolderService.swift       // File monitoring business logic
│   ├── ProjectWorkflow.swift          // Import/Link/Render coordination
│   └── FileSystemOperations.swift     // File size/hash/metadata utilities
│
├── Models/
│   ├── ProjectModel.swift             // Pure data model (no business logic)
│   ├── RenderQueue.swift              // Queue state machine
│   └── FileChangeDetector.swift       // Change detection algorithm
│
└── [Existing Modules]
    ├── PrintProcess/
    ├── Import/
    ├── Linking/
    └── ...

SourcePrint/SourcePrint/
├── Features/
│   ├── Linking/
│   │   └── LinkingResultsView.swift   // Pure SwiftUI (calls RenderQueueManager)
│   ├── MediaImport/
│   │   └── MediaImportTab.swift       // Delegates to ProjectWorkflow
│   └── ...
│
└── Models/
    ├── ProjectViewModel.swift         // Thin wrapper around ProjectModel
    └── ProjectManagerViewModel.swift  // SwiftUI-specific presentation logic
```

### Principles

1. **Views are pure presentation:** No business decisions, only display and user input delegation
2. **Core owns all workflows:** Import, linking, rendering, watching orchestrated in core
3. **UI models are thin wrappers:** ObservableObject wraps core models, maps to UI state
4. **File system operations in core:** All I/O, hashing, size checking in FileSystemOperations utility

---

## Expected Benefits

### Immediate Gains
- **Testability:** Unit test all rendering, import, and watch folder logic
- **CLI Support:** Expose render queue manager through command-line interface
- **Automation:** Scripts can use watch folder service without GUI
- **Code Clarity:** Clear boundary between presentation and business logic

### Long-Term Benefits
- **Maintainability:** Business rule changes isolated to core library
- **Performance:** Optimize algorithms without touching UI code
- **Portability:** Could port to iOS, Linux, or web with different UI layer
- **Team Velocity:** Frontend and backend developers work independently

---

## Risk Assessment

### Low Risk
- DisplayMediaInfo abstraction already provides good separation
- Core library has strong foundation with SMPTE, FrameRateManager, etc.
- Import and Linking processes already well-encapsulated

### Medium Risk
- Moving render queue to core requires careful async/await bridging
- Watch folder callbacks need redesign to avoid UI coupling
- Project model state management must remain reactive for SwiftUI

### High Risk
- Project.swift is 1,167 lines with complex state interdependencies
- Blank rush generation interleaved with UI status updates
- Extensive use of @Published properties for SwiftUI bindings

---

## Phased Migration Strategy

### Phase 1: Low-Hanging Fruit (Low Risk, High Value)
**Duration:** 1-2 weeks
**Target:** File system utilities, media analysis parallelization

- Extract `FileSystemOperations` utility class
- Move `calculatePartialHash`, `getFileSize`, `getFileModificationDate` to core
- Extract `MediaImportParallelizer` from MediaImportTab
- Extract `VideoFileDiscovery` recursive traversal logic

**Value:** Immediate testability, CLI can use file utilities

### Phase 2: Watch Folder Service (Medium Risk, High Value)
**Duration:** 2-3 weeks
**Target:** Complete watch folder business logic separation

- Create `WatchFolderService` in core with protocol-based callbacks
- Extract file change detection algorithm
- Move automatic import triggering logic to core workflow
- UI layer becomes thin presentation of watch folder state

**Value:** Watch folder can run as daemon/service, testable in isolation

### Phase 3: Render Queue Manager (High Risk, High Value)
**Duration:** 3-4 weeks
**Target:** Complete rendering orchestration in core

- Create `RenderQueueManager` with queue state machine
- Extract blank rush creation workflow
- Move FFmpeg segment processing to core
- Implement progress reporting through protocol callbacks
- UI views become pure consumers of render queue state

**Value:** CLI rendering, automation scripts, full unit test coverage

### Phase 4: Project Model Refactoring (High Risk, Critical)
**Duration:** 4-6 weeks
**Target:** Separate Project data model from business logic

- Split `Project.swift` into `ProjectModel` (core) and `ProjectViewModel` (UI)
- Move all business operations to `ProjectWorkflow` in core
- Maintain SwiftUI reactivity through thin observable wrapper
- Extract state machine for print status, blank rush status, etc.

**Value:** Clean architecture, maintainable codebase, full separation achieved

---

## Recommendations

### Immediate Actions
1. **Freeze feature development** in violation areas until refactoring begins
2. **Write integration tests** for current behavior before refactoring
3. **Establish architecture review** process to prevent new violations
4. **Document callback contracts** between UI and core for async operations

### Strategic Direction
1. **Invest in Phase 1 immediately** - low risk, immediate testability gains
2. **Plan Phase 2 for next sprint** - watch folder is discrete, well-scoped
3. **Schedule Phase 3-4 as major initiative** - requires careful design and testing
4. **Consider extracting C-ABI interface** for ultimate portability (future phase)

---

## Conclusion

SourcePrint demonstrates **strong architectural discipline** in its core library design, with excellent separation of media processing, timecode calculations, and video composition logic. However, **critical violations** exist where complex workflows (rendering, watch folders, project management) have leaked into the UI layer.

The recommended refactoring follows a **progressive migration** strategy:
- Start with low-risk file utilities (immediate testability)
- Move to discrete services like watch folders (high value, manageable risk)
- Culminate in major refactoring of rendering and project model (high impact)

This audit provides a **clear roadmap** to achieve complete architectural separation while managing risk and maintaining development velocity. The phased approach allows incremental progress with validation at each stage, preventing a risky "big bang" rewrite.

**Next Steps:** Review detailed violation analysis in `ui_layer_violations.md` and implementation plan in `refactoring_plan.md`.
