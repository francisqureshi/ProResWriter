# Phase 5 Kickoff - Full ViewModel Split

**Date:** 2025-10-31
**Status:** 📋 PLANNING (Not Started)
**Estimated Duration:** 2-3 weeks
**Risk Level:** Very High
**Priority:** Medium (Deferred)

---

## Executive Summary

Phase 5 completes the Model/ViewModel architectural separation started in Phase 4D by creating a full SwiftUI-reactive wrapper around the Core ProjectModel. This phase involves updating 20-30 view files to use the new ViewModel pattern, requiring extensive testing and careful management of SwiftUI reactivity.

**Current State:** Phase 4 achieved ~90% separation with business logic in Core and thin wrappers in UI.

**Goal:** Achieve 100% separation with a clean ProjectViewModel wrapping the pure ProjectModel.

**Recommendation:** **Defer** until business needs justify the high risk and complexity.

---

## Prerequisites

### Phase 4 Completion (Required)
- ✅ Phase 4A: BlankRushScanner in Core
- ✅ Phase 4B: AutoImportService in Core
- ✅ Phase 4C: ProjectOperations in Core
- ✅ Phase 4D Path A: ProjectModel in Core + duplicate types removed

### Foundation Already Exists
- ✅ ProjectModel with all data properties (272 lines)
- ✅ All business logic services in Core
- ✅ Clean type imports from Core to UI
- ✅ 69 passing tests in Core

---

## Problem Statement

### Current Architecture (Post Phase 4)

```swift
// macos/SourcePrint/Models/Project.swift (UI Layer)
class Project: ObservableObject, Codable, Identifiable, WatchFolderDelegate {
    // 18 @Published properties
    @Published var name: String
    @Published var ocfFiles: [MediaFileInfo]
    @Published var segments: [MediaFileInfo]
    @Published var linkingResult: LinkingResult?
    @Published var blankRushStatus: [String: BlankRushStatus]
    // ... 13 more @Published properties

    // Thin wrapper methods (delegate to Core services)
    func addOCFFiles(_ files: [MediaFileInfo]) {
        let result = ProjectOperations.addOCFFiles(...)
        applyOperationResult(result)
    }

    // UI-specific properties
    @Published var renderQueue: [RenderQueueItem] = []
    @Published var ocfCardExpansionState: [String: Bool] = [:]
    var watchFolderService: WatchFolderService?
}

// SourcePrintCore/Models/ProjectModel.swift (Core)
public struct ProjectModel: Codable, Identifiable {
    // Same 18 properties as Project (no @Published)
    public var name: String
    public var ocfFiles: [MediaFileInfo]
    // ... all the same data properties
}
```

### Issues with Current Approach

1. **Duplication:** Project.swift @Published properties mirror ProjectModel properties
2. **Codable Complexity:** Custom encode/decode to handle @Published wrappers
3. **Two Sources of Truth:** Data exists in both Project class and can exist in ProjectModel
4. **Mixed Responsibilities:** Project class handles both data + UI state + delegation

### Target Architecture (Phase 5)

```swift
// SourcePrintCore/Models/ProjectModel.swift (Core - Already exists)
public struct ProjectModel: Codable, Identifiable {
    public var name: String
    public var ocfFiles: [MediaFileInfo]
    public var segments: [MediaFileInfo]
    // ... all 18 data properties
}

// macos/SourcePrint/ViewModels/ProjectViewModel.swift (UI Layer - To create)
class ProjectViewModel: ObservableObject, WatchFolderDelegate {
    // Single source of truth for project data
    @Published private(set) var model: ProjectModel

    // UI-specific state only
    @Published var renderQueue: [RenderQueueItem] = []
    @Published var ocfCardExpansionState: [String: Bool] = [:]
    @Published var watchFolderSettings: WatchFolderSettings

    var watchFolderService: WatchFolderService?

    // All operations delegate to Core, update model
    func addOCFFiles(_ files: [MediaFileInfo]) {
        let result = ProjectOperations.addOCFFiles(files, existingOCFs: model.ocfFiles)
        applyOperationResult(result)
    }

    private func applyOperationResult(_ result: ProjectOperationResult) {
        if let updated = result.ocfFiles {
            model.ocfFiles = updated
            model.lastModified = Date()
        }
        // ...
    }
}

// Views use: @ObservedObject var viewModel: ProjectViewModel
// Access data via: viewModel.model.name
```

---

## Objectives

### Primary Goals

