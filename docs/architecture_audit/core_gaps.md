# SourcePrintCore Architecture Gaps

**Project:** SourcePrint Architecture Audit
**Date:** 2025-10-28

This document identifies missing abstractions and services needed in SourcePrintCore to support complete separation of business logic from the UI layer.

---

## Table of Contents

1. [Current Core Architecture](#current-core-architecture)
2. [Missing Core Components](#missing-core-components)
3. [Proposed Core Structure](#proposed-core-structure)
4. [Implementation Priorities](#implementation-priorities)

---

## Current Core Architecture

### Existing Core Modules (13 Swift files)

SourcePrintCore currently contains well-designed foundational components:

**Processing Pipeline:**
- `importProcess.swift` - Media file analysis and metadata extraction
- `linkingProcess.swift` - Segment-to-OCF matching algorithm
- `printProcessFFmpeg.swift` - SwiftFFmpeg-based video composition
- `printProcess.swift` - Legacy AVFoundation composition
- `blankRushIntermediate.swift` - ProRes 4444 blank rush generation

**Analysis & Utilities:**
- `FrameOwnershipAnalyzer.swift` - VFX priority and frame overlap resolution
- `FrameRateManager.swift` - Rational frame rate arithmetic
- `SMPTE.swift` - Professional timecode calculations

**Data Models:**
- `DisplayMediaInfo.swift` - GUI-friendly media information abstraction

**Watch Folder (Partial):**
- `WatchFolderSettings.swift` - Configuration model
- `FileMonitorWatchFolder.swift` - FileMonitor library wrapper

**TUI:**
- `progressBar.swift` - Terminal progress visualization

### Strengths of Current Core

1. **Clean Separation:** Media processing logic is well-isolated from UI
2. **Professional Standards:** SMPTE timecode, rational frame rates, frame-accurate calculations
3. **Performance:** Hardware-accelerated VideoToolbox encoding, SwiftFFmpeg direct stream copying
4. **Abstraction Layer:** DisplayMediaInfo eliminates SwiftFFmpeg dependencies from UI

### Core Design Philosophy (Inferred)

- **Pure Functions:** Utilities like FrameRateManager are stateless and testable
- **Service Objects:** ImportProcess, BlankRushIntermediate encapsulate workflows
- **Rich Domain Models:** MediaFileInfo contains computed properties for business logic
- **Async/Await:** Modern Swift concurrency throughout

---

## Missing Core Components

The following components are currently implemented in the UI layer but belong in SourcePrintCore:

### 1. Workflow Orchestration

**Missing:** High-level workflow services that coordinate multiple operations

**Gap:**
- No `ProjectWorkflow` service to coordinate Import → Link → Blank Rush → Render
- No orchestration layer - UI views directly call multiple services in sequence
- Business rules for workflow transitions scattered across UI code

**Needed:**
```
SourcePrintCore/Workflows/
├── ProjectWorkflow.swift          // Coordinate complete workflow
├── RenderWorkflowService.swift    // Blank rush + render orchestration
├── WatchFolderService.swift       // File monitoring business logic
└── AutoImportService.swift        // Automatic import triggering
```

**Example:**
```swift
// Missing from core - currently in UI
public class ProjectWorkflow {
    public func executeImport(from directory: URL, type: MediaType) async throws -> [MediaFileInfo]
    public func executeLinking(ocfFiles: [MediaFileInfo], segments: [MediaFileInfo]) -> LinkingResult
    public func executeBlankRushGeneration(for linkingResult: LinkingResult) async -> [BlankRushResult]
    public func executeRender(for ocfParent: OCFParent, blankRushURL: URL) async -> RenderResult
}
```

---

### 2. Render Queue Management

**Missing:** Batch rendering queue with state machine

**Gap:**
- Batch render queue implemented in `LinkingResultsView.swift` (100+ lines)
- Queue state machine (add, process, complete, timeout) in SwiftUI view
- Cannot use render queue from CLI or automation

**Needed:**
```
SourcePrintCore/Workflows/
├── RenderQueueManager.swift       // Queue state machine
└── RenderService.swift            // Individual render execution
```

**Example:**
```swift
public class RenderQueueManager {
    public private(set) var queue: [RenderQueueItem] = []
    public private(set) var currentlyRendering: RenderQueueItem?

    public func enqueue(_ items: [RenderQueueItem])
    public func processNext(using service: RenderService) async -> RenderResult
    public func cancelAll()

    public var progress: (completed: Int, total: Int)
    public var isProcessing: Bool
}

public protocol RenderQueueDelegate: AnyObject {
    func renderQueue(_ queue: RenderQueueManager, willStartItem item: RenderQueueItem)
    func renderQueue(_ queue: RenderQueueManager, didCompleteItem item: RenderQueueItem, result: RenderResult)
}
```

---

### 3. File System Utilities

**Missing:** Centralized file operations for media files

**Gap:**
- File size, modification date, hash calculation scattered in `Project.swift`
- No centralized error handling for file operations
- Cannot test file operations without full UI environment

**Needed:**
```
SourcePrintCore/Utilities/
├── FileSystemOperations.swift     // File metadata and hashing
└── VideoFileDiscovery.swift       // Recursive video file discovery
```

**Example:**
```swift
public class FileSystemOperations {
    public static func getModificationDate(for url: URL) -> Result<Date, FileSystemError>
    public static func getFileSize(for url: URL) -> Result<Int64, FileSystemError>
    public static func calculatePartialHash(for url: URL) -> Result<String, FileSystemError>
}

public class VideoFileDiscovery {
    public static func discoverVideoFiles(in directory: URL) async throws -> [URL]
    public static func isVideoFile(_ url: URL) -> Bool
}
```

---

### 4. File Change Detection

**Missing:** Algorithm for detecting file changes and offline files

**Gap:**
- Complex file change detection (170+ lines) embedded in `Project.swift`
- Size-based comparison with hash fallback strategy in UI model
- Offline file tracking logic cannot be reused

**Needed:**
```
SourcePrintCore/Workflows/
├── FileChangeDetector.swift       // Classify new/returning/changed files
└── OfflineFileTracker.swift       // Track offline media files
```

**Example:**
```swift
public class FileChangeDetector {
    public static func classifyFiles(
        detectedFiles: [URL],
        existingSegments: [MediaFileInfo],
        offlineFiles: Set<String>,
        offlineMetadata: [String: OfflineFileMetadata],
        trackedSizes: [String: Int64]
    ) -> FileClassification

    public struct FileClassification {
        let newFiles: [URL]
        let returningUnchanged: [URL]
        let returningChanged: [URL]
        let existingModified: [URL]
    }
}
```

---

### 5. Media Import Parallelization

**Missing:** Concurrent media analysis strategy

**Gap:**
- Parallel processing logic (80+ lines) in `MediaImportTab.swift`
- TaskGroup management, progress throttling in UI view
- Cannot optimize import performance without modifying UI

**Needed:**
```
SourcePrintCore/Import/
└── MediaImportParallelizer.swift  // Concurrent analysis strategy
```

**Example:**
```swift
public class MediaImportParallelizer {
    public struct Configuration {
        let maxConcurrentTasks: Int
        let progressUpdateInterval: TimeInterval
    }

    public func analyzeInParallel(
        urls: [URL],
        type: MediaType,
        configuration: Configuration,
        progressHandler: ((Int, Int, MediaFileInfo?) -> Void)?
    ) async throws -> [MediaFileInfo]
}
```

---

### 6. Project Model Separation

**Missing:** Pure data model separated from UI concerns

**Gap:**
- `Project.swift` (1167 lines) is both data model AND business logic orchestrator
- Marked `@ObservableObject` tightly couples to SwiftUI
- Cannot use project model outside macOS GUI context

**Needed:**
```
SourcePrintCore/Models/
├── ProjectModel.swift             // Pure data (Codable, no business logic)
├── ProjectPersistence.swift       // Save/load from .w2 files
└── ProjectStateMachine.swift      // State transitions and validation
```

**Example:**
```swift
// Pure data model (no @ObservableObject, no business logic)
public struct ProjectModel: Codable {
    public var name: String
    public var ocfFiles: [MediaFileInfo]
    public var segments: [MediaFileInfo]
    public var linkingResult: LinkingResult?
    public var blankRushStatus: [String: BlankRushStatus]
    public var printStatus: [String: PrintStatus]
    // ... all data, no operations
}

// Separate persistence service
public class ProjectPersistence {
    public static func save(_ project: ProjectModel, to url: URL) throws
    public static func load(from url: URL) throws -> ProjectModel
}

// UI layer wraps in ObservableObject:
class ProjectViewModel: ObservableObject {
    @Published private(set) var model: ProjectModel

    init(model: ProjectModel) {
        self.model = model
    }

    // Thin wrappers that delegate to workflow services
    func performImport(...) async { ... }
}
```

---

### 7. Render Composition Service

**Missing:** Complete render workflow abstraction

**Gap:**
- FFmpeg segment conversion (100+ lines) in `LinkingResultsView.swift`
- SMPTE timecode calculations, CMTime arithmetic in UI
- Compositor invocation directly from SwiftUI views

**Needed:**
```
SourcePrintCore/Workflows/
└── RenderService.swift            // Complete render workflow
```

**Example:**
```swift
public class RenderService {
    private let compositor: SwiftFFmpegProResCompositor
    private let smpteCalculator: SMPTECalculator

    public func render(
        ocfParent: OCFParent,
        blankRushURL: URL,
        outputDirectory: URL,
        progressHandler: ((Double) -> Void)?
    ) async -> RenderResult

    public struct RenderResult {
        let success: Bool
        let outputURL: URL?
        let segmentCount: Int
        let duration: TimeInterval
        let printRecord: PrintRecord?
        let error: Error?
    }

    // Internal: Convert MediaFileInfo to FFmpegGradedSegments
    private func convertToFFmpegSegments(
        children: [LinkedSegment],
        baseTimecode: String,
        frameRate: Float
    ) throws -> [FFmpegGradedSegment]
}
```

---

### 8. Processing Plan Generator

**Missing:** Timeline visualization data generation

**Gap:**
- Processing plan generation (40+ lines) in `LinkingTab.swift`
- VideoStreamProperties construction from MediaFileInfo in UI
- FrameOwnershipAnalyzer invocation from view

**Needed:**
```
SourcePrintCore/SegmentAnalysis/
└── ProcessingPlanGenerator.swift  // Generate plans from linking results
```

**Example:**
```swift
public class ProcessingPlanGenerator {
    public static func generatePlan(
        for ocfParent: OCFParent,
        verbose: Bool = false
    ) async throws -> ProcessingPlan

    public static func generatePlans(
        for linkingResult: LinkingResult
    ) async throws -> [String: ProcessingPlan]  // OCF filename → plan
}
```

---

### 9. Blank Rush Validation

**Missing:** Video file validation utility

**Gap:**
- Blank rush validation using MediaAnalyzer in `CompressorStyleOCFCard.swift`
- No reusable validation utility for checking video file integrity

**Needed:**
```
SourcePrintCore/Utilities/
└── VideoFileValidator.swift       // Validate video files
```

**Example:**
```swift
public class VideoFileValidator {
    public static func isValidVideoFile(at url: URL) async -> Result<Bool, VideoValidationError>
    public static func validateBlankRush(at url: URL, expectedProperties: VideoStreamProperties) async -> ValidationResult
}
```

---

## Proposed Core Structure

### Reorganized SourcePrintCore Directory Structure

```
SourcePrintCore/
├── Sources/
│   └── SourcePrintCore/
│       │
│       ├── Models/                      # Pure data models
│       │   ├── ProjectModel.swift       # Pure project data (no business logic)
│       │   ├── RenderQueueItem.swift    # Queue item data
│       │   ├── FileChangeSet.swift      # File change results
│       │   └── OfflineFileMetadata.swift # Offline file tracking
│       │
│       ├── Workflows/                   # High-level orchestration
│       │   ├── ProjectWorkflow.swift    # Import → Link → Render coordination
│       │   ├── RenderQueueManager.swift # Batch render queue
│       │   ├── RenderService.swift      # Individual render execution
│       │   ├── RenderWorkflowService.swift # Blank rush + render
│       │   ├── WatchFolderService.swift # File monitoring orchestration
│       │   ├── AutoImportService.swift  # Automatic import triggering
│       │   └── FileChangeDetector.swift # File change classification
│       │
│       ├── Import/                      # Media import
│       │   ├── importProcess.swift      # (existing)
│       │   └── MediaImportParallelizer.swift # Concurrent analysis
│       │
│       ├── Linking/                     # Segment-OCF linking
│       │   └── linkingProcess.swift     # (existing)
│       │
│       ├── SegmentAnalysis/             # Frame ownership & planning
│       │   ├── FrameOwnershipAnalyzer.swift # (existing)
│       │   └── ProcessingPlanGenerator.swift # Generate from linking
│       │
│       ├── PrintProcess/                # Video composition
│       │   ├── printProcessFFmpeg.swift # (existing)
│       │   └── printProcess.swift       # (existing)
│       │
│       ├── BlankRush/                   # Blank rush generation
│       │   └── blankRushIntermediate.swift # (existing)
│       │
│       ├── Utilities/                   # Core utilities
│       │   ├── SMPTE.swift              # (existing)
│       │   ├── FrameRateManager.swift   # (existing)
│       │   ├── FileSystemOperations.swift # File metadata/hashing
│       │   ├── VideoFileDiscovery.swift # Recursive file traversal
│       │   └── VideoFileValidator.swift # Video file validation
│       │
│       ├── Persistence/                 # Data persistence
│       │   └── ProjectPersistence.swift # Save/load .w2 files
│       │
│       └── WatchFolder/                 # File monitoring
│           ├── WatchFolderSettings.swift # (existing)
│           └── FileMonitorWatchFolder.swift # (existing)
│
└── Tests/
    └── SourcePrintCoreTests/
        ├── FileSystemOperationsTests.swift
        ├── VideoFileDiscoveryTests.swift
        ├── FileChangeDetectorTests.swift
        ├── RenderQueueManagerTests.swift
        ├── ProjectWorkflowTests.swift
        └── ... (comprehensive unit tests for all services)
```

---

## Implementation Priorities

### Priority 1: Foundation (Phase 1)

**Timeline:** 1-2 weeks

**Components:**
- `FileSystemOperations.swift` - File metadata and hashing
- `VideoFileDiscovery.swift` - Recursive directory traversal
- `VideoFileValidator.swift` - Video file validation

**Why First:**
- Low risk, high value
- Zero dependencies on other refactoring
- Immediate testability gains
- Used by all other components

**Impact:**
- Remove 150+ lines from UI layer
- Enable unit testing of file operations
- Reusable in CLI immediately

---

### Priority 2: Watch Folder & Import (Phase 2)

**Timeline:** 2-3 weeks

**Components:**
- `WatchFolderService.swift` - File monitoring orchestration
- `FileChangeDetector.swift` - File change classification
- `AutoImportService.swift` - Automatic import triggering
- `MediaImportParallelizer.swift` - Concurrent analysis
- `OfflineFileMetadata.swift` - Offline file tracking model

**Why Second:**
- Builds on Phase 1 utilities
- Discrete, well-scoped service
- High-value feature extraction
- Medium risk, manageable dependencies

**Impact:**
- Remove 600+ lines from `Project.swift`
- Watch folder service usable as daemon
- Import performance tuning in core
- Complete unit test coverage

---

### Priority 3: Render Workflows (Phase 3)

**Timeline:** 3-4 weeks

**Components:**
- `RenderQueueManager.swift` - Batch render queue
- `RenderService.swift` - Individual render execution
- `RenderWorkflowService.swift` - Blank rush + render orchestration
- `ProcessingPlanGenerator.swift` - Timeline visualization data

**Why Third:**
- Requires Phase 1 (file validation)
- High complexity, careful async coordination
- Highest value for CLI support
- High risk due to state management

**Impact:**
- Remove 600+ lines from `LinkingResultsView.swift` and `CompressorStyleOCFCard.swift`
- Enable CLI rendering
- Complete render workflow testing
- Automation scripts can use render queue

---

### Priority 4: Project Model (Phase 4)

**Timeline:** 4-6 weeks

**Components:**
- `ProjectModel.swift` - Pure data model
- `ProjectPersistence.swift` - Save/load .w2 files
- `ProjectWorkflow.swift` - Complete workflow coordination
- `ProjectStateMachine.swift` - State transitions

**Why Last:**
- Requires all other phases complete
- Highest risk (1167 lines to refactor)
- Complex state management
- Maintains SwiftUI reactivity through ViewModel wrapper

**Impact:**
- Remove 1000+ lines of business logic from UI
- Project model testable without UI
- Complete architectural separation achieved
- Enable future UI ports (iOS, web, Linux)

---

## Expected Core Library Growth

### Current State
- **Files:** 13 Swift files
- **Lines:** ~3000 lines of code (estimated)
- **Focus:** Media processing, timecode, composition

### After Complete Refactoring
- **Files:** ~30 Swift files
- **Lines:** ~5000-6000 lines of code (estimated)
- **Focus:** Media processing + workflow orchestration + file operations + state management

### Growth Breakdown
- **New Workflow Services:** ~1500 lines
- **File System Utilities:** ~400 lines
- **Render Queue & Services:** ~800 lines
- **Project Model Refactoring:** ~600 lines
- **Additional Tests:** ~2000 lines

---

## Benefits of Complete Core

### Testability
- Unit test all business logic without UI
- Integration tests for complete workflows
- Performance benchmarking isolated from UI
- Regression testing on core algorithms

### Reusability
- CLI can use all workflows (render queue, watch folder, import)
- Automation scripts leverage core services
- Daemon mode for watch folder monitoring
- Potential for HTTP API wrapper

### Maintainability
- Clear separation of concerns
- Business logic changes isolated to core
- UI changes don't break workflows
- Single source of truth for operations

### Portability
- Could port to iOS with different UI
- Linux support possible (remove VideoToolbox dependency)
- Web UI could consume core via WASM or REST API
- Easier to expose C-ABI interface for ultimate portability

---

## Risks & Considerations

### Complexity Growth
- Core library grows from 13 to ~30 files
- More abstractions to understand
- Steeper learning curve for new contributors

**Mitigation:** Comprehensive documentation, clear module organization, meaningful naming

### Over-Engineering
- Risk of creating abstractions that are too generic
- Potential performance overhead from additional layers
- Callback hell from protocol-based architecture

**Mitigation:** Start with concrete use cases, refactor incrementally, measure performance

### Migration Cost
- 10-15 weeks of focused refactoring effort
- Requires careful coordination to avoid breaking UI
- Testing overhead significant

**Mitigation:** Phased approach with validation, parallel implementation, feature flags

---

## Conclusion

SourcePrintCore has a **strong foundation** with excellent media processing and timecode utilities. However, **critical gaps** exist where workflow orchestration, file operations, and state management have leaked into the UI layer.

The proposed refactoring will:
1. **Add 17 new services and utilities** to core
2. **Remove ~2000 lines** of business logic from UI
3. **Enable CLI and automation** support for all workflows
4. **Achieve complete architectural separation**

The phased approach ensures **manageable risk** while delivering **incremental value** at each stage. Upon completion, SourcePrint will have a **world-class architecture** suitable for professional video workflows with clean separation between business logic and presentation layers.

---

**Next Steps:** Begin Phase 1 implementation (File System Utilities) as outlined in `refactoring_plan.md`.
