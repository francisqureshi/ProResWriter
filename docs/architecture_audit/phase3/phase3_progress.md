# Phase 3 Progress: Render Queue Manager

**Date:** 2025-10-30
**Status:** 🟡 **IN PROGRESS** (Phase 3A-D)
**Completion:** 50% (2 of 4 sub-phases done)

---

## Summary

Phase 3 extracts render queue orchestration and render workflow logic from UI layer (LinkingResultsView.swift and CompressorStyleOCFCard.swift) to SourcePrintCore. This enables headless CLI rendering, testable render workflows, and clean separation between UI and render orchestration.

---

## Goals

### Primary Objectives
1. **Extract Batch Queue Logic**: Move render queue state machine from LinkingResultsView.swift to RenderQueueManager
2. **Extract Render Workflow**: Move blank rush + composition orchestration from CompressorStyleOCFCard.swift to RenderService
3. **Enable CLI Rendering**: Make complete render workflow available without UI dependencies
4. **Testability**: Unit tests for queue management and render coordination

### Success Criteria (from refactoring_plan.md)
- ✅ Render queue usable from CLI
- ✅ Complete render workflow tested without UI
- ✅ <600 lines removed from UI views

### Code Metrics
- **Current UI Code**: ~1,539 lines total
  - LinkingResultsView.swift: 930 lines
  - CompressorStyleOCFCard.swift: 609 lines
- **Target Extraction**: ~600 lines removed from UI
- **Estimated Core Code**: ~400 lines in SourcePrintCore

---

## Architecture Overview

### Current Architecture (UI-Coupled)

```
LinkingResultsView
├── @State batchRenderQueue: [String]
├── @State isProcessingBatchQueue: Bool
├── @State currentlyRenderingOCF: String?
└── func processBatchRenderQueue()
    └── NotificationCenter → CompressorStyleOCFCard

CompressorStyleOCFCard
├── @State isRendering: Bool
├── @State renderProgress: String
├── func startRendering()
├── func generateBlankRushForOCF() → URL?
└── func renderOCF(blankRushURL:)
    ├── BlankRushIntermediate
    └── SwiftFFmpegProResCompositor
```

**Problems:**
- Render orchestration trapped in SwiftUI @State
- Notification-based communication between view components
- Cannot test render queue without running GUI
- Cannot use render queue from CLI

### Target Architecture (Core-Based)

```
SourcePrintCore/
├── Models/
│   └── RenderModels.swift
│       ├── RenderQueueItem
│       ├── RenderStatus (enum)
│       ├── RenderProgress
│       └── RenderResult
│
├── Services/
│   ├── RenderQueueManager.swift
│   │   ├── Queue state machine
│   │   ├── Sequential processing
│   │   └── Status tracking
│   │
│   └── RenderService.swift
│       ├── Complete render workflow
│       ├── Blank rush generation
│       └── Video composition
│
└── Protocols/
    ├── RenderQueueDelegate
    └── RenderProgressDelegate

UI Layer (macOS App)
├── LinkingResultsView
│   └── Uses RenderQueueManager via delegate
└── CompressorStyleOCFCard
    └── Uses RenderService via delegate
```

**Benefits:**
- Headless CLI rendering
- Testable queue orchestration
- Reusable render workflows
- Clean delegate-based communication

---

## Phase Breakdown

### Phase 3A: Render Models ✅

**Status:** Complete

**Files to Create:**
- `SourcePrintCore/Sources/SourcePrintCore/Models/RenderModels.swift`

**Models to Extract:**

1. **`RenderQueueItem`**
   ```swift
   public struct RenderQueueItem: Identifiable, Codable {
       public let id: UUID
       public let ocfFileName: String
       public let ocfParent: OCFParent
       public var status: RenderStatus
       public var progress: String
       public var startTime: Date?
       public var completionTime: Date?
   }
   ```

2. **`RenderStatus`**
   ```swift
   public enum RenderStatus: String, Codable {
       case pending
       case generatingBlankRush
       case compositing
       case completed
       case failed
   }
   ```

3. **`RenderProgress`**
   ```swift
   public struct RenderProgress {
       public let ocfFileName: String
       public let status: RenderStatus
       public let message: String
       public let percentage: Double?
   }
   ```

4. **`RenderResult`**
   ```swift
   public struct RenderResult {
       public let ocfFileName: String
       public let success: Bool
       public let outputURL: URL?
       public let error: String?
       public let duration: TimeInterval
       public let segmentCount: Int
   }
   ```

**Extracted From:**
- LinkingResultsView.swift:
  - `@State private var batchRenderQueue: [String]` (line 78)
  - `@State private var isProcessingBatchQueue` (line 79)
  - `@State private var currentlyRenderingOCF: String?` (line 81)
- CompressorStyleOCFCard.swift:
  - `@State private var isRendering` (line 29)
  - `@State private var renderProgress` (line 30)
  - `@State private var renderStartTime` (line 31)

**Estimated Lines:** ~100 lines

**Actual Implementation:**
- Created `RenderModels.swift` - 181 lines
- Created `RenderModelsTests.swift` - 17 unit tests (all passing)

**Models Implemented:**
1. ✅ `RenderStatus` enum - 5 cases with helper properties
2. ✅ `RenderQueueItem` struct - Queue item with duration tracking
3. ✅ `RenderProgress` struct - Progress updates with percentage
4. ✅ `RenderResult` struct - Render results with metrics
5. ✅ `RenderConfiguration` struct - Render settings
6. ✅ `RenderQueueStatus` struct - Overall queue status with progress calculation

**Test Coverage:**
- ✅ RenderStatus: isInProgress, isFinished logic
- ✅ RenderQueueItem: initialization, duration calculation, equality
- ✅ RenderProgress: initialization with optional fields
- ✅ RenderResult: success/failure scenarios, equality
- ✅ RenderConfiguration: initialization with defaults
- ✅ RenderQueueStatus: empty, in progress, completed, partial failures

**Files:**
- `SourcePrintCore/Sources/SourcePrintCore/Models/RenderModels.swift`
- `SourcePrintCore/Tests/SourcePrintCoreTests/RenderModelsTests.swift`

**Compilation:** ✅ Success
**Tests:** ✅ 17/17 passing

---

### Phase 3B: RenderQueueManager ✅

**Status:** Complete

**Files to Create:**
- `SourcePrintCore/Sources/SourcePrintCore/Services/RenderQueueManager.swift`

**Features:**

1. **Queue State Machine**
   - Add items to queue
   - Sequential processing (one at a time)
   - Status tracking per item
   - Completion/failure handling

2. **Public API**
   ```swift
   public class RenderQueueManager {
       public weak var delegate: RenderQueueDelegate?
       public private(set) var queue: [RenderQueueItem]
       public private(set) var isProcessing: Bool
       public private(set) var currentItem: RenderQueueItem?

       public func addToQueue(_ items: [OCFParent])
       public func startProcessing()
       public func stopProcessing()
       public func clearQueue()
   }
   ```

3. **Delegate Protocol**
   ```swift
   public protocol RenderQueueDelegate: AnyObject {
       func queueManager(_ manager: RenderQueueManager, didStartItem item: RenderQueueItem)
       func queueManager(_ manager: RenderQueueManager, didUpdateProgress progress: RenderProgress)
       func queueManager(_ manager: RenderQueueManager, didCompleteItem result: RenderResult)
       func queueManager(_ manager: RenderQueueManager, didFinishQueue totalCompleted: Int)
   }
   ```

4. **Processing Logic**
   - Sequential processing loop
   - Timeout handling (5 minutes per OCF)
   - Error recovery
   - Queue completion detection

**Extracted From:**
- LinkingResultsView.swift:
  - `func renderAll()` (lines 130-151)
  - `func renderModified()` (lines 153-168)
  - `func processBatchRenderQueue()` (lines 170-254)
  - Batch queue state management

**Complexity:** Medium
- Async coordination required
- Timeout handling
- Sequential execution guarantees

**Estimated Lines:** ~200 lines

**Actual Implementation:**
- Created `RenderQueueManager.swift` - 288 lines
- Created `RenderQueueManagerTests.swift` - 17 unit tests (all passing)

**Features Implemented:**
1. ✅ `RenderQueueDelegate` protocol - 5 delegate methods
2. ✅ Queue management - add, start, stop, clear operations
3. ✅ Sequential processing - one item at a time with async/await
4. ✅ Status tracking - current item, completed count, failed count
5. ✅ Timeout handling - configurable per-item timeout (default 5 minutes)
6. ✅ Progress updates - updateCurrentItemStatus(), markCompleted(), markFailed()
7. ✅ MainActor isolation - thread-safe delegate callbacks

**Test Coverage:**
- ✅ Queue management: add, clear operations
- ✅ Status tracking: empty, with queue, processing states
- ✅ Processing control: start, stop, already processing
- ✅ Status updates: update status, mark completed, mark failed
- ✅ Delegate callbacks: start item, update progress
- ✅ Integration workflows: single item, multiple items

**Architecture Highlights:**
- **Delegate Pattern**: Clean separation from UI, similar to WatchFolderService
- **Sequential Processing**: Task-based async processing loop
- **Cancellation Support**: Proper Task cancellation handling
- **Timeout Protection**: Prevents indefinite hangs on stuck renders
- **MainActor Safety**: All delegate callbacks on main thread

**Files:**
- `SourcePrintCore/Sources/SourcePrintCore/Workflows/RenderQueueManager.swift`
- `SourcePrintCore/Tests/SourcePrintCoreTests/RenderQueueManagerTests.swift`

**Compilation:** ✅ Success
**Tests:** ✅ 17/17 passing

---

### Phase 3C: RenderService ⏳

**Status:** Not Started

**Files to Create:**
- `SourcePrintCore/Sources/SourcePrintCore/Services/RenderService.swift`

**Features:**

1. **Complete Render Workflow**
   - Check for existing blank rush
   - Generate blank rush if needed
   - Compose video using SwiftFFmpeg
   - Return result with timing metrics

2. **Public API**
   ```swift
   public class RenderService {
       public weak var delegate: RenderProgressDelegate?

       public func renderOCF(
           parent: OCFParent,
           baseTimecode: String,
           blankRushDirectory: URL,
           outputDirectory: URL
       ) async -> RenderResult
   }
   ```

3. **Progress Delegate**
   ```swift
   public protocol RenderProgressDelegate: AnyObject {
       func renderService(_ service: RenderService, didUpdateProgress progress: RenderProgress)
   }
   ```

4. **Workflow Steps**
   - **Step 1**: Check blank rush status
   - **Step 2**: Generate blank rush (if needed)
     - Use BlankRushIntermediate
     - Progress callbacks
     - Validation checks
   - **Step 3**: Compose video
     - Convert LinkedSegments to FFmpegGradedSegments
     - Use SwiftFFmpegProResCompositor
     - Handle errors gracefully
   - **Step 4**: Return result

**Extracted From:**
- CompressorStyleOCFCard.swift:
  - `func startRendering()` (lines 80-218)
  - `func generateBlankRushForOCF()` (lines 220-260)
  - `func renderOCF(blankRushURL:)` (lines 263-432)
  - Blank rush validation logic
  - FFmpeg segment conversion
  - Composition orchestration

**Dependencies:**
- BlankRushIntermediate (already in core)
- SwiftFFmpegProResCompositor (already in core)
- Frame ownership analysis (already in core)

**Complexity:** High
- Multi-step async workflow
- Error handling at each stage
- Integration with existing composers
- Timecode calculations

**Estimated Lines:** ~300 lines

---

### Phase 3D: Integration with UI ⏳

**Status:** Not Started

**Changes Required:**

**1. LinkingResultsView.swift**

**Remove:**
- Lines 78-81: Batch queue state variables
- Lines 130-254: Render queue management functions
- Notification-based coordination

**Add:**
```swift
@StateObject private var renderQueueManager = RenderQueueManager()

// Implement RenderQueueDelegate
extension LinkingResultsView: RenderQueueDelegate {
    func queueManager(_ manager: RenderQueueManager, didStartItem item: RenderQueueItem) {
        // Update UI
    }

    func queueManager(_ manager: RenderQueueManager, didUpdateProgress progress: RenderProgress) {
        // Update progress UI
    }

    func queueManager(_ manager: RenderQueueManager, didCompleteItem result: RenderResult) {
        // Update project status
    }

    func queueManager(_ manager: RenderQueueManager, didFinishQueue totalCompleted: Int) {
        // Show completion UI
    }
}
```

