# Phase 4 Kickoff - Current State Summary

**Date:** 2025-10-31
**Status:** Ready to Begin
**Strategy:** Incremental extraction (4A → 4B → 4C → 4D)

---

## Current Architecture State

### ✅ Completed Refactoring (Phases 1-3)

**Phase 1: File System Utilities** ✅
- FileSystemOperations.swift (104 lines)
- VideoFileDiscovery.swift (97 lines)
- 33 passing unit tests
- UI layer now uses Core utilities

**Phase 2: Watch Folder Service** ✅
- WatchFolderService.swift (192 lines)
- FileChangeDetector.swift (201 lines)
- Core models: OfflineFileMetadata, FileChangeSet, FileClassification
- 45+ passing unit tests
- Clean delegate pattern

**Phase 3: Render Queue Manager** ✅
- RenderQueueManager.swift (279 lines)
- RenderService.swift (305 lines)
- Progress bars with FPS counters
- Removed 540+ lines from UI layer
- LinkingResultsView: 930 → 743 lines (-20%)
- CompressorStyleOCFCard: 609 → 256 lines (-58%)

### 📊 Lines Moved to Core (So Far)

| Phase | Lines to Core | Lines Removed from UI |
|-------|---------------|----------------------|
| Phase 1 | ~200 | ~100 |
| Phase 2 | ~400 | ~250 |
| Phase 3 | ~600 | ~540 |
| **Total** | **~1,200** | **~890** |

---

## Current Violations Remaining

### Project.swift Analysis

**Current Size:** 1,049 lines
**Target After Phase 4:** ~200-300 lines (ViewModel only)

**Remaining Business Logic:**

1. **File System Helpers** (lines 426-476, ~50 lines) - **Phase 4A target**
   - `getFileModificationDate(for:)` - Wrapper around Core utility
   - `getFileSize(for:)` - Wrapper around Core utility
   - `calculatePartialHash(for:)` - Wrapper around Core utility
   - `scanForExistingBlankRushes()` - Uses file system ops

2. **Watch Folder Integration** (lines 482-889, ~400 lines) - **Phase 4B target**
   - WatchFolderDelegate implementation (4 methods)
   - Watch folder lifecycle management
   - File classification logic (new, returning, changed)
   - Automatic import triggering
   - Size/hash comparison for offline detection
   - Print status updates

3. **Project Management** (lines 221-422, ~200 lines) - **Phase 4C target**
   - `addOCFFiles(_:)` - Add media to project
   - `addSegments(_:)` - Add segments with tracking
   - `removeOCFFiles(_:)` - Remove with cleanup
   - `removeSegments(_:)` - Remove with cleanup
   - `refreshSegmentModificationDates()` - Update from FS
   - `updateLinkingResult(_:)` - Update linking state
   - `checkForModifiedSegmentsAndUpdatePrintStatus()` - Status updates
   - `refreshPrintStatus()` - Status refresh
   - `toggleOCFVFXStatus(_:isVFX:)` - Toggle flags
   - `toggleSegmentVFXStatus(_:isVFX:)` - Toggle flags

4. **SwiftUI Coupling** (~100-150 lines) - **Phase 4D target**
   - `@ObservableObject` conformance
   - `@Published` property wrappers (18 properties)
   - Mixed data model + UI reactivity

---

## Phase 4 Incremental Plan

### Phase 4A: File System Operations (1-2 days)
**Risk:** Low | **Lines to Remove:** ~50

**Actions:**
1. Replace `getFileModificationDate` wrapper with direct Core calls
2. Replace `getFileSize` wrapper with direct Core calls
3. Replace `calculatePartialHash` wrapper with direct Core calls
4. Move `scanForExistingBlankRushes()` to new BlankRushScanner service

**Files to Create:**
- `BlankRushScanner.swift` (SourcePrintCore)

**Expected Result:**
- Project.swift: 1,049 → ~999 lines

---

### Phase 4B: Watch Folder Integration (3-5 days)
**Risk:** Medium | **Lines to Remove:** ~350

**Actions:**
1. Create AutoImportService in Core
2. Move file classification logic to AutoImportService
3. Simplify WatchFolderDelegate methods to thin wrappers
4. Delegate all import decisions to service

**Files to Create:**
- `AutoImportService.swift` (SourcePrintCore, ~250 lines)

**Expected Result:**
- Project.swift: ~999 → ~649 lines

---

### Phase 4C: Project Management Operations (5-7 days)
**Risk:** Medium | **Lines to Remove:** ~150-200

**Actions:**
1. Create ProjectOperations service in Core
2. Move all add/remove/update operations to service
3. Move status refresh logic to service
4. Update Project.swift to delegate to service

**Files to Create:**
- `ProjectOperations.swift` (SourcePrintCore, ~200 lines)

**Expected Result:**
- Project.swift: ~649 → ~450-500 lines

---

### Phase 4D: Model/ViewModel Split (2-3 weeks)
**Risk:** High | **Lines to Remove:** ~200-250 (+ restructuring)

