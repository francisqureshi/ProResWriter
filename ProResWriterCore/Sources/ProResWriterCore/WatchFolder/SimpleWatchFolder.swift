//
//  SimpleWatchFolder.swift
//  ProResWriterCore
//
//  Created by Claude on 29/09/2025.
//  Watch folder service supporting multiple folders with different behaviors
//

import Foundation
import CoreServices

/// Watch folder service supporting multiple folders with different behaviors
public class SimpleWatchFolder {
    private var eventStream: FSEventStreamRef?
    private var isActive = false

    /// Callback for when video files are detected (URLs, isVFX)
    public var onVideoFilesDetected: (([URL], Bool) -> Void)?

    /// Callback for when video files are deleted (file names, isVFX)
    public var onVideoFilesDeleted: (([String], Bool) -> Void)?

    /// Callback for when video files are modified (file names, isVFX)
    public var onVideoFilesModified: (([String], Bool) -> Void)?

    /// Pending files waiting for copy completion (filePath -> (lastModified, isVFX))
    private var pendingFiles: [String: (Date, Bool)] = [:]
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 3.0 // Wait 3 seconds after last change

    /// Paths being monitored (path -> isVFX)
    private var monitoredPaths: [String: Bool] = [:]

    public init() {}

    /// Start monitoring multiple folders
    public func startWatching(gradePath: String?, vfxPath: String?) {
        NSLog("🔍 SimpleWatchFolder: Starting to watch folders...")

        guard !isActive else {
            NSLog("⚠️ Already watching - stop first")
            return
        }

        // Build paths array and track which paths are VFX
        var pathsToWatch: [String] = []
        monitoredPaths.removeAll()

        if let gradePath = gradePath {
            pathsToWatch.append(gradePath)
            monitoredPaths[gradePath] = false // Grade folder
            NSLog("📁 Monitoring grade folder: %@", gradePath)

            // Scan for existing files in grade folder
            scanExistingFiles(in: gradePath, isVFX: false)
        }

        if let vfxPath = vfxPath {
            pathsToWatch.append(vfxPath)
            monitoredPaths[vfxPath] = true // VFX folder
            NSLog("🎬 Monitoring VFX folder: %@", vfxPath)

            // Scan for existing files in VFX folder
            scanExistingFiles(in: vfxPath, isVFX: true)
        }

        guard !pathsToWatch.isEmpty else {
            NSLog("⚠️ No folders specified for monitoring")
            return
        }

        // Create array of paths to watch
        let pathsArray = pathsToWatch as CFArray

        // Create context to pass self to callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        var fsContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create FSEvent stream
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (stream, info, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = info else { return }
                let service = Unmanaged<SimpleWatchFolder>.fromOpaque(info).takeUnretainedValue()
                service.handleEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
            },
            &fsContext,
            pathsArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = eventStream else {
            NSLog("❌ Failed to create FSEventStream")
            return
        }

        // Schedule on dispatch queue
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

        // Start the stream
        if FSEventStreamStart(stream) {
            isActive = true
            NSLog("✅ SimpleWatchFolder: Successfully started monitoring %d folders", pathsToWatch.count)
        } else {
            NSLog("❌ Failed to start FSEventStream")
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    /// Stop monitoring
    public func stopWatching() {
        NSLog("🛑 SimpleWatchFolder: Stopping watch")

        guard let stream = eventStream, isActive else {
            NSLog("⚠️ Not currently watching")
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamRelease(stream)

        // Clean up debounce timer and pending files
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingFiles.removeAll()
        monitoredPaths.removeAll()

        eventStream = nil
        isActive = false
        NSLog("✅ SimpleWatchFolder: Stopped")
    }

    /// Scan for existing files in a folder on startup
    private func scanExistingFiles(in folderPath: String, isVFX: Bool) {
        NSLog("📂 Scanning existing files in %@ folder: %@", isVFX ? "VFX" : "grade", folderPath)

        let folderURL = URL(fileURLWithPath: folderPath)
        let videoExtensions = ["mov", "mp4", "m4v", "mxf", "prores"]

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: folderURL,
                                                                      includingPropertiesForKeys: [.isRegularFileKey],
                                                                      options: [.skipsHiddenFiles])

            var existingVideoFiles: [URL] = []

            for fileURL in fileURLs {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])

                if resourceValues.isRegularFile == true {
                    let fileExtension = fileURL.pathExtension.lowercased()

                    if videoExtensions.contains(fileExtension) {
                        NSLog("📄 Found existing %@ file: %@", isVFX ? "VFX" : "grade", fileURL.lastPathComponent)
                        existingVideoFiles.append(fileURL)
                    }
                }
            }

            if !existingVideoFiles.isEmpty {
                NSLog("🎬 Found %d existing %@ files to import", existingVideoFiles.count, isVFX ? "VFX" : "grade")

                // Import existing files immediately (they're already complete)
                onVideoFilesDetected?(existingVideoFiles, isVFX)
            } else {
                NSLog("📭 No existing video files found in %@ folder", isVFX ? "VFX" : "grade")
            }
        } catch {
            NSLog("❌ Error scanning folder %@: %@", folderPath, error.localizedDescription)
        }
    }

    /// Handle FSEvents callback
    private func handleEvents(numEvents: Int, eventPaths: UnsafeRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>) {
        NSLog("🚨 FSEvent triggered! %d events", numEvents)

        // Convert eventPaths to array of path strings using safer approach
        let pathsPointer = eventPaths.bindMemory(to: UnsafePointer<CChar>.self, capacity: numEvents)
        let pathsBuffer = UnsafeBufferPointer(start: pathsPointer, count: numEvents)

        for i in 0..<numEvents {
            // Safely get the path string
            guard i < pathsBuffer.count else {
                NSLog("⚠️ Index %d out of bounds", i)
                continue
            }

            let pathPtr = pathsBuffer[i]
            let pathAsString = String(cString: pathPtr)
            let flags = eventFlags[i]

            NSLog("📁 Event %d: %@", i, pathAsString)
            NSLog("   Flags: %d", flags)

            // Determine if this event is in a VFX folder
            let isVFXEvent = monitoredPaths.keys.first { vfxPath in
                pathAsString.hasPrefix(vfxPath) && monitoredPaths[vfxPath] == true
            } != nil

            // Check for different types of file events
            let isCreated = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
            let isModified = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0
            let isRemoved = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
            let isRenamed = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0
            let videoExtensions = ["mov", "mp4", "m4v", "mxf", "prores"]
            let pathExtension = URL(fileURLWithPath: pathAsString).pathExtension.lowercased()

            if videoExtensions.contains(pathExtension) {
                let fileName = URL(fileURLWithPath: pathAsString).lastPathComponent

                // Handle removed/deleted files
                if isRemoved && !FileManager.default.fileExists(atPath: pathAsString) {
                    NSLog("🗑️ %@ FILE DELETED: %@", isVFXEvent ? "VFX" : "GRADE", fileName)
                    onVideoFilesDeleted?([fileName], isVFXEvent)
                }

                // Handle renamed/moved files
                if isRenamed {
                    if FileManager.default.fileExists(atPath: pathAsString) {
                        // File exists at this path - this is a move-in (treat as creation)
                        NSLog("📥 %@ FILE MOVED IN: %@", isVFXEvent ? "VFX" : "GRADE", fileName)

                        // Add to pending files with current timestamp and VFX flag
                        pendingFiles[pathAsString] = (Date(), isVFXEvent)

                        // Reset debounce timer
                        debounceTimer?.invalidate()
                        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                            self?.processCompletedFiles()
                        }

                        NSLog("⏳ Moved-in file added to pending queue. Will process in %.1f seconds if no more changes...", debounceInterval)
                    } else {
                        // File doesn't exist at this path - this is a move-out (already handled by isRemoved)
                        NSLog("📤 %@ FILE MOVED OUT: %@", isVFXEvent ? "VFX" : "GRADE", fileName)
                    }
                }

                // Handle created files
                if isCreated && FileManager.default.fileExists(atPath: pathAsString) {
                    NSLog("🎬 %@ FILE CREATED: %@", isVFXEvent ? "VFX" : "GRADE", fileName)

                    // Add to pending files with current timestamp and VFX flag
                    pendingFiles[pathAsString] = (Date(), isVFXEvent)

                    // Reset debounce timer
                    debounceTimer?.invalidate()
                    debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                        self?.processCompletedFiles()
                    }

                    NSLog("⏳ File added to pending queue. Will process in %.1f seconds if no more changes...", debounceInterval)
                }

                // Handle modified files
                if isModified && !isCreated && !isRemoved {
                    // Check if file exists (modification vs ongoing creation)
                    if FileManager.default.fileExists(atPath: pathAsString) {
                        // Check if this is a stable modification (file size unchanged for a moment)
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: pathAsString)
                            if let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                                NSLog("📝 %@ FILE MODIFIED: %@", isVFXEvent ? "VFX" : "GRADE", fileName)
                                onVideoFilesModified?([fileName], isVFXEvent)
                            }
                        } catch {
                            NSLog("⚠️ Cannot read modified file attributes: %@ - %@", fileName, error.localizedDescription)
                        }
                    } else {
                        // File being created/copied - treat as creation
                        NSLog("🎬 %@ FILE CREATING: %@", isVFXEvent ? "VFX" : "GRADE", fileName)
                        pendingFiles[pathAsString] = (Date(), isVFXEvent)

                        debounceTimer?.invalidate()
                        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                            self?.processCompletedFiles()
                        }
                    }
                }
            }
        }
    }

    /// Process files that haven't been modified for the debounce interval
    private func processCompletedFiles() {
        NSLog("🔄 Processing completed files...")

        let now = Date()
        var gradeFiles: [URL] = []
        var vfxFiles: [URL] = []
        var filesToRemove: [String] = []

        for (filePath, (lastModified, isVFX)) in pendingFiles {
            let timeSinceModified = now.timeIntervalSince(lastModified)

            if timeSinceModified >= debounceInterval {
                // File hasn't been modified for debounce interval - should be complete
                if FileManager.default.fileExists(atPath: filePath) {
                    let fileURL = URL(fileURLWithPath: filePath)

                    // Double-check file is readable and has size > 0
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                        if let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                            NSLog("✅ File ready for import: %@ (size: %lld bytes) [%@]",
                                 fileURL.lastPathComponent, fileSize, isVFX ? "VFX" : "GRADE")

                            if isVFX {
                                vfxFiles.append(fileURL)
                            } else {
                                gradeFiles.append(fileURL)
                            }
                            filesToRemove.append(filePath)
                        } else {
                            NSLog("⚠️ File has zero size, waiting longer: %@", fileURL.lastPathComponent)
                        }
                    } catch {
                        NSLog("⚠️ Cannot read file attributes: %@ - %@", fileURL.lastPathComponent, error.localizedDescription)
                        filesToRemove.append(filePath) // Remove problematic files
                    }
                } else {
                    NSLog("⚠️ File no longer exists: %@", filePath)
                    filesToRemove.append(filePath)
                }
            }
        }

        // Remove processed files from pending queue
        for filePath in filesToRemove {
            pendingFiles.removeValue(forKey: filePath)
        }

        // Import completed files by type
        if !gradeFiles.isEmpty {
            NSLog("📢 Importing %d completed grade files", gradeFiles.count)
            onVideoFilesDetected?(gradeFiles, false)
        }

        if !vfxFiles.isEmpty {
            NSLog("📢 Importing %d completed VFX files", vfxFiles.count)
            onVideoFilesDetected?(vfxFiles, true)
        }

        // If there are still pending files, schedule another check
        if !pendingFiles.isEmpty {
            NSLog("⏳ %d files still pending, scheduling another check...", pendingFiles.count)
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                self?.processCompletedFiles()
            }
        }
    }

    deinit {
        stopWatching()
    }
}