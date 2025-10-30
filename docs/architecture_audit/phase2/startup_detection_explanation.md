# How Startup Detection Works

**Last Updated:** 2025-10-30
**Status:** Production - Fully Working ✅

---

## Overview

When SourcePrint closes and reopens, the watch folder system detects all changes that occurred while the app was closed:
- **Modified files** (size changes)
- **Deleted files** (marked offline)
- **New files** (auto-imported)

This document explains exactly how this works.

---

## The Two-Phase Detection System

### Phase 1: Check Known Segments (Synchronous)
**Purpose:** Detect changes to files that were already imported

### Phase 2: Scan for New Files (Asynchronous)
**Purpose:** Discover and import files added while app was closed

---

## Complete Execution Flow

### 1. App Startup Trigger

**Location:** `Project.swift:startWatchFolderIfNeeded()`

```swift
func startWatchFolderIfNeeded() {
    // Create watch folder service
    watchFolderService = WatchFolderService(gradePath: gradePath, vfxPath: vfxPath)
    watchFolderService?.delegate = self

    // Start detection (does NOT start monitoring yet!)
    checkForChangedFilesOnStartup(gradePath: gradePath, vfxPath: vfxPath)
}
```

**Key Point:** File monitor is NOT started here. Detection happens first.

---

### 2. Phase 1: Check Known Segments

**Location:** `Project.swift:checkForChangedFilesOnStartup()` → `WatchFolderService.detectChangesOnStartup()`

**What It Does:**
Iterates through all segments that were previously imported and checks if they changed:

```swift
public func detectChangesOnStartup(
    knownSegments: [MediaFileInfo],
    trackedSizes: [String: Int64]
) -> FileChangeSet {

    for segment in knownSegments {
        let fileURL = segment.url

        // Is this segment in a watch folder?
        guard isFileInWatchFolder(fileURL) else { continue }

        if FileSystemOperations.fileExists(at: fileURL) {
            // File exists - check if size changed
            if let storedSize = trackedSizes[fileName] {
                let currentSize = getFileSize(for: fileURL)
                if currentSize != storedSize {
                    modifiedFiles.append(fileName)
                    sizeChanges[fileName] = (old: storedSize, new: currentSize)
                }
            }
        } else {
            // File was deleted
            deletedFiles.append(fileName)
        }
    }

    return FileChangeSet(
        modifiedFiles: modifiedFiles,
        deletedFiles: deletedFiles,
        sizeChanges: sizeChanges
    )
}
```

**Output:**
- List of modified files (with old/new sizes)
- List of deleted files
- Returns immediately (synchronous)

**Back in Project.swift:**
```swift
let changes = service.detectChangesOnStartup(knownSegments: segments, trackedSizes: segmentFileSizes)

// Handle modifications
for fileName in changes.modifiedFiles {
    segmentModificationDates[fileName] = Date()
    segmentFileSizes[fileName] = newSize
    // Mark OCFs for re-print
}

// Handle deletions
for fileName in changes.deletedFiles {
    offlineMediaFiles.insert(fileName)
    // Store metadata for when file returns
}
```

**Result:** Known files are updated, but we haven't found NEW files yet.

---

### 3. Phase 2: Scan for New Files

**Location:** `WatchFolderService.scanForNewFiles()`

**What It Does:**
Scans the actual watch folder directories and compares against known segments:

```swift
public func scanForNewFiles(
    knownSegments: [MediaFileInfo]
) async -> (gradeFiles: [URL], vfxFiles: [URL]) {

    let knownFileNames = Set(knownSegments.map { $0.fileName })
    var gradeFiles: [URL] = []
    var vfxFiles: [URL] = []

    // Scan grade folder
    if let gradePath = gradePath {
        let gradeURL = URL(fileURLWithPath: gradePath)
        let allFiles = try await VideoFileDiscovery.discoverVideoFiles(in: gradeURL)

        for file in allFiles {
            if !knownFileNames.contains(file.lastPathComponent) {
                gradeFiles.append(file)  // NEW file!
            }
        }
    }

    // Same for VFX folder...

    return (gradeFiles, vfxFiles)
}
```

**How It Works:**

1. **Build Known Set:** Creates a Set of all imported file names (fast lookup)
2. **Scan Grade Folder:** Uses `VideoFileDiscovery` (from Phase 1) to find all video files
3. **Filter New Files:** Any file NOT in the known set is new
4. **Scan VFX Folder:** Same process for VFX
5. **Return Lists:** Separate lists for grade and VFX files

**Why This Works:**
- `VideoFileDiscovery` recursively scans directories
- Filters by video extensions (.mov, .mp4, .mxf, etc.)
- Skips hidden files (. prefix)
- Fast Set lookup (O(1) per file)

---

### 4. Import New Files (Critical: Proper Await)

**Location:** `Project.swift:checkForChangedFilesOnStartup()`

```swift
Task {
    let newFiles = await service.scanForNewFiles(knownSegments: segments)

    // Import grade files - WAIT for completion
    if !newFiles.gradeFiles.isEmpty && watchFolderSettings.autoImportEnabled {
        let gradeMediaFiles = await analyzeDetectedFiles(urls: newFiles.gradeFiles, isVFX: false)
        await MainActor.run {
            addSegments(gradeMediaFiles)
            NSLog("✅ Startup import complete: %d grade files", gradeMediaFiles.count)
        }
    }

    // Import VFX files - WAIT for completion
    if !newFiles.vfxFiles.isEmpty && watchFolderSettings.autoImportEnabled {
        let vfxMediaFiles = await analyzeDetectedFiles(urls: newFiles.vfxFiles, isVFX: true)
        await MainActor.run {
            addSegments(vfxMediaFiles)
            NSLog("✅ Startup import complete: %d VFX files", vfxMediaFiles.count)
        }
    }

    // CRITICAL: Only start monitoring AFTER imports finish
    await MainActor.run {
        service.startMonitoring()
        NSLog("✅ Watch folder monitoring active")
    }
}
```

**Key Points:**

1. **`await analyzeDetectedFiles()`** - Waits for video analysis to complete
2. **`await MainActor.run { addSegments() }`** - Waits for segments to be added to array
3. **THEN `startMonitoring()`** - Only starts file monitor after everything finishes

**Why This Prevents Duplicates:**

```
❌ WRONG (causes duplicates):
handleDetectedVideoFiles(files)  // Spawns Task, returns immediately
startMonitoring()                 // Monitor starts NOW
                                 // Task still running, adds files
                                 // Monitor detects same files → DUPLICATES!

✅ CORRECT (no duplicates):
await analyzeDetectedFiles()      // WAIT for analysis
await addSegments()               // WAIT for import
startMonitoring()                 // NOW start monitor (files already imported)
```

---

### 5. Real-Time Monitoring Begins

**Location:** `WatchFolderService.startMonitoring()`

```swift
public func startMonitoring() {
    fileMonitor = FileMonitorWatchFolder()

    // Set up callbacks
    fileMonitor?.onVideoFilesDetected = { [weak self] videoFiles, isVFX in
        self.delegate?.watchFolder(self, didDetectNewFiles: videoFiles, isVFX: isVFX)
    }

    fileMonitor?.onVideoFilesDeleted = { [weak self] fileNames, isVFX in
        self.delegate?.watchFolder(self, didDetectDeletedFiles: fileNames, isVFX: isVFX)
    }

    fileMonitor?.startWatching(gradePath: gradePath, vfxPath: vfxPath)
}
```

**What Happens:**
- FSEvents monitoring starts
- FileMonitor watches both Grade and VFX folders
- Callbacks fire when files are added/deleted/modified
- Delegate pattern routes events back to Project.swift

**Critical:** FSEvents only reports changes that occur AFTER monitoring starts. Since we imported all existing files first, there's no overlap.

---

## Timeline Diagram

Here's exactly what happens from app launch to monitoring:

```
Time    Event                           State
────────────────────────────────────────────────────────────────
T+0s    App launches                    Loading...
T+1s    startWatchFolderIfNeeded()      Service created
T+1s    Phase 1: detectChangesOnStartup() Checking known files...
T+1.1s  → Found 2 modified files        Updating metadata
T+1.1s  → Found 1 deleted file          Marking offline
T+1.2s  Phase 2: scanForNewFiles()      Scanning directories...
T+2s    → Found 5 new files in Grade    Analyzing...
T+2s    → Analyzing file 1/5            FFmpeg analysis
T+3s    → Analyzing file 2/5            FFmpeg analysis
T+4s    → Analyzing file 3/5            FFmpeg analysis
T+5s    → Analyzing file 4/5            FFmpeg analysis
T+6s    → Analyzing file 5/5            FFmpeg analysis
T+6.5s  → addSegments() called          Adding to array
T+6.5s  startMonitoring()               ✅ Monitor active
T+7s+   Real-time monitoring            Watching for changes...
```

**Key Observation:** Monitor doesn't start until T+6.5s, after all imports finish.

---

## Architecture Benefits

### 1. Clean Separation
- **Core Library:** `scanForNewFiles()` in SourcePrintCore (testable)
- **UI Layer:** State management in Project.swift (reactive)

### 2. Reusability
```swift
// CLI tool could use the same logic:
let service = WatchFolderService(gradePath: "/path", vfxPath: nil)
let newFiles = await service.scanForNewFiles(knownSegments: existingFiles)
// Import files...
```

### 3. No Race Conditions
- Synchronous Phase 1 completes immediately
- Asynchronous Phase 2 fully awaits before monitoring
- Clear separation between startup detection and real-time monitoring

### 4. Leverages Phase 1 Work
- Uses `VideoFileDiscovery` from Phase 1
- Uses `FileSystemOperations` for size checks
- Consistent file discovery across features

---

## Edge Cases Handled

### Case 1: File Deleted and Replaced
```
1. User imports file "clip.mov" (size: 1GB)
2. App closes
3. User deletes "clip.mov"
4. User copies NEW "clip.mov" (size: 1.5GB, different content)
5. App opens

Result:
- Phase 1: Detects size change (1GB → 1.5GB)
- Marks file as modified
- Updates segmentFileSizes
- Marks OCFs for re-print
```

### Case 2: Multiple New Files, Some Already Importing
```
1. User imports files A, B, C
2. App closes
3. User adds files D, E, F
4. App opens

Result:
- Phase 1: Checks A, B, C (no changes)
- Phase 2: Scans directory, finds A, B, C, D, E, F
- Filter: D, E, F not in known set → import only D, E, F
- No duplicates of A, B, C
```

### Case 3: File Deleted While Analyzing
```
1. App closed
2. User adds files A, B, C
3. App opens, starts scanning
4. Scan finds A, B, C
5. User deletes B while analysis running
6. Analysis tries to analyze B

Result:
- analyzeDetectedFiles() has try/catch
- B analysis fails (file not found)
- A and C import successfully
- Logs: "❌ Failed to analyze watch folder file B: File not found"
- Monitor starts, detects B is gone → marks offline
```

### Case 4: No Changes
```
1. App closes
2. User changes nothing
3. App opens

Result:
- Phase 1: Checks all files, no changes
- Phase 2: Scans folders, all files already known
- Log: "✅ No new files found in watch folders"
- Monitor starts immediately (no import delay)
```

---

## Comparison: Old vs New

### Before Phase 2 Startup Detection

```
App Startup:
├── startMonitoring() immediately
├── FSEvents starts watching
└── NEW files added while closed: ❌ NEVER DETECTED

User Experience:
- Close app
- Add new files to watch folder
- Reopen app
- Files NOT detected
- User must manually import or toggle monitoring off/on
```

### After Phase 2 Startup Detection

```
App Startup:
├── Phase 1: Check known files
│   ├── Detect modifications
│   └── Detect deletions
├── Phase 2: Scan for new files
│   ├── Find all new files
│   ├── Analyze & import
│   └── Wait for completion
└── startMonitoring()

User Experience:
- Close app
- Add new files to watch folder
- Reopen app
- ✅ Files automatically detected and imported
- Seamless workflow
```

---

## Code Locations Quick Reference

| Feature | File | Method | Lines |
|---------|------|--------|-------|
| Startup Trigger | Project.swift | `startWatchFolderIfNeeded()` | 512-535 |
| Phase 1: Known Files | WatchFolderService.swift | `detectChangesOnStartup()` | 103-155 |
| Phase 2: New Files | WatchFolderService.swift | `scanForNewFiles()` | 162-213 |
| Import & Start Monitor | Project.swift | `checkForChangedFilesOnStartup()` | 537-628 |
| File Analysis | Project.swift | `analyzeDetectedFiles()` | 721-755 |
| Delegate Pattern | WatchFolderService.swift | `WatchFolderDelegate` | 6-11 |

---

## What Makes This Work

### 1. Sequential Execution
```swift
Task {                                    // Async context
    await scanForNewFiles()               // Step 1
    await analyzeDetectedFiles()          // Step 2
    await MainActor.run { addSegments() } // Step 3
    await MainActor.run { startMonitoring() } // Step 4
}
```
Each `await` ensures previous step completes before next one starts.

### 2. MainActor Threading
```swift
await MainActor.run {
    addSegments(mediaFiles)  // Must run on main thread (updates @Published)
}
```
Ensures UI updates happen safely on main thread.

### 3. Set-Based Filtering
```swift
let knownFileNames = Set(segments.map { $0.fileName })  // O(n) build
for file in allFiles {
    if !knownFileNames.contains(file.lastPathComponent) {  // O(1) lookup
        newFiles.append(file)
    }
}
```
Fast filtering even with thousands of files.

### 4. Delegate Pattern Decoupling
```swift
// Core library doesn't know about Project.swift
public protocol WatchFolderDelegate: AnyObject {
    func watchFolder(_ service: WatchFolderService, didDetectNewFiles files: [URL], isVFX: Bool)
}

// Project.swift implements delegate
extension Project: WatchFolderDelegate {
    func watchFolder(_ service: WatchFolderService, didDetectNewFiles files: [URL], isVFX: Bool) {
        handleDetectedVideoFiles(files, isVFX: isVFX)
    }
}
```
Clean separation, testable independently.

---

## Summary

**The Magic:**
1. App startup runs TWO detection phases BEFORE monitoring starts
2. Phase 1 checks known files (fast, synchronous)
3. Phase 2 scans directories for new files (thorough, asynchronous)
4. Properly awaits import completion to prevent race conditions
5. Only starts real-time monitoring after everything is imported

**Result:** Seamless watch folder experience - files added while app is closed are automatically detected and imported on startup! 🎉