1. **Create ProjectViewModel wrapper** around ProjectModel
2. **Eliminate property duplication** between Project and ProjectModel
3. **Simplify Codable implementation** (ProjectModel is naturally Codable)
4. **Clear separation** between data (model) and presentation (viewModel)
5. **Maintain SwiftUI reactivity** throughout all views

### Success Criteria

- ✅ ProjectViewModel successfully wraps ProjectModel from Core
- ✅ All 20-30 views updated to use ViewModel pattern
- ✅ UI reactivity maintained (no regressions in SwiftUI updates)
- ✅ All functionality works (import, link, render, print, watch folder)
- ✅ Project save/load works correctly (Codable simplified)
- ✅ No performance degradation
- ✅ All manual tests pass

---

## Phase Breakdown

### Sub-Phase 5A: Create ProjectViewModel (Week 1)

**Estimated Duration:** 3-5 days
**Risk:** Medium

#### Tasks

1. **Create ProjectViewModel.swift** (`macos/SourcePrint/ViewModels/ProjectViewModel.swift`)
   - Wrap ProjectModel as `@Published private(set) var model: ProjectModel`
   - Move UI-specific @Published properties (renderQueue, ocfCardExpansionState, watchFolderSettings)
   - Implement WatchFolderDelegate protocol
   - Implement all wrapper methods that delegate to Core services

2. **Create initialization logic**
   - `init(model: ProjectModel)` - wrap existing model
   - `init(name: String, outputDir: URL, blankRushDir: URL)` - create new project

3. **Implement applyOperationResult**
   - Centralized method to apply ProjectOperationResult to model
   - Trigger SwiftUI updates via `@Published model` changes

4. **Move delegation methods**
   - Watch folder delegate methods
   - Service result handlers
   - Keep all business logic in Core, ViewModel only coordinates

5. **Create Codable support**
   - Encode/decode ProjectModel directly
   - Encode UI-specific state separately
   - Simpler than current Project.swift Codable implementation

#### Files Created
- `macos/SourcePrint/ViewModels/ProjectViewModel.swift` (~400-500 lines)

#### Files Modified
- None yet (parallel development)

---

### Sub-Phase 5B: Update View Files (Week 2)

**Estimated Duration:** 5-7 days
**Risk:** Very High

#### Strategy

**Incremental Migration Pattern:**
1. Update one view file at a time
2. Test immediately after each change
3. Use compiler to find all property access points
4. Update bindings carefully to maintain reactivity

#### Property Access Pattern Changes

**Before:**
```swift
struct ContentView: View {
    @ObservedObject var project: Project

    var body: some View {
        Text("Project: \(project.name)")
        Text("OCFs: \(project.ocfFiles.count)")

        Button("Add OCF") {
            project.addOCFFiles(selectedFiles)
        }
    }
}
```

**After:**
```swift
struct ContentView: View {
    @ObservedObject var viewModel: ProjectViewModel

    var body: some View {
        Text("Project: \(viewModel.model.name)")
        Text("OCFs: \(viewModel.model.ocfFiles.count)")

        Button("Add OCF") {
            viewModel.addOCFFiles(selectedFiles)
        }
    }
}
```

#### Binding Pattern Changes

**Before:**
```swift
TextField("Project Name", text: $project.name)
```

**After (Option 1 - Computed Binding):**
```swift
TextField("Project Name", text: Binding(
    get: { viewModel.model.name },
    set: { viewModel.updateName($0) }
))
```

**After (Option 2 - ViewModel Helper):**
```swift
extension ProjectViewModel {
    var nameBinding: Binding<String> {
        Binding(
            get: { self.model.name },
            set: { self.updateName($0) }
        )
    }
}

TextField("Project Name", text: viewModel.nameBinding)
```

#### Views to Update (~20-30 files)

**High Priority (Core Functionality):**
1. ✅ ContentView.swift - Main view, project references
2. ✅ LinkingResultsView.swift - Linking workflow, OCF access
3. ✅ MediaImportView.swift - Import workflow, segments access
4. ✅ OCFCard.swift - OCF display, status management
5. ✅ CompressorStyleOCFCard.swift - OCF card variant
6. ✅ RenderQueueView.swift - Render queue, print status
7. ✅ OverviewView.swift - Project overview, statistics

**Medium Priority (Features):**
8. ✅ WatchFolderSettingsView.swift - Watch folder configuration
9. ✅ BlankRushView.swift - Blank rush management
10. ✅ OfflineMediaView.swift - Offline file tracking
11. ✅ PrintHistoryView.swift - Print history display
12. ✅ ProjectSettingsView.swift - Project settings

