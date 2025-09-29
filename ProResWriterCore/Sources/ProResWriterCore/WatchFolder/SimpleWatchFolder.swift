//
//  SimpleWatchFolder.swift
//  ProResWriterCore
//
//  Created by Claude on 29/09/2025.
//  Minimal FSEvents monitoring service for testing
//

import Foundation
import CoreServices

/// Minimal watch folder service that only proves FSEvents work
public class SimpleWatchFolder {
    private var eventStream: FSEventStreamRef?
    private var isActive = false

    /// Callback for when video files are detected
    public var onVideoFilesDetected: (([URL]) -> Void)?

    /// Pending files waiting for copy completion
    private var pendingFiles: [String: Date] = [:]
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 3.0 // Wait 3 seconds after last change

    public init() {}

    /// Start monitoring a specific folder
    public func startWatching(path: String) {
        print("🔍 SimpleWatchFolder: Starting to watch \(path)")

        guard !isActive else {
            print("⚠️ Already watching - stop first")
            return
        }

        // Create array of paths to watch
        let pathsArray = [path] as CFArray

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
            print("❌ Failed to create FSEventStream")
            return
        }

        // Schedule on run loop
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Start the stream
        if FSEventStreamStart(stream) {
            isActive = true
            print("✅ SimpleWatchFolder: Successfully started monitoring \(path)")
        } else {
            print("❌ Failed to start FSEventStream")
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    /// Stop monitoring
    public func stopWatching() {
        print("🛑 SimpleWatchFolder: Stopping watch")

        guard let stream = eventStream, isActive else {
            print("⚠️ Not currently watching")
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamUnscheduleFromRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamRelease(stream)

        // Clean up debounce timer and pending files
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingFiles.removeAll()

        eventStream = nil
        isActive = false
        print("✅ SimpleWatchFolder: Stopped")
    }

    /// Handle FSEvents callback
    private func handleEvents(numEvents: Int, eventPaths: UnsafeRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>) {
        print("🚨 FSEvent triggered! \(numEvents) events")

        // Convert eventPaths to array of path strings using safer approach
        let pathsPointer = eventPaths.bindMemory(to: UnsafePointer<CChar>.self, capacity: numEvents)
        let pathsBuffer = UnsafeBufferPointer(start: pathsPointer, count: numEvents)

        for i in 0..<numEvents {
            // Safely get the path string
            guard i < pathsBuffer.count else {
                print("⚠️ Index \(i) out of bounds")
                continue
            }

            let pathPtr = pathsBuffer[i]
            let pathAsString = String(cString: pathPtr)
            let flags = eventFlags[i]

            print("📁 Event \(i): \(pathAsString)")
            print("   Flags: \(flags)")

            // Check for file events and video file extensions
            let isFileEvent = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0 ||
                              (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0
            let videoExtensions = ["mov", "mp4", "m4v", "mxf", "prores"]
            let pathExtension = URL(fileURLWithPath: pathAsString).pathExtension.lowercased()

            if isFileEvent && videoExtensions.contains(pathExtension) {
                print("🎬 VIDEO FILE EVENT: \(URL(fileURLWithPath: pathAsString).lastPathComponent)")

                // Add to pending files with current timestamp
                pendingFiles[pathAsString] = Date()

                // Reset debounce timer
                debounceTimer?.invalidate()
                debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                    self?.processCompletedFiles()
                }

                print("⏳ File added to pending queue. Will process in \(debounceInterval) seconds if no more changes...")
            }
        }
    }

    /// Process files that haven't been modified for the debounce interval
    private func processCompletedFiles() {
        print("🔄 Processing completed files...")

        let now = Date()
        var completedFiles: [URL] = []
        var filesToRemove: [String] = []

        for (filePath, lastModified) in pendingFiles {
            let timeSinceModified = now.timeIntervalSince(lastModified)

            if timeSinceModified >= debounceInterval {
                // File hasn't been modified for debounce interval - should be complete
                if FileManager.default.fileExists(atPath: filePath) {
                    let fileURL = URL(fileURLWithPath: filePath)

                    // Double-check file is readable and has size > 0
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                        if let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                            print("✅ File ready for import: \(fileURL.lastPathComponent) (size: \(fileSize) bytes)")
                            completedFiles.append(fileURL)
                            filesToRemove.append(filePath)
                        } else {
                            print("⚠️ File has zero size, waiting longer: \(fileURL.lastPathComponent)")
                        }
                    } catch {
                        print("⚠️ Cannot read file attributes: \(fileURL.lastPathComponent) - \(error)")
                        filesToRemove.append(filePath) // Remove problematic files
                    }
                } else {
                    print("⚠️ File no longer exists: \(filePath)")
                    filesToRemove.append(filePath)
                }
            }
        }

        // Remove processed files from pending queue
        for filePath in filesToRemove {
            pendingFiles.removeValue(forKey: filePath)
        }

        // Import completed files
        if !completedFiles.isEmpty {
            print("📢 Importing \(completedFiles.count) completed files")
            onVideoFilesDetected?(completedFiles)
        }

        // If there are still pending files, schedule another check
        if !pendingFiles.isEmpty {
            print("⏳ \(pendingFiles.count) files still pending, scheduling another check...")
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                self?.processCompletedFiles()
            }
        }
    }

    deinit {
        stopWatching()
    }
}