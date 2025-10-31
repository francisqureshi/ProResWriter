# Phase 4: Project Model Refactoring - Incremental Plan

**Project:** SourcePrint Architecture Refactoring
**Goal:** Extract all remaining business logic from Project.swift into SourcePrintCore
**Strategy:** Incremental extraction with validation at each step
**Date:** 2025-10-31

---

## Table of Contents

1. [Overview](#overview)
2. [Phase 4A: File System Operations](#phase-4a-file-system-operations)
3. [Phase 4B: Watch Folder Integration](#phase-4b-watch-folder-integration)
4. [Phase 4C: Project Management Operations](#phase-4c-project-management-operations)
5. [Phase 4D: Model/ViewModel Split](#phase-4d-modelviewmodel-split)
6. [Testing Strategy](#testing-strategy)
7. [Risk Mitigation](#risk-mitigation)

---

## Overview

### Current State (Post-Phase 3)

**Project.swift:** 1,049 lines
- ✅ Phases 1-3 completed (~600 lines moved to Core)
- ⚠️ Still contains ~500 lines of business logic

**Remaining Violations:**
1. File system helpers (lines 426-476, ~50 lines) - **Low Risk**
2. Watch folder integration (lines 482-889, ~400 lines) - **Medium Risk**
3. Project management operations (lines 221-422, ~200 lines) - **Medium Risk**
4. SwiftUI coupling (@ObservableObject + @Published) - **High Risk**

### Incremental Approach Benefits

✅ **Lower Risk** - Validate each extraction before proceeding
✅ **Faster Feedback** - See architectural improvements quickly
✅ **Easy Rollback** - Small commits, easy to revert if needed
✅ **Maintains Stability** - App stays functional throughout refactoring

---

## Phase 4A: File System Operations

**Duration:** 1-2 days
**Risk:** Low
**Priority:** High (foundational)

### Objectives

Move remaining file system operations from Project.swift to SourcePrintCore utilities:
- `getFileModificationDate(for:)` - Already in Core, need to replace usage
- `getFileSize(for:)` - Already in Core, need to replace usage
- `calculatePartialHash(for:)` - Already in Core, need to replace usage
- `scanForExistingBlankRushes()` - Business logic that uses file system ops

### Files to Modify

**Project.swift** (lines 426-476)
- Remove private file system helper methods
- Replace with calls to `FileSystemOperations` utility
- Keep `scanForExistingBlankRushes()` but delegate to Core

**SourcePrintCore utilities** (already exist)
- `FileSystemOperations.swift` - Already has all needed methods
- Just need to update Project.swift to use them

### Implementation Steps

#### Step 4A.1: Replace `getFileModificationDate` Usage (30 min)

**Current Code (Project.swift:426-434):**
```swift
private func getFileModificationDate(for url: URL) -> Date? {
    switch FileSystemOperations.getModificationDate(for: url) {
    case .success(let date):
        return date
    case .failure(let error):
        print("⚠️ \(error.localizedDescription)")
        return nil
    }
}
```

**Action:** Remove this wrapper, replace all usages with direct calls to `FileSystemOperations.getModificationDate(for:)`

**Usages to update:**
- Line 90: `hasModifiedSegments` computed property
- Line 247: `refreshSegmentModificationDates()`
- Line 551: `checkForChangedFilesOnStartup()`

**After:**
```swift
// Example replacement
if let fileModDate = getFileModificationDate(for: child.segment.url)
// Becomes:
if case .success(let fileModDate) = FileSystemOperations.getModificationDate(for: child.segment.url)
```

#### Step 4A.2: Replace `getFileSize` Usage (30 min)

**Current Code (Project.swift:436-445):**
```swift
private func getFileSize(for url: URL) -> Int64? {
    switch FileSystemOperations.getFileSize(for: url) {
    case .success(let size):
        return size
    case .failure(let error):
        print("⚠️ \(error.localizedDescription)")
        return nil
    }
}
```

**Action:** Remove wrapper, replace all usages

**Usages to update:**
- Line 552: `checkForChangedFilesOnStartup()`
- Lines 651-696: `handleDetectedVideoFiles()` - multiple size checks

#### Step 4A.3: Replace `calculatePartialHash` Usage (30 min)

**Current Code (Project.swift:447-456):**
```swift
private func calculatePartialHash(for url: URL) -> String? {
    switch FileSystemOperations.calculatePartialHash(for: url) {
    case .success(let hash):
        return hash
    case .failure(let error):
        print("⚠️ \(error.localizedDescription)")
        return nil
    }
}
```

**Action:** Remove wrapper, replace all usages

**Usages to update:**
- Lines 673-690: `handleDetectedVideoFiles()` - hash comparison for offline files

#### Step 4A.4: Move `scanForExistingBlankRushes` to Core (2-3 hours)

**Current Code (Project.swift:458-476):**
```swift
func scanForExistingBlankRushes() {
    guard let linkingResult = linkingResult else { return }

    for parent in linkingResult.parentsWithChildren {
        let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
        let blankRushFileName = "\(baseName)_blankRush.mov"
        let blankRushURL = blankRushDirectory.appendingPathComponent(blankRushFileName)

        if FileManager.default.fileExists(atPath: blankRushURL.path) {
            blankRushStatus[parent.ocf.fileName] = .completed(date: Date(), url: blankRushURL)
        }
    }
    updateModified()
}
```

**New File:** `SourcePrintCore/Workflows/BlankRushScanner.swift`

```swift
import Foundation

/// Service for scanning and detecting existing blank rush files
public class BlankRushScanner {

    /// Scan directory for existing blank rush files matching OCF parents
    ///
    /// - Parameters:
    ///   - linkingResult: Linking result with OCF parents
    ///   - blankRushDirectory: Directory to scan
    /// - Returns: Dictionary of OCF filename to blank rush URL
    public static func scanForExistingBlankRushes(
        linkingResult: LinkingResult,
        blankRushDirectory: URL
    ) -> [String: URL] {
        var foundBlankRushes: [String: URL] = [:]

        for parent in linkingResult.parentsWithChildren {
            let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
            let blankRushFileName = "\(baseName)_blankRush.mov"
            let blankRushURL = blankRushDirectory.appendingPathComponent(blankRushFileName)

            if FileManager.default.fileExists(atPath: blankRushURL.path) {
                foundBlankRushes[parent.ocf.fileName] = blankRushURL
                NSLog("✅ Found existing blank rush: \(blankRushFileName)")
            }
        }

        NSLog("📊 Scan complete: Found \(foundBlankRushes.count)/\(linkingResult.parentsWithChildren.count) blank rushes")
        return foundBlankRushes
    }

    /// Check if blank rush exists for specific OCF
    public static func blankRushExists(
        for ocfFileName: String,
        in directory: URL
    ) -> Bool {
        let baseName = (ocfFileName as NSString).deletingPathExtension
        let blankRushFileName = "\(baseName)_blankRush.mov"
        let blankRushURL = directory.appendingPathComponent(blankRushFileName)
        return FileManager.default.fileExists(atPath: blankRushURL.path)
    }
}
```

**Update Project.swift:**
```swift
func scanForExistingBlankRushes() {
    guard let linkingResult = linkingResult else { return }

    let found = BlankRushScanner.scanForExistingBlankRushes(
        linkingResult: linkingResult,
        blankRushDirectory: blankRushDirectory
    )

    for (ocfFileName, url) in found {
        blankRushStatus[ocfFileName] = .completed(date: Date(), url: url)
    }
    updateModified()
}
```

### Testing

**Unit Tests:** `BlankRushScannerTests.swift`
```swift
func testScanForExistingBlankRushes() {
    // Create test directory with blank rushes
    let testDir = createTestDirectory()
    createFile(at: testDir, name: "OCF001_blankRush.mov")
    createFile(at: testDir, name: "OCF002_blankRush.mov")

    let result = createMockLinkingResult(ocfNames: ["OCF001.mov", "OCF002.mov", "OCF003.mov"])

    let found = BlankRushScanner.scanForExistingBlankRushes(
        linkingResult: result,
        blankRushDirectory: testDir
    )

    XCTAssertEqual(found.count, 2)
    XCTAssertNotNil(found["OCF001.mov"])
    XCTAssertNotNil(found["OCF002.mov"])
    XCTAssertNil(found["OCF003.mov"])
}
```

### Success Criteria

- ✅ All file system helper methods removed from Project.swift
- ✅ All usages updated to use Core utilities
- ✅ BlankRushScanner tested and integrated
- ✅ App builds and runs without issues
- ✅ ~50 lines removed from Project.swift

**Estimated Lines Removed:** 50 lines
**Project.swift Target:** ~999 lines

---

## Phase 4B: Watch Folder Integration

**Duration:** 3-5 days
**Risk:** Medium
**Priority:** High

### Objectives

Move watch folder integration logic from Project.swift to a dedicated service in Core:
- File classification logic (new, returning, changed)
- Automatic import triggering
- Size/hash comparison for offline detection
- Print status updates based on file changes

### Current State Analysis

**Project.swift Watch Folder Code (lines 482-889, ~400 lines):**
1. **WatchFolderDelegate Implementation** (lines 482-497)
   - 4 delegate methods that just route to internal handlers

2. **Watch Folder Lifecycle** (lines 500-634)
   - `updateWatchFolderMonitoring()` - Start/stop based on settings
   - `startWatchFolderIfNeeded()` - Service initialization
   - `checkForChangedFilesOnStartup()` - Startup detection
   - `stopWatchFolder()` - Cleanup

3. **File Detection Handlers** (lines 636-891)
   - `handleDetectedVideoFiles()` - 92 lines of classification logic
   - `analyzeDetectedFiles()` - Media analysis orchestration
   - `handleDeletedVideoFiles()` - Offline tracking
   - `handleModifiedVideoFiles()` - Change detection

**Problem:** All this business logic is in the UI model

### Architecture Goal

```
SourcePrintCore:
├── WatchFolderService (existing)
├── FileChangeDetector (existing)
└── AutoImportService (NEW)
    ├── classifyDetectedFiles()
    ├── handleNewFiles()
    ├── handleReturningFiles()
    └── handleModifiedFiles()

UI Layer:
└── ProjectViewModel (thin wrapper)
    └── Delegates all work to AutoImportService
```

### Files to Create

#### File 1: `AutoImportService.swift` (SourcePrintCore)

**Purpose:** Orchestrate automatic import when watch folder detects files

**Location:** `/Users/mac10/Projects/SourcePrint/SourcePrintCore/Sources/SourcePrintCore/Workflows/AutoImportService.swift`

```swift
import Foundation

/// Protocol for auto-import events
@MainActor
public protocol AutoImportDelegate: AnyObject {
    /// Called when new files should be imported
    func autoImport(_ service: AutoImportService, shouldImportFiles files: [URL], isVFX: Bool)

    /// Called when offline files return
    func autoImport(_ service: AutoImportService, didDetectReturningFiles: [String], unchanged: [URL], changed: [URL])

    /// Called when online files are modified
    func autoImport(_ service: AutoImportService, didDetectModifiedFiles fileNames: [String])
}

/// Service for handling automatic import from watch folders
@MainActor
public class AutoImportService {

    public weak var delegate: AutoImportDelegate?

    private let mediaAnalyzer: MediaAnalyzer

    public init(mediaAnalyzer: MediaAnalyzer = MediaAnalyzer()) {
        self.mediaAnalyzer = mediaAnalyzer
    }

    // MARK: - File Detection Handling

    /// Process detected video files and classify them
    public func processDetectedFiles(
        _ urls: [URL],
        isVFX: Bool,
        existingSegments: [MediaFileInfo],
        offlineFiles: Set<String>,
        offlineMetadata: [String: OfflineFileMetadata],
        trackedSizes: [String: Int64]
    ) async -> DetectionResult {

        // Classify files using FileChangeDetector
        let classification = FileChangeDetector.classifyFiles(
            detectedFiles: urls,
            existingSegments: existingSegments,
            offlineFiles: offlineFiles,
            offlineMetadata: offlineMetadata,
            trackedSizes: trackedSizes
        )

        // Handle returning offline files (unchanged)
        var returningFileActions: [String: OfflineAction] = [:]
        for url in classification.returningUnchanged {
            let fileName = url.lastPathComponent
            returningFileActions[fileName] = .markOnline
            NSLog("✅ File %@ is back online (unchanged)", fileName)
        }

        // Handle returning offline files (changed)
        var modifiedFileActions: [String: ModificationAction] = [:]
        for url in classification.returningChanged {
            let fileName = url.lastPathComponent

            // Get new size
            if case .success(let newSize) = FileSystemOperations.getFileSize(for: url) {
                modifiedFileActions[fileName] = ModificationAction(
                    fileName: fileName,
                    newSize: newSize,
                    action: .markModifiedAndOnline
                )
                NSLog("✅ File %@ is back online (changed - size: %lld)", fileName, newSize)
            }
        }

        // Handle existing online files that were modified
        for url in classification.existingModified {
            let fileName = url.lastPathComponent

            if case .success(let newSize) = FileSystemOperations.getFileSize(for: url) {
                modifiedFileActions[fileName] = ModificationAction(
                    fileName: fileName,
                    newSize: newSize,
                    action: .markModified
                )
                NSLog("⚠️ Online file modified: %@ (size: %lld)", fileName, newSize)
            }
        }

        // Analyze new files for import (if any)
        var newlyAnalyzedFiles: [MediaFileInfo] = []
        if !classification.newFiles.isEmpty {
            NSLog("🎬 Analyzing %d new files for import...", classification.newFiles.count)
            newlyAnalyzedFiles = await analyzeFiles(classification.newFiles, isVFX: isVFX)
        }

        return DetectionResult(
            newFiles: newlyAnalyzedFiles,
            returningFiles: returningFileActions,
            modifiedFiles: modifiedFileActions,
            isVFX: isVFX
        )
    }

    /// Analyze files for import
    private func analyzeFiles(_ urls: [URL], isVFX: Bool) async -> [MediaFileInfo] {
        var results: [MediaFileInfo] = []

        for url in urls {
            do {
                NSLog("📹 Analyzing: %@", url.lastPathComponent)
                var mediaFile = try await mediaAnalyzer.analyzeMediaFile(
                    at: url,
                    type: .gradedSegment
                )

                // Set VFX flag if from VFX folder
                if isVFX {
                    mediaFile.isVFXShot = true
                }

                results.append(mediaFile)
                NSLog("✅ Analyzed: %@", url.lastPathComponent)
            } catch {
                NSLog("❌ Failed to analyze %@: %@", url.lastPathComponent, error.localizedDescription)
            }
        }

        NSLog("✅ Analysis complete: %d/%d files analyzed", results.count, urls.count)
        return results
    }

    // MARK: - Deletion Handling

    /// Process deleted files
    public func processDeletedFiles(
        _ fileNames: [String],
        existingSegments: [MediaFileInfo]
    ) -> DeletionResult {

        var offlineFiles: [String] = []
        var offlineMetadata: [String: OfflineFileMetadata] = [:]

        for fileName in fileNames {
            // Find the segment
            guard let segment = existingSegments.first(where: { $0.fileName == fileName }) else {
                NSLog("⚠️ Deleted file not found in segments: %@", fileName)
                continue
            }

            // Get file metadata before it's gone
            let fileSize: Int64
            if case .success(let size) = FileSystemOperations.getFileSize(for: segment.url) {
                fileSize = size
            } else {
                fileSize = 0  // Unknown size
            }

            // Create offline metadata
            let metadata = OfflineFileMetadata(
                fileName: fileName,
                fileSize: fileSize,
                offlineDate: Date(),
                partialHash: nil  // Don't have file anymore
            )

            offlineFiles.append(fileName)
            offlineMetadata[fileName] = metadata

            NSLog("📴 Marking file as offline: %@ (size: %lld bytes)", fileName, fileSize)
        }

        return DeletionResult(
            offlineFiles: offlineFiles,
            offlineMetadata: offlineMetadata
        )
    }

    // MARK: - Modification Handling

    /// Process modified files
    public func processModifiedFiles(
        _ fileNames: [String],
        existingSegments: [MediaFileInfo]
    ) -> ModificationResult {

        var modifications: [String: ModificationAction] = [:]

        for fileName in fileNames {
            guard let segment = existingSegments.first(where: { $0.fileName == fileName }) else {
                continue
            }

            // Get new file size
            if case .success(let newSize) = FileSystemOperations.getFileSize(for: segment.url) {
                modifications[fileName] = ModificationAction(
                    fileName: fileName,
                    newSize: newSize,
                    action: .markModified
                )
                NSLog("⚠️ File modified: %@ (new size: %lld bytes)", fileName, newSize)
            }
        }

        return ModificationResult(modifications: modifications)
    }
}

// MARK: - Result Types

/// Result of file detection processing
public struct DetectionResult {
    public let newFiles: [MediaFileInfo]
    public let returningFiles: [String: OfflineAction]
    public let modifiedFiles: [String: ModificationAction]
    public let isVFX: Bool
}

public enum OfflineAction {
    case markOnline
}

public struct ModificationAction {
    public let fileName: String
    public let newSize: Int64
    public let action: ModificationActionType
}

public enum ModificationActionType {
    case markModified
    case markModifiedAndOnline
}

/// Result of file deletion processing
public struct DeletionResult {
    public let offlineFiles: [String]
    public let offlineMetadata: [String: OfflineFileMetadata]
}

/// Result of file modification processing
public struct ModificationResult {
    public let modifications: [String: ModificationAction]
}
```

### Implementation Steps

#### Step 4B.1: Create AutoImportService (4-6 hours)

1. Create the new file in SourcePrintCore
2. Write comprehensive unit tests
3. Verify it compiles with Core

#### Step 4B.2: Update Project.swift to Use AutoImportService (6-8 hours)

**Before (Project.swift:636-727):**
```swift
private func handleDetectedVideoFiles(_ videoFiles: [URL], isVFX: Bool) {
    // 92 lines of classification logic
    // Size comparisons
    // Hash calculations
    // Import triggering
}
```

**After:**
```swift
private var autoImportService: AutoImportService?

// In init:
self.autoImportService = AutoImportService()
self.autoImportService?.delegate = self

// Simplified handler:
func watchFolder(_ service: WatchFolderService, didDetectNewFiles files: [URL], isVFX: Bool) {
    guard watchFolderSettings.autoImportEnabled else {
        NSLog("⚠️ Auto-import disabled")
        return
    }

    Task {
        let result = await autoImportService?.processDetectedFiles(
            files,
            isVFX: isVFX,
            existingSegments: segments,
            offlineFiles: offlineMediaFiles,
            offlineMetadata: offlineFileMetadata,
            trackedSizes: segmentFileSizes
        )

        await MainActor.run {
            applyDetectionResult(result)
        }
    }
}

private func applyDetectionResult(_ result: DetectionResult?) {
    guard let result = result else { return }

    // Add new files
    addSegments(result.newFiles)

    // Handle returning files
    for (fileName, action) in result.returningFiles {
        offlineMediaFiles.remove(fileName)
        offlineFileMetadata.removeValue(forKey: fileName)
    }

    // Handle modifications
    for (fileName, modification) in result.modifiedFiles {
        segmentModificationDates[fileName] = Date()
        segmentFileSizes[fileName] = modification.newSize

        if modification.action == .markModifiedAndOnline {
            offlineMediaFiles.remove(fileName)
            offlineFileMetadata.removeValue(forKey: fileName)
        }

        // Update print status for affected OCFs
        updatePrintStatusForSegment(fileName)
    }
}
```

#### Step 4B.3: Refactor Deletion Handler (2 hours)

**Before (Project.swift:764-827):**
```swift
private func handleDeletedVideoFiles(_ fileNames: [String], isVFX: Bool) {
    // 63 lines of offline tracking logic
}
```

**After:**
```swift
func watchFolder(_ service: WatchFolderService, didDetectDeletedFiles fileNames: [String], isVFX: Bool) {
    let result = autoImportService?.processDeletedFiles(fileNames, existingSegments: segments)

    guard let result = result else { return }

    for fileName in result.offlineFiles {
        offlineMediaFiles.insert(fileName)
        if let metadata = result.offlineMetadata[fileName] {
            offlineFileMetadata[fileName] = metadata
        }
    }

    updateModified()
}
```

#### Step 4B.4: Refactor Modification Handler (2 hours)

**Before (Project.swift:829-882):**
```swift
private func handleModifiedVideoFiles(_ fileNames: [String], isVFX: Bool) {
    // 53 lines of modification tracking
}
```

**After:**
```swift
func watchFolder(_ service: WatchFolderService, didDetectModifiedFiles fileNames: [String], isVFX: Bool) {
    let result = autoImportService?.processModifiedFiles(fileNames, existingSegments: segments)

    guard let result = result else { return }

    for (fileName, modification) in result.modifications {
        segmentModificationDates[fileName] = Date()
        segmentFileSizes[fileName] = modification.newSize
        updatePrintStatusForSegment(fileName)
    }

    updateModified()
}
```

### Testing

**Unit Tests:** `AutoImportServiceTests.swift`

```swift
func testProcessDetectedFiles_NewFiles() async {
    let service = AutoImportService()
    let testFiles = [createTestVideoFile()]

    let result = await service.processDetectedFiles(
        testFiles,
        isVFX: false,
        existingSegments: [],
        offlineFiles: [],
        offlineMetadata: [:],
        trackedSizes: [:]
    )

    XCTAssertEqual(result.newFiles.count, 1)
    XCTAssertTrue(result.returningFiles.isEmpty)
}

func testProcessDetectedFiles_ReturningUnchanged() async {
    // Test offline file returning with same size
}

func testProcessDetectedFiles_ReturningChanged() async {
    // Test offline file returning with different size
}
```

### Success Criteria

- ✅ AutoImportService created and tested
- ✅ All watch folder handlers simplified
- ✅ File classification logic in Core
- ✅ App functionality unchanged
- ✅ ~350 lines removed from Project.swift

**Estimated Lines Removed:** 350 lines
**Project.swift Target:** ~649 lines

---

## Phase 4C: Project Management Operations

**Duration:** 5-7 days
**Risk:** Medium
**Priority:** High

### Objectives

Extract project management operations into a dedicated workflow service:
- Add/remove OCF files and segments
- Update linking results
- Refresh print status
- Toggle VFX flags
- Manage blank rush status

### Files to Create

#### File 1: `ProjectOperations.swift` (SourcePrintCore)

**Purpose:** All project data manipulation operations

**Location:** `/Users/mac10/Projects/SourcePrint/SourcePrintCore/Sources/SourcePrintCore/Workflows/ProjectOperations.swift`

```swift
import Foundation

/// Service for project data operations
public class ProjectOperations {

    // MARK: - Media Management

    /// Add OCF files to project
    public static func addOCFFiles(
        _ files: [MediaFileInfo],
        to existingOCFs: inout [MediaFileInfo]
    ) {
        existingOCFs.append(contentsOf: files)
        NSLog("✅ Added %d OCF file(s)", files.count)
    }

    /// Add segments to project with modification tracking
    public static func addSegments(
        _ newSegments: [MediaFileInfo],
        to existingSegments: inout [MediaFileInfo],
        modificationDates: inout [String: Date],
        fileSizes: inout [String: Int64]
    ) {
        existingSegments.append(contentsOf: newSegments)

        // Track initial state
        let now = Date()
        for segment in newSegments {
            modificationDates[segment.fileName] = now

            if case .success(let size) = FileSystemOperations.getFileSize(for: segment.url) {
                fileSizes[segment.fileName] = size
            }
        }

        NSLog("✅ Added %d segment(s)", newSegments.count)
    }

    /// Remove OCF files and clean up associated data
    public static func removeOCFFiles(
        _ fileNames: [String],
        from ocfFiles: inout [MediaFileInfo],
        linkingResult: inout LinkingResult?,
        blankRushStatus: inout [String: BlankRushStatus],
        printStatus: inout [String: PrintStatus]
    ) {
        ocfFiles.removeAll { fileNames.contains($0.fileName) }

        // Clear linking data for removed OCFs
        if var result = linkingResult {
            result.ocfParents.removeAll { fileNames.contains($0.ocf.fileName) }
            linkingResult = result
        }

        // Clear status data
        for fileName in fileNames {
            blankRushStatus.removeValue(forKey: fileName)
            printStatus.removeValue(forKey: fileName)
        }

        NSLog("🗑️ Removed %d OCF file(s)", fileNames.count)
    }

    /// Remove segments and clean up associated data
    public static func removeSegments(
        _ fileNames: [String],
        from segments: inout [MediaFileInfo],
        linkingResult: inout LinkingResult?,
        modificationDates: inout [String: Date],
        fileSizes: inout [String: Int64],
        offlineFiles: inout Set<String>,
        offlineMetadata: inout [String: OfflineFileMetadata]
    ) {
        segments.removeAll { fileNames.contains($0.fileName) }

        // Clear linking data
        if var result = linkingResult {
            for i in 0..<result.ocfParents.count {
                result.ocfParents[i].children.removeAll { fileNames.contains($0.segment.fileName) }
            }
            linkingResult = result
        }

        // Clear tracking data
        for fileName in fileNames {
            modificationDates.removeValue(forKey: fileName)
            fileSizes.removeValue(forKey: fileName)
            offlineFiles.remove(fileName)
            offlineMetadata.removeValue(forKey: fileName)
        }

        NSLog("🗑️ Removed %d segment(s)", fileNames.count)
    }

    // MARK: - Status Management

    /// Refresh segment modification dates from file system
    public static func refreshSegmentModificationDates(
        segments: [MediaFileInfo],
        modificationDates: inout [String: Date]
    ) {
        for segment in segments {
            if case .success(let date) = FileSystemOperations.getModificationDate(for: segment.url) {
                modificationDates[segment.fileName] = date
            }
        }
        NSLog("🔄 Refreshed modification dates for %d segments", segments.count)
    }

    /// Check for modified segments and update print status
    public static func checkForModifiedSegments(
        linkingResult: LinkingResult,
        modificationDates: [String: Date],
        printStatus: inout [String: PrintStatus]
    ) -> Set<String> {
        var affectedOCFs = Set<String>()

        for parent in linkingResult.parentsWithChildren {
            var hasModifiedChild = false

            for child in parent.children {
                let fileName = child.segment.fileName

                if case .success(let fileModDate) = FileSystemOperations.getModificationDate(for: child.segment.url),
                   let trackedDate = modificationDates[fileName],
                   fileModDate > trackedDate {
                    hasModifiedChild = true
                    break
                }
            }

            if hasModifiedChild {
                affectedOCFs.insert(parent.ocf.fileName)

                // Update print status to needsReprint
                if case .printed = printStatus[parent.ocf.fileName] {
                    printStatus[parent.ocf.fileName] = .needsReprint
                    NSLog("⚠️ OCF needs re-print due to modified segment: %@", parent.ocf.fileName)
                }
            }
        }

        return affectedOCFs
    }

    /// Refresh print status based on current state
    public static func refreshPrintStatus(
        linkingResult: LinkingResult?,
        printStatus: inout [String: PrintStatus]
    ) {
        guard let result = linkingResult else { return }

        for parent in result.parentsWithChildren {
            // If not in status map, set to notPrinted
            if printStatus[parent.ocf.fileName] == nil {
                printStatus[parent.ocf.fileName] = .notPrinted
            }
        }

        NSLog("🔄 Refreshed print status")
    }

    // MARK: - VFX Management

    /// Toggle VFX status for OCF
    public static func toggleOCFVFXStatus(
        _ fileName: String,
        isVFX: Bool,
        in ocfFiles: inout [MediaFileInfo]
    ) {
        if let index = ocfFiles.firstIndex(where: { $0.fileName == fileName }) {
            ocfFiles[index].isVFXShot = isVFX
            NSLog("🎬 Toggled OCF VFX status: %@ -> %@", fileName, isVFX ? "VFX" : "Grade")
        }
    }

    /// Toggle VFX status for segment
    public static func toggleSegmentVFXStatus(
        _ fileName: String,
        isVFX: Bool,
        in segments: inout [MediaFileInfo]
    ) {
        if let index = segments.firstIndex(where: { $0.fileName == fileName }) {
            segments[index].isVFXShot = isVFX
            NSLog("🎬 Toggled segment VFX status: %@ -> %@", fileName, isVFX ? "VFX" : "Grade")
        }
    }
}
```

### Implementation Steps

#### Step 4C.1: Create ProjectOperations Service (4-6 hours)

1. Create the service file
2. Write comprehensive tests
3. Verify compilation

#### Step 4C.2: Update Project.swift (8-10 hours)

Replace all project management methods with calls to ProjectOperations:

**Before:**
```swift
func addOCFFiles(_ files: [MediaFileInfo]) {
    ocfFiles.append(contentsOf: files)
    updateModified()
}
```

**After:**
```swift
func addOCFFiles(_ files: [MediaFileInfo]) {
    ProjectOperations.addOCFFiles(files, to: &ocfFiles)
    updateModified()
}
```

Apply this pattern to all methods in lines 221-422.

### Testing

**Unit Tests:** `ProjectOperationsTests.swift`

```swift
func testAddOCFFiles() {
    var ocfs: [MediaFileInfo] = []
    let newOCFs = [createTestOCF()]

    ProjectOperations.addOCFFiles(newOCFs, to: &ocfs)

    XCTAssertEqual(ocfs.count, 1)
}

func testRemoveOCFFiles_CleansUpStatuses() {
    var ocfs = [createTestOCF(fileName: "OCF001.mov")]
    var blankRushStatus: [String: BlankRushStatus] = ["OCF001.mov": .completed(date: Date(), url: URL(fileURLWithPath: "/"))]
    var printStatus: [String: PrintStatus] = ["OCF001.mov": .printed(date: Date(), outputURL: URL(fileURLWithPath: "/"))]
    var linkingResult: LinkingResult? = nil

    ProjectOperations.removeOCFFiles(
        ["OCF001.mov"],
        from: &ocfs,
        linkingResult: &linkingResult,
        blankRushStatus: &blankRushStatus,
        printStatus: &printStatus
    )

    XCTAssertTrue(ocfs.isEmpty)
    XCTAssertTrue(blankRushStatus.isEmpty)
    XCTAssertTrue(printStatus.isEmpty)
}
```

### Success Criteria

- ✅ ProjectOperations service created and tested
- ✅ All project management methods delegated to Core
- ✅ App functionality unchanged
- ✅ ~150-200 lines removed from Project.swift

**Estimated Lines Removed:** 150-200 lines
**Project.swift Target:** ~450-500 lines

---

## Phase 4D: Model/ViewModel Split

**Duration:** 2-3 weeks
**Risk:** High
**Priority:** Critical (final phase)

### Objectives

**The Big Refactor:** Split Project.swift into proper architecture:
1. **ProjectModel.swift** - Pure Codable data model (no SwiftUI, no business logic)
2. **ProjectViewModel.swift** - SwiftUI reactive wrapper (@ObservableObject)
3. **ProjectWorkflow.swift** - High-level workflow coordination (Core)

### Architecture Vision

```
SourcePrintCore:
├── ProjectModel (pure data, Codable)
├── ProjectWorkflow (import/link/render coordination)
├── ProjectOperations (already exists from 4C)
├── AutoImportService (already exists from 4B)
├── RenderQueueManager (already exists from Phase 3)
└── All other services

UI Layer:
└── ProjectViewModel (@ObservableObject)
    ├── Wraps ProjectModel
    ├── Provides @Published properties for SwiftUI
    ├── Delegates all operations to Core services
    └── Thin reactive layer only
```

### Benefits

✅ **Project model becomes testable** - No SwiftUI dependencies
✅ **CLI can use ProjectModel directly** - Load/save projects without UI
✅ **Clean separation** - Data, business logic, and presentation layers distinct
✅ **Easier maintenance** - Changes to data model don't affect UI
✅ **Better testing** - Can test workflows without SwiftUI environment

### Implementation Overview

This is a large refactor that deserves its own detailed sub-plan. When we reach this phase, we'll break it down into:

- **4D.1:** Extract ProjectModel (pure data)
- **4D.2:** Create ProjectViewModel (SwiftUI wrapper)
- **4D.3:** Create ProjectWorkflow (Core coordination)
- **4D.4:** Update all UI views to use ViewModel
- **4D.5:** Integration testing and validation

**This phase will have its own detailed plan document when we reach it.**

---

## Testing Strategy

### Unit Testing

Each phase includes comprehensive unit tests:
- **Phase 4A:** BlankRushScanner tests
- **Phase 4B:** AutoImportService tests (classification, detection, etc.)
- **Phase 4C:** ProjectOperations tests (all CRUD operations)
- **Phase 4D:** ProjectModel/ViewModel tests

### Integration Testing

After each phase:
1. Build and run the app
2. Test affected workflows end-to-end
3. Verify no regressions in functionality
4. Check performance hasn't degraded

### Manual Testing Checklist

- [ ] Import media files
- [ ] Watch folder auto-import
- [ ] Perform linking
- [ ] Create blank rushes
- [ ] Render OCFs (batch and single)
- [ ] Offline file handling
- [ ] File modification detection
- [ ] Project save/load

---

## Risk Mitigation

### Strategy

1. **Small Commits:** Commit after each successful step
2. **Feature Flags:** Use flags for gradual rollout if needed
3. **Parallel Implementation:** Keep old code until new code validated
4. **Rollback Plan:** Git tags at each phase for easy rollback
5. **Code Review:** Review each phase before proceeding

### Known Risks

| Phase | Risk | Mitigation |
|-------|------|------------|
| 4A | Low - Simple utility extraction | Comprehensive tests |
| 4B | Medium - Complex classification logic | Extensive unit tests, manual testing |
| 4C | Medium - Many interdependencies | Careful dependency tracking |
| 4D | High - Major architectural change | Detailed sub-plan, incremental migration |

---

## Success Metrics

### Phase Completion

- **Phase 4A:** ~50 lines removed, file system operations in Core
- **Phase 4B:** ~350 lines removed, watch folder integration in Core
- **Phase 4C:** ~150-200 lines removed, project operations in Core
- **Phase 4D:** ~200-300 lines remaining (thin ViewModel)

### Final State

**Project.swift (current):** 1,049 lines
**After Phase 4:** ~200-300 lines (ProjectViewModel only)

**Lines Moved to Core:** ~750-850 lines
**Architecture:** Clean separation achieved ✅

---

## Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| 4A: File System | 1-2 days | 1-2 days |
| 4B: Watch Folder | 3-5 days | 4-7 days |
| 4C: Operations | 5-7 days | 9-14 days |
| 4D: Model/ViewModel | 2-3 weeks | 23-35 days |

**Total Estimated Duration:** 23-35 days (4-7 weeks)

---

## Next Steps

1. **Review this plan** - Get approval on the incremental approach
2. **Start Phase 4A** - Begin with low-risk file system extraction
3. **Document progress** - Update phase completion docs as we go
4. **Celebrate wins** - Each phase is a significant architectural improvement!

---

**Ready to begin Phase 4A? 🚀**
