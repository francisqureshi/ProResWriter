# Phase 2 Bug Report: Startup Detection Missing New Files - RESOLVED ✅

**Date:** 2025-10-30
**Status:** ✅ **RESOLVED**
**Reporter:** User GUI testing
**Resolution Date:** 2025-10-30

---

## Problem Description

Watch folder functionality works correctly when SourcePrint is **open**, but fails to detect changes made while the app is **closed**.

### Affected Scenarios (All Fail)

1. **Delete files while closed, copy new ones in** - Not detected
2. **Copy files over existing ones** - Not detected
3. **Move new files into watch folder** - Not detected
4. **Delete files while closed** - May not be detected

### Expected Behavior

On app startup, the watch folder service should:
- Detect files deleted while app was closed
- Detect files modified while app was closed (size changes)
- **Detect NEW files added while app was closed**
- Import new files automatically (if auto-import enabled)

### Actual Behavior

On app startup, the watch folder service:
- ✅ Detects files deleted while app was closed (works)
- ✅ Detects files modified while app was closed (works)
- ❌ Does NOT detect new files added while app was closed (BROKEN)

---

## Root Cause Analysis

### Current Startup Detection Logic

Looking at `WatchFolderService.detectChangesOnStartup()`:

```swift
public func detectChangesOnStartup(
    knownSegments: [MediaFileInfo],
    trackedSizes: [String: Int64]
) -> FileChangeSet {
    // Only checks KNOWN segments
    for segment in knownSegments {
        // Check if file still exists
        // Check if size changed
    }

    // Returns modifications and deletions ONLY
    return FileChangeSet(
        modifiedFiles: modifiedFiles,
        deletedFiles: deletedFiles,
        sizeChanges: sizeChanges
    )
}
```

**Problem**: This method only iterates over `knownSegments` (files already imported). It never scans the watch folders themselves to discover new files.

### Why Real-Time Monitoring Works

When the app is **running**, `FileMonitorWatchFolder` actively watches the directories and fires callbacks:

```swift
fileMonitor?.onVideoFilesDetected = { [weak self] videoFiles, isVFX in
    // This callback fires when FSEvents detects new files
    self.delegate?.watchFolder(self, didDetectNewFiles: videoFiles, isVFX: isVFX)
}
```

**FSEvents only fires for changes that occur while monitoring is active.**

### Why Startup Detection Fails

At startup (before monitoring begins):
1. App calls `checkForChangedFilesOnStartup()` - only checks known files
2. App calls `startWatchFolderIfNeeded()` - starts FSEvents monitoring
3. FSEvents monitoring starts NOW - does not see historical changes
4. New files added while app was closed are never discovered

---

## Solution Design

### Add Startup Scan Method

Add a new method to `WatchFolderService`:

```swift
/// Scan watch folders for new files present at startup
/// Returns files that exist in watch folders but are not yet imported
public func scanForNewFiles(
    knownSegments: [MediaFileInfo]
) -> (gradeFiles: [URL], vfxFiles: [URL])
```

### Integration with Project.swift

Modify `checkForChangedFilesOnStartup()` to:

1. Call `detectChangesOnStartup()` (existing - checks known files)
2. Call `scanForNewFiles()` (NEW - discovers unknown files)
3. Process modifications/deletions from step 1
4. Auto-import new files from step 2 (if enabled)

---

## Implementation Plan

### Step 1: Add Scan Method to WatchFolderService

```swift
public func scanForNewFiles(knownSegments: [MediaFileInfo]) -> (gradeFiles: [URL], vfxFiles: [URL]) {
    let knownFileNames = Set(knownSegments.map { $0.fileName })
    var gradeFiles: [URL] = []
    var vfxFiles: [URL] = []

    // Scan grade folder
    if let gradePath = gradePath {
        let files = discoverVideoFilesSync(in: URL(fileURLWithPath: gradePath))
        for file in files {
            if !knownFileNames.contains(file.lastPathComponent) {
                gradeFiles.append(file)
            }
        }
    }

    // Scan VFX folder
    if let vfxPath = vfxPath {
        let files = discoverVideoFilesSync(in: URL(fileURLWithPath: vfxPath))
        for file in files {
            if !knownFileNames.contains(file.lastPathComponent) {
                vfxFiles.append(file)
            }
        }
    }

    return (gradeFiles, vfxFiles)
}
```

### Step 2: Update Project.swift Startup Logic

```swift
private func checkForChangedFilesOnStartup() {
    // 1. Check for modifications/deletions (existing)
    let changes = watchFolderService.detectChangesOnStartup(...)

    // 2. Scan for new files (NEW)
    let newFiles = watchFolderService.scanForNewFiles(knownSegments: segments)

    // 3. Process changes
    handleModifications(changes)

    // 4. Auto-import new files
    if !newFiles.gradeFiles.isEmpty {
        handleDetectedVideoFiles(newFiles.gradeFiles, isVFX: false)
    }
    if !newFiles.vfxFiles.isEmpty {
        handleDetectedVideoFiles(newFiles.vfxFiles, isVFX: true)
    }
}
```

---

## Testing Checklist

After fix, verify:

- [ ] Close app, add new file to Grade folder, reopen → file auto-imported
- [ ] Close app, add new file to VFX folder, reopen → file auto-imported
- [ ] Close app, delete file, add different file, reopen → deletion + new import
- [ ] Close app, replace file (copy over), reopen → modification detected + new import
- [ ] Close app, move files in, reopen → files auto-imported
- [ ] Real-time monitoring still works when app is open

---

## Risk Assessment

**Risk Level:** Low
- Adding new scan functionality, not modifying existing logic
- Uses existing `VideoFileDiscovery` utility from Phase 1
- Clear separation: startup scan vs real-time monitoring

---

## Status

- [x] Bug documented
- [x] Fix designed
- [x] Implementation complete
- [x] Build succeeds
- [x] User GUI testing confirms fix

---

## Resolution ✅

**Implementation Summary:**

Added `scanForNewFiles()` method to `WatchFolderService` that scans watch folders for files not yet imported:
- Uses `VideoFileDiscovery` from Phase 1
- Compares against known segment file names
- Returns separate lists for grade and VFX files

**Integration in Project.swift:**

Modified `checkForChangedFilesOnStartup()` to:
1. Check modifications/deletions (existing functionality)
2. Scan for new files (NEW)
3. Import found files with proper await
4. Start file monitor AFTER imports complete

**Critical Fix - Race Condition:**

Initial implementation had a race condition causing duplicate imports. Fixed by:
- Directly awaiting `analyzeDetectedFiles()` instead of calling `handleDetectedVideoFiles()`
- Explicitly waiting for `addSegments()` to complete
- Only starting file monitor after all imports finish

**Files Modified:**
- `SourcePrintCore/Sources/SourcePrintCore/Workflows/WatchFolderService.swift` - Added scanForNewFiles() method
- `macos/SourcePrint/Models/Project.swift` - Updated startup detection to scan and import new files

**Testing Results:**
- ✅ Close app, add files, reopen → files detected and imported
- ✅ No duplicate imports
- ✅ Real-time monitoring continues to work when app is open
- ✅ Deletion + new file scenarios work correctly