**Actions:**
1. Extract pure data model to ProjectModel.swift
2. Create ProjectViewModel as SwiftUI wrapper
3. Create ProjectWorkflow for high-level coordination
4. Update all views to use ViewModel

**Files to Create:**
- `ProjectModel.swift` (SourcePrintCore, ~300 lines)
- `ProjectViewModel.swift` (UI layer, ~200-300 lines)
- `ProjectWorkflow.swift` (SourcePrintCore, ~150 lines)

**Expected Result:**
- ProjectModel: ~300 lines (pure data)
- ProjectViewModel: ~200-300 lines (SwiftUI wrapper)
- Total: Clean separation achieved ✅

---

## Testing Requirements

### Unit Tests (Required for Each Phase)

**Phase 4A:**
- BlankRushScanner tests (file existence, scanning logic)

**Phase 4B:**
- AutoImportService tests (classification, detection, import)
- File detection scenarios (new, returning, changed)
- Offline handling tests

**Phase 4C:**
- ProjectOperations tests (all CRUD operations)
- Status management tests
- VFX toggle tests

**Phase 4D:**
- ProjectModel serialization tests
- ViewModel reactivity tests
- ProjectWorkflow integration tests

### Integration Tests (After Each Phase)

Manual testing checklist:
- [ ] Import media files (OCFs and segments)
- [ ] Watch folder auto-import
- [ ] Perform linking
- [ ] Create blank rushes
- [ ] Render OCFs (batch and single)
- [ ] Offline file handling
- [ ] File modification detection
- [ ] Project save/load
- [ ] App restart persistence

---

## Risk Management

### Low Risk (Phase 4A)
- Simple utility extraction
- Already have Core utilities, just replacing wrappers
- Easy rollback if needed

### Medium Risk (Phases 4B, 4C)
- More complex business logic
- Multiple interdependencies
- Requires careful testing

**Mitigation:**
- Comprehensive unit tests
- Manual testing after each change
- Small, incremental commits
- Git tags for rollback points

### High Risk (Phase 4D)
- Major architectural change
- SwiftUI coupling is deep
- Risk of breaking UI reactivity

**Mitigation:**
- Detailed sub-plan before starting
- Parallel implementation (keep old code)
- Extensive integration testing
- Staged rollout if needed

---

## Success Criteria

### Phase Completion Metrics

| Phase | Success Criteria |
|-------|-----------------|
| 4A | ✅ BlankRushScanner tested<br>✅ All wrappers removed<br>✅ ~50 lines removed<br>✅ App builds and runs |
| 4B | ✅ AutoImportService tested<br>✅ Watch folder logic in Core<br>✅ ~350 lines removed<br>✅ Auto-import works |
| 4C | ✅ ProjectOperations tested<br>✅ All management ops in Core<br>✅ ~150-200 lines removed<br>✅ CRUD operations work |
| 4D | ✅ Clean model/viewmodel split<br>✅ All workflows in Core<br>✅ UI reactivity intact<br>✅ CLI can use ProjectModel |

### Final Architecture Goals

**After Phase 4 Complete:**

```
SourcePrintCore/
├── Models/
│   ├── ProjectModel.swift ✨ (pure data, no SwiftUI)
│   └── ... (other models)
├── Workflows/
│   ├── ProjectWorkflow.swift ✨ (coordination)
│   ├── ProjectOperations.swift ✨ (CRUD)
│   ├── AutoImportService.swift ✨ (watch folder integration)
│   ├── BlankRushScanner.swift ✨ (blank rush detection)
│   ├── RenderQueueManager.swift (Phase 3)
│   ├── RenderService.swift (Phase 3)
│   ├── WatchFolderService.swift (Phase 2)
│   └── FileChangeDetector.swift (Phase 2)
└── Utilities/
    ├── FileSystemOperations.swift (Phase 1)
    └── VideoFileDiscovery.swift (Phase 1)

UI Layer/
└── Models/
    └── ProjectViewModel.swift ✨ (thin SwiftUI wrapper)
```

**Total Lines in Core:** ~3,000+ lines of testable business logic
**Project.swift → ProjectViewModel:** ~200-300 lines (90% reduction)

---

## Timeline

| Phase | Duration | Start | End |
|-------|----------|-------|-----|
| 4A | 1-2 days | Day 1 | Day 2 |
| 4B | 3-5 days | Day 3 | Day 7 |
| 4C | 5-7 days | Day 8 | Day 14 |
| 4D | 2-3 weeks | Day 15 | Day 35 |

**Total Duration:** 4-7 weeks

---

## Ready to Start? 🚀

**Phase 4A is up first!**

Next steps:
1. Create `BlankRushScanner.swift` in SourcePrintCore
2. Replace file system wrapper methods
3. Update Project.swift to use new scanner
4. Write comprehensive tests
5. Validate and move to Phase 4B

---

**Let's build this! 💪**