**Lower Priority (Components):**
13. ✅ OCFStatusBadge.swift - Status display component
14. ✅ SegmentCard.swift - Segment display
15. ✅ LinkingStatusView.swift - Linking status
16. ✅ RenderQueueItemRow.swift - Queue item display
17-30. Other view components

#### Testing Checklist (After Each View Update)

- [ ] View compiles without errors
- [ ] SwiftUI preview works (if applicable)
- [ ] App launches successfully
- [ ] View displays correctly
- [ ] User interactions work (buttons, text fields)
- [ ] Data updates reflect in UI
- [ ] No performance issues

---

### Sub-Phase 5C: Update ProjectManager & Persistence (Week 2)

**Estimated Duration:** 2-3 days
**Risk:** Medium

#### Tasks

1. **Update ProjectManager.swift**
   - Change project storage from `Project` to `ProjectViewModel`
   - Update save/load methods to work with ProjectModel Codable
   - Handle UI-specific state (renderQueue, expansionState) separately

2. **Simplify save logic**
   ```swift
   // Before (Complex custom Codable)
   func saveProject(_ project: Project) throws {
       let encoder = JSONEncoder()
       let data = try encoder.encode(project) // Custom CodingKeys, @Published handling
       try data.write(to: url)
   }

   // After (Simple ProjectModel encoding)
   func saveProject(_ viewModel: ProjectViewModel) throws {
       let encoder = JSONEncoder()
       let data = try encoder.encode(viewModel.model) // ProjectModel is naturally Codable
       try data.write(to: url)

       // Save UI state separately if needed
       saveUIState(viewModel)
   }
   ```

3. **Update load logic**
   ```swift
   // After
   func loadProject(from url: URL) throws -> ProjectViewModel {
       let decoder = JSONDecoder()
       let data = try Data(contentsOf: url)
       let model = try decoder.decode(ProjectModel.self, from: data)

       // Load UI state separately
       let uiState = loadUIState(for: url)

       return ProjectViewModel(model: model, uiState: uiState)
   }
   ```

4. **Update recent projects tracking**
   - Store file URLs only
   - Load ProjectViewModel on demand
   - Handle migration from old Project format

#### Files Modified
- `macos/SourcePrint/Models/ProjectManager.swift`
- `macos/SourcePrint/SourcePrintApp.swift` (project initialization)

---

### Sub-Phase 5D: Testing & Validation (Week 3)

**Estimated Duration:** 3-5 days
**Risk:** Medium

#### Manual Testing Checklist

**Project Management:**
- [ ] Create new project
- [ ] Open existing project
- [ ] Save project
- [ ] Save As (duplicate project)
- [ ] Recent projects list works
- [ ] Project persistence across app restarts

**Media Import:**
- [ ] Import OCF files
- [ ] Import segment files
- [ ] Remove OCF files
- [ ] Remove segments
- [ ] Drag & drop import
- [ ] Batch import

**Linking:**
- [ ] Run linking analysis
- [ ] View linking results
- [ ] Expand/collapse OCF cards
- [ ] VFX shot detection
- [ ] Grade segment classification
- [ ] Timecode validation

**Blank Rush:**
- [ ] Create blank rush files
- [ ] Scan for existing blank rushes
- [ ] Blank rush status updates
- [ ] Progress tracking

**Print Process:**
- [ ] Print single OCF
- [ ] Print all queued OCFs
- [ ] Render queue management
- [ ] Print status updates
- [ ] Print history tracking
- [ ] Re-print flagging

**Watch Folder:**
- [ ] Enable/disable watch folders
- [ ] Auto-import new files
- [ ] Detect modified files
- [ ] Detect deleted files
- [ ] Offline file tracking
- [ ] Re-print marking on changes

**UI State:**
- [ ] OCF card expansion persists
- [ ] Window size/position persists
- [ ] Settings persist
- [ ] Render queue persists

**Edge Cases:**
- [ ] Large projects (100+ files)
- [ ] Quick successive saves
- [ ] App quit during operation
- [ ] File system errors
- [ ] Corrupted project files

#### Performance Testing

- [ ] Project load time < 1s (for typical project)
- [ ] UI responsiveness (no lag on interaction)
- [ ] Memory usage reasonable
- [ ] No memory leaks over extended use

#### Regression Testing

- [ ] All Phase 4 functionality still works
- [ ] No broken SwiftUI bindings
- [ ] No data loss on save/load
- [ ] No crashes

---

## Technical Challenges & Solutions