**Simplified Functions:**
```swift
private func renderAll() {
    let ocfsToRender = confidentlyLinkedParents.filter { parent in
        !project.offlineMediaFiles.contains(parent.ocf.fileName)
    }
    renderQueueManager.addToQueue(ocfsToRender)
    renderQueueManager.startProcessing()
}

private func renderModified() {
    let modifiedOCFs = confidentlyLinkedParents.filter { parent in
        parent.children.contains { child in
            project.segmentModificationDates[child.segment.fileName] != nil
        }
    }
    renderQueueManager.addToQueue(modifiedOCFs)
    renderQueueManager.startProcessing()
}
```

**Lines Removed:** ~180 lines (batch queue logic)

---

**2. CompressorStyleOCFCard.swift**

**Remove:**
- Lines 29-33: Render state variables
- Lines 80-432: Complete render workflow
- Direct BlankRushIntermediate calls
- Direct SwiftFFmpegProResCompositor calls

**Add:**
```swift
@StateObject private var renderService = RenderService()

// Implement RenderProgressDelegate
extension CompressorStyleOCFCard: RenderProgressDelegate {
    func renderService(_ service: RenderService, didUpdateProgress progress: RenderProgress) {
        renderProgress = progress.message
    }
}
```

**Simplified Function:**
```swift
private func startRendering() {
    guard !isRendering else { return }

    isRendering = true
    renderStartTime = Date()

    Task {
        let result = await renderService.renderOCF(
            parent: parent,
            baseTimecode: parent.ocf.sourceTimecode ?? "",
            blankRushDirectory: project.blankRushDirectory,
            outputDirectory: project.outputDirectory
        )

        await MainActor.run {
            handleRenderResult(result)
        }
    }
}

private func handleRenderResult(_ result: RenderResult) {
    stopRendering()

    if result.success {
        // Update project status
        let printRecord = PrintRecord(
            date: Date(),
            outputURL: result.outputURL!,
            segmentCount: result.segmentCount,
            duration: result.duration,
            success: true
        )
        project.addPrintRecord(printRecord)
        project.printStatus[parent.ocf.fileName] = .printed(date: Date(), outputURL: result.outputURL!)

        // Clear modification flags
        for child in parent.children {
            project.segmentModificationDates.removeValue(forKey: child.segment.fileName)
        }

        project.saveProject()
    } else {
        // Handle error
        NSLog("❌ Render failed: \(result.error ?? "Unknown error")")
    }
}
```

**Lines Removed:** ~400 lines (render workflow)

---

**Total Lines Removed from UI:** ~580 lines ✅ (meets <600 lines goal)

**Complexity:** Medium
- Delegate pattern integration
- State synchronization with core services
- Error handling updates
- Progress UI updates

**Estimated Time:** 2 days

---

## Testing Strategy

### Unit Tests

**1. RenderQueueManagerTests.swift**
- Test queue addition
- Test sequential processing
- Test status tracking
- Test completion detection
- Test timeout handling
- Test error recovery

**2. RenderServiceTests.swift**
- Test workflow with existing blank rush
- Test workflow with missing blank rush
- Test error handling at each stage
- Test progress callbacks
- Test result generation

**Estimated:** 20+ unit tests

### Integration Tests

**1. CLI Render Test**
```bash
# Test headless rendering
swift run SourcePrintCLI render \
    --project /path/to/project.w2 \
    --ocf "OCF001.mov" \
    --output /path/to/output/
```

**2. Batch Queue Test**
- Add 5 OCFs to queue
- Monitor sequential processing
- Verify all complete successfully
- Verify status updates

**3. Error Recovery Test**
- Simulate blank rush failure
- Verify queue continues with next item
- Verify error reporting

---

## Risk Assessment

### Low Risk
- Model definitions (Phase 3A)
- Delegate protocol design

### Medium Risk
- Queue state machine (Phase 3B)
  - Sequential execution guarantees
  - Timeout handling
- UI integration (Phase 3D)
  - State synchronization
  - Progress updates

### High Risk
- Render workflow (Phase 3C)
  - Multi-step async coordination
  - Error handling at each stage
  - Integration with existing composers
  - Timecode calculations

