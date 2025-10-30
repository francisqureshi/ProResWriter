# Phase 2 Bug: Duplicate File Imports - RESOLVED ✅

**Date:** 2025-10-30
**Status:** ✅ **RESOLVED**
**Severity:** High - Breaks user experience (WAS critical, now fixed)

---

## Problem Description

After implementing the startup scan fix, files are being imported **twice**, resulting in duplicate entries in the segments view.

### Root Cause

The issue occurs because:

1. **Startup scan** runs and calls `handleDetectedVideoFiles()` for new files
2. **File monitor starts** and also detects the same files in the watch folder
3. Files get imported twice

### Timeline of Events

```
App Startup:
├── startWatchFolderIfNeeded() called
│   ├── checkForChangedFilesOnStartup()
│   │   ├── detectChangesOnStartup() - checks known files
│   │   └── scanForNewFiles() - finds NEW files
│   │       └── handleDetectedVideoFiles() - IMPORTS files (1st time)
│   └── watchFolderService.startMonitoring()
│       └── FileMonitor detects existing files in folder
│           └── onVideoFilesDetected callback fires
│               └── handleDetectedVideoFiles() - IMPORTS files (2nd time) ❌
```

---

## Solution

The startup scan should NOT call `handleDetectedVideoFiles()` directly. Instead, it should just log what it found, and let the file monitor detect them when it starts.

**Why this works:**
- FileMonitorWatchFolder already scans the directory when `startWatching()` is called
- It will detect all existing files and fire callbacks
- We don't need to manually import files from startup scan
- Files are only imported once via the normal monitoring flow

---

## Fix Implementation

Remove the auto-import logic from startup scan in `checkForChangedFilesOnStartup()`.

The startup scan should ONLY:
1. Log that files were found
2. Let the file monitor handle importing when it starts

**Before:**
```swift
// 2. Scan for NEW files added while app was closed
Task {
    let newFiles = await service.scanForNewFiles(knownSegments: segments)

    // Auto-import new grade files
    if !newFiles.gradeFiles.isEmpty && watchFolderSettings.autoImportEnabled {
        await MainActor.run {
            handleDetectedVideoFiles(newFiles.gradeFiles, isVFX: false)
        }
    }

    // Auto-import new VFX files
    if !newFiles.vfxFiles.isEmpty && watchFolderSettings.autoImportEnabled {
        await MainActor.run {
            handleDetectedVideoFiles(newFiles.vfxFiles, isVFX: true)
        }
    }
}
```

**After:**
```swift
// 2. Scan for NEW files added while app was closed
// Note: FileMonitor will detect these files when startMonitoring() is called
// We just log them here for visibility
Task {
    let newFiles = await service.scanForNewFiles(knownSegments: segments)

    // Just log - don't import (monitor will handle it)
    if !newFiles.gradeFiles.isEmpty {
        NSLog("📋 Found %d new grade file(s) - will be imported by file monitor", newFiles.gradeFiles.count)
    }
    if !newFiles.vfxFiles.isEmpty {
        NSLog("📋 Found %d new VFX file(s) - will be imported by file monitor", newFiles.vfxFiles.count)
    }
}
```

---

## Status

- [x] Bug identified
- [x] Fix implemented
- [x] Build succeeds
- [ ] User testing confirms no duplicates

---

## Fix Applied

Modified the startup flow in `Project.swift`:

**Key Changes:**

1. **Removed premature `startMonitoring()` call** (line 531)
   - Was starting monitor immediately after service creation
   - Now waits for startup scan to complete

2. **Added deferred monitoring start** (lines 617-620)
   - File monitor now starts ONLY after startup scan completes
   - Wrapped in `MainActor.run` for thread safety
   - Added log message "✅ Watch folder monitoring active"

**Execution Flow (Fixed):**

```
App Startup:
├── startWatchFolderIfNeeded() called
│   ├── Create WatchFolderService
│   ├── Set delegate
│   ├── checkForChangedFilesOnStartup()
│   │   ├── detectChangesOnStartup() - checks known files (sync)
│   │   └── Task {
│   │       ├── scanForNewFiles() - finds NEW files (async)
│   │       ├── handleDetectedVideoFiles() - imports grade files
│   │       ├── handleDetectedVideoFiles() - imports VFX files
│   │       └── startMonitoring() - NOW start file monitor ✅
│   │   }
```

**Why This Works:**

- Startup scan completes and imports all existing files FIRST
- File monitor starts AFTER import finishes
- FSEvents only reports changes that occur AFTER monitoring starts
- No overlap = no duplicates

---

## Second Attempt - Race Condition Found

**Problem:** Duplicates still occurred after first fix!

**Root Cause:** The `handleDetectedVideoFiles()` function spawns a Task internally and returns immediately. So even though we moved `startMonitoring()` to after calling it, the actual import hadn't finished yet:

```swift
❌ First Fix (Still Broken):
handleDetectedVideoFiles(files, isVFX: false)  // Spawns Task, returns immediately
service.startMonitoring()                       // Starts before import finishes!
                                               // → Monitor detects files → DUPLICATES
```

**Real Fix (Second Attempt):**

Inline the import logic to properly await completion:

```swift
✅ Second Fix (Working):
let mediaFiles = await analyzeDetectedFiles(urls: files, isVFX: false)  // WAIT for analysis
await MainActor.run { addSegments(mediaFiles) }                         // WAIT for import
service.startMonitoring()                                               // NOW start monitor
```

**Changes Made (Lines 602-626):**

1. **Replaced `handleDetectedVideoFiles()` calls** with direct awaited calls
2. **Directly call `analyzeDetectedFiles()`** with await keyword
3. **Explicitly wait for `addSegments()`** to complete
4. **Only start monitor after ALL awaits complete**

This ensures the entire import pipeline finishes before the monitor starts, eliminating the race condition.

**User Symptom:**
- Files appeared twice in segments list
- When one was selected, the other also got selected (same import spawned twice)

**Fix Status:** ✅ Build succeeded, ready for testing

---

## Resolution Confirmed ✅

**Date:** 2025-10-30
**Tester:** User GUI testing
**Result:** ✅ **NO MORE DUPLICATES**

The race condition fix successfully eliminated duplicate imports:
- Startup scan properly awaits import completion
- File monitor only starts after imports finish
- No overlap between startup scan and real-time monitoring
- Files appear once in segments list
- Selection behavior is correct

**Testing Performed:**
- ✅ Close app, add files, reopen → files import once
- ✅ No duplicates in segments list
- ✅ Selection works correctly (no linked duplicates)

**Status:** Bug resolved, Phase 2 startup detection feature working correctly