### Challenge 1: SwiftUI Reactivity

**Problem:** Nested property changes (viewModel.model.ocfFiles) may not trigger SwiftUI updates

**Solutions:**

**Option A: objectWillChange.send() (Explicit)**
```swift
class ProjectViewModel: ObservableObject {
    @Published private(set) var model: ProjectModel

    func addOCFFiles(_ files: [MediaFileInfo]) {
        objectWillChange.send() // Explicit notification
        let result = ProjectOperations.addOCFFiles(files, existingOCFs: model.ocfFiles)
        applyOperationResult(result)
    }
}
```

**Option B: Property Setter (Implicit)**
```swift
func addOCFFiles(_ files: [MediaFileInfo]) {
    var updatedModel = model
    let result = ProjectOperations.addOCFFiles(files, existingOCFs: updatedModel.ocfFiles)
    // Apply changes to updatedModel
    updatedModel.ocfFiles = result.ocfFiles ?? updatedModel.ocfFiles
    model = updatedModel // Triggers @Published change
}
```

**Recommendation:** Option B (cleaner, more SwiftUI-idiomatic)

---

### Challenge 2: Two-Way Bindings

**Problem:** TextField/Toggle need Binding<T>, but model is private(set)

**Solutions:**

**Option A: Individual Binding Helpers**
```swift
extension ProjectViewModel {
    var nameBinding: Binding<String> {
        Binding(
            get: { self.model.name },
            set: { newValue in
                self.model.name = newValue
                self.model.lastModified = Date()
            }
        )
    }
}
```

**Option B: Generic Binding Helper**
```swift
extension ProjectViewModel {
    func binding<T>(for keyPath: WritableKeyPath<ProjectModel, T>) -> Binding<T> {
        Binding(
            get: { self.model[keyPath: keyPath] },
            set: { newValue in
                self.model[keyPath: keyPath] = newValue
                self.model.lastModified = Date()
            }
        )
    }
}

// Usage:
TextField("Name", text: viewModel.binding(for: \.name))
```

**Recommendation:** Mix of both - individual helpers for frequently used, generic for simple cases

---

### Challenge 3: Codable Simplification

**Problem:** Current Project.swift has complex custom Codable with CodingKeys

**Solution:**

```swift
// ProjectModel is naturally Codable (no @Published wrappers)
struct ProjectPersistence: Codable {
    let model: ProjectModel
    let renderQueue: [RenderQueueItem]?
    let ocfCardExpansionState: [String: Bool]?
    let watchFolderSettings: WatchFolderSettings?
}

// ViewModel save/load
func save() throws {
    let persistence = ProjectPersistence(
        model: model,
        renderQueue: renderQueue,
        ocfCardExpansionState: ocfCardExpansionState,
        watchFolderSettings: watchFolderSettings
    )
    let data = try JSONEncoder().encode(persistence)
    try data.write(to: fileURL)
}
```

**Benefit:** Much simpler than current custom CodingKeys approach

---

### Challenge 4: Migration from Old Format

**Problem:** Existing .w2 files use Project class format

**Solution:**

```swift
func loadProject(from url: URL) throws -> ProjectViewModel {
    let data = try Data(contentsOf: url)

    // Try new format first
    if let persistence = try? JSONDecoder().decode(ProjectPersistence.self, from: data) {
        return ProjectViewModel(
            model: persistence.model,
            renderQueue: persistence.renderQueue ?? [],
            // ...
        )
    }

    // Fall back to old Project format
    if let oldProject = try? JSONDecoder().decode(Project.self, from: data) {
        return migrateToViewModel(oldProject)
    }

    throw ProjectError.invalidFormat
}

func migrateToViewModel(_ project: Project) -> ProjectViewModel {
    let model = ProjectModel(
        id: project.id,
        name: project.name,
        // ... copy all properties
    )
    return ProjectViewModel(model: model, renderQueue: project.renderQueue)
}
```

**Benefit:** Backward compatibility with existing projects

---

## Risk Assessment

### Very High Risks

1. **SwiftUI Reactivity Breakage**
   - **Impact:** UI doesn't update when data changes
   - **Likelihood:** Medium
   - **Mitigation:** Extensive testing, use proven patterns, incremental updates

2. **Binding Complexity**
   - **Impact:** Form fields don't work correctly
   - **Likelihood:** Medium
   - **Mitigation:** Helper methods, thorough testing of all inputs

3. **Performance Degradation**
   - **Impact:** UI lag, slow updates
   - **Likelihood:** Low
   - **Mitigation:** Profile before/after, optimize if needed