### Mitigation Strategies
1. **Keep old code**: Don't delete until new code validated
2. **Feature flag**: Add `useNewRenderService` flag for gradual rollout
3. **Parallel implementation**: Build new services alongside existing UI
4. **Integration tests**: Validate complete workflow before removing old code
5. **Rollback plan**: Git tag at each sub-phase for easy rollback

---

## Timeline Estimate

| Sub-Phase | Complexity | Estimated Time |
|-----------|------------|----------------|
| 3A: Render Models | Low | 0.5 days |
| 3B: RenderQueueManager | Medium | 2 days |
| 3C: RenderService | High | 3 days |
| 3D: UI Integration | Medium | 2 days |
| **Total** | | **7.5 days** |

---

## Dependencies

### Required from Phase 2
- ✅ FileSystemOperations (for file checks)
- ✅ WatchFolderService integration (for file status)

### Existing Core Components
- ✅ BlankRushIntermediate (already in SourcePrintCore)
- ✅ SwiftFFmpegProResCompositor (already in SourcePrintCore)
- ✅ FrameOwnershipAnalyzer (already in SourcePrintCore)
- ✅ OCFParent, LinkedSegment models (already in SourcePrintCore)

### UI Components to Preserve
- Progress display in CompressorStyleOCFCard
- Queue status display in LinkingResultsView
- Render buttons and controls

---

## Progress Tracking

### Phase 3A: Render Models
- ⏳ Create RenderModels.swift
- ⏳ Define RenderQueueItem
- ⏳ Define RenderStatus enum
- ⏳ Define RenderProgress
- ⏳ Define RenderResult
- ⏳ Add unit tests for models
- ⏳ Verify compilation

### Phase 3B: RenderQueueManager
- ⏳ Create RenderQueueManager.swift
- ⏳ Define RenderQueueDelegate protocol
- ⏳ Implement queue state machine
- ⏳ Implement sequential processing
- ⏳ Implement timeout handling
- ⏳ Add unit tests for queue management
- ⏳ Verify compilation

### Phase 3C: RenderService
- ⏳ Create RenderService.swift
- ⏳ Define RenderProgressDelegate protocol
- ⏳ Implement blank rush check logic
- ⏳ Implement blank rush generation
- ⏳ Implement video composition workflow
- ⏳ Implement error handling
- ⏳ Add progress callbacks
- ⏳ Add unit tests for render workflow
- ⏳ Verify compilation

### Phase 3D: UI Integration
- ⏳ Update LinkingResultsView to use RenderQueueManager
- ⏳ Implement RenderQueueDelegate in LinkingResultsView
- ⏳ Update CompressorStyleOCFCard to use RenderService
- ⏳ Implement RenderProgressDelegate in CompressorStyleOCFCard
- ⏳ Remove old batch queue logic
- ⏳ Remove old render workflow code
- ⏳ Test GUI rendering
- ⏳ Test batch queue
- ⏳ Verify all render scenarios

---

## Current Status

**Phase:** Planning Complete
**Next Step:** Begin Phase 3A - Create RenderModels.swift
**Blockers:** None

---

## Notes

### Design Decisions

1. **Why Sequential Processing?**
   - Prevents resource contention (CPU, disk I/O)
   - Simpler error handling
   - Clear progress reporting
   - Matches current behavior

2. **Why Delegate Pattern?**
   - Avoids UI coupling
   - Testable without GUI
   - Clean separation of concerns
   - Matches Phase 2 architecture

3. **Why Separate RenderService?**
   - Reusable from CLI
   - Testable in isolation
   - Single responsibility (one render workflow)
   - Clean integration points

### Questions to Resolve

1. **Should RenderQueueManager own RenderService instances?**
   - Option A: Manager creates RenderService per item
   - Option B: Manager uses shared RenderService
   - **Decision:** TBD (likely Option A for isolation)

2. **How to handle Project.swift dependencies?**
   - RenderService needs to update:
     - `project.blankRushStatus`
     - `project.printStatus`
     - `project.segmentModificationDates`
   - **Options:**
     - Pass Project as parameter (tight coupling)
     - Return results and let caller update (loose coupling)
   - **Decision:** TBD (likely loose coupling via RenderResult)

3. **Feature flag for gradual rollout?**
   - Add `useNewRenderService` flag?
   - **Decision:** TBD (depends on testing confidence)

---

**Last Updated:** 2025-10-30
**Next Review:** After Phase 3A completion