### Medium Risks

4. **Migration Issues**
   - **Impact:** Old projects can't load
   - **Likelihood:** Low
   - **Mitigation:** Backward compatibility layer, version detection

5. **Codable Edge Cases**
   - **Impact:** Project save/load fails
   - **Likelihood:** Low
   - **Mitigation:** Comprehensive save/load testing

---

## Rollback Plan

### If Phase 5 Fails

1. **Git Branch Strategy**
   - Create `feature/phase5-viewmodel` branch
   - Keep `main` branch on Phase 4 completion
   - Only merge when Phase 5 fully validated

2. **Feature Flag (Optional)**
   ```swift
   #if USE_VIEWMODEL_PATTERN
       @StateObject var viewModel = ProjectViewModel(...)
   #else
       @StateObject var project = Project(...)
   #endif
   ```

3. **Rollback Steps**
   - Revert to Phase 4 completion commit
   - Document lessons learned
   - Re-evaluate Phase 5 approach

---

## Alternatives to Full Phase 5

### Option 1: Incremental ViewModel Adoption

**Approach:** Add ViewModel alongside existing Project class
- Views can gradually migrate to ViewModel
- Both patterns coexist during transition
- Lower risk but longer timeline

### Option 2: Wait for SwiftUI Improvements

**Approach:** Defer until SwiftUI has better struct-based patterns
- Apple may introduce better patterns in future OS versions
- Current Phase 4 architecture is already good enough
- Lowest risk

### Option 3: CLI-First ViewModel

**Approach:** Create ViewModel for CLI tool first
- Lower risk (no SwiftUI reactivity concerns)
- Validates ViewModel design
- GUI can adopt later if successful

---

## Decision: Defer Phase 5

### Rationale

**Costs:**
- 2-3 weeks development time
- Very high risk of breaking UI
- Extensive manual testing required
- Marginal architectural benefit over Phase 4

**Benefits:**
- Slightly cleaner architecture (100% vs 90% separation)
- Simpler Codable implementation
- One less class (Project → ProjectViewModel)

**Conclusion:** **Costs outweigh benefits at this time.**

### When to Revisit Phase 5

**Pursue Phase 5 if:**
1. Building cross-platform UI (iOS, Linux, etc.) requires shared ViewModel
2. Team grows and architectural purity becomes more valuable
3. SwiftUI improvements make migration easier
4. Major UI refactoring is already planned (piggyback on that work)
5. Business requirements justify the time investment

**Current Recommendation:** Stay on Phase 4 architecture, focus on feature development.

---

## Appendix: File Listing

### Files to Create

```
macos/SourcePrint/ViewModels/
└── ProjectViewModel.swift (~400-500 lines)

docs/architecture_audit/phase5/
├── phase5_kickoff.md (this document)
├── phase5a_completion.md (if pursued)
├── phase5b_completion.md (if pursued)
├── phase5c_completion.md (if pursued)
└── phase5d_completion.md (if pursued)
```

### Files to Modify (20-30 total)

```
macos/SourcePrint/
├── Models/
│   ├── ProjectManager.swift
│   └── Project.swift (deprecate or remove)
├── Views/
│   ├── ContentView.swift
│   ├── LinkingResultsView.swift
│   ├── MediaImportView.swift
│   ├── OCFCard.swift
│   ├── CompressorStyleOCFCard.swift
│   ├── RenderQueueView.swift
│   ├── OverviewView.swift
│   ├── WatchFolderSettingsView.swift
│   ├── BlankRushView.swift
│   ├── OfflineMediaView.swift
│   ├── PrintHistoryView.swift
│   ├── ProjectSettingsView.swift
│   └── Components/
│       ├── OCFStatusBadge.swift
│       ├── SegmentCard.swift
│       ├── LinkingStatusView.swift
│       ├── RenderQueueItemRow.swift
│       └── [15+ other component files]
└── SourcePrintApp.swift
```

---

## Conclusion

Phase 5 represents the final step in complete architectural separation, but **should be deferred** due to high risk and marginal benefit over the already-excellent Phase 4 architecture.

**Current State After Phase 4:**
- ✅ ~870 lines of business logic in Core
- ✅ 39 comprehensive tests
- ✅ Clean separation of concerns
- ✅ Testable, reusable services
- ✅ Ready for CLI/cross-platform work

**Phase 5 can be pursued later if business needs justify the complexity.**

**For now, focus on feature development and leverage the solid Phase 4 foundation! 🚀**
