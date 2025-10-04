//
//  Project.swift
//  ProResWriter
//
//  Created by Claude on 25/08/2025.
//

import Foundation
import ProResWriterCore
import SwiftUI
import CryptoKit

// MARK: - File Metadata

struct OfflineFileMetadata: Codable {
    let fileName: String
    let fileSize: Int64
    let offlineDate: Date
    let partialHash: String?  // Optional hash for fallback comparison
}

// MARK: - Project Data Model

class Project: ObservableObject, Codable, Identifiable {

    // MARK: - Basic Project Info
    let id = UUID()
    @Published var name: String
    @Published var createdDate: Date
    @Published var lastModified: Date

    // MARK: - Core Data Integration
    @Published var ocfFiles: [MediaFileInfo] = []
    @Published var segments: [MediaFileInfo] = []
    @Published var linkingResult: LinkingResult?
    // Note: ProcessingPlans are generated on-demand during print process to avoid Codable complexity

    // MARK: - Status Tracking
    @Published var blankRushStatus: [String: BlankRushStatus] = [:]  // OCF filename → status
    @Published var segmentModificationDates: [String: Date] = [:]  // Segment filename → last modified date
    @Published var segmentFileSizes: [String: Int64] = [:]  // Segment filename → file size (proactive tracking)
    @Published var offlineMediaFiles: Set<String> = []  // Track offline (deleted/moved) media files
    @Published var offlineFileMetadata: [String: OfflineFileMetadata] = [:]  // Track metadata for offline files
    @Published var lastPrintDate: Date?
    @Published var printHistory: [PrintRecord] = []
    @Published var ocfCardExpansionState: [String: Bool] = [:]  // OCF filename → isExpanded (default true if not set)
    
    // MARK: - Render Queue System
    @Published var renderQueue: [RenderQueueItem] = []
    @Published var printStatus: [String: PrintStatus] = [:]  // OCF filename → print status

    // MARK: - Project Settings
    @Published var outputDirectory: URL
    @Published var blankRushDirectory: URL
    @Published var fileURL: URL?

    // MARK: - Watch Folder Settings
    @Published var watchFolderSettings: WatchFolderSettings = WatchFolderSettings() {
        didSet {
            updateWatchFolderMonitoring()
        }
    }
    private var watchFolderService: SimpleWatchFolder?

    // MARK: - Computed Properties
    var hasLinkedMedia: Bool {
        linkingResult?.totalLinkedSegments ?? 0 > 0
    }

    var readyForBlankRush: Bool {
        linkingResult?.parentsWithChildren.isEmpty == false
    }

    /// Check if blank rush file exists on disk for given OCF filename
    func blankRushFileExists(for ocfFileName: String) -> Bool {
        let baseName = (ocfFileName as NSString).deletingPathExtension
        let blankRushFileName = "\(baseName)_blankRush.mov"
        let blankRushURL = blankRushDirectory.appendingPathComponent(blankRushFileName)
        return FileManager.default.fileExists(atPath: blankRushURL.path)
    }

    var blankRushProgress: (completed: Int, total: Int) {
        let total = linkingResult?.parentsWithChildren.count ?? 0
        let completed = blankRushStatus.values.compactMap {
            if case .completed = $0 { return 1 } else { return nil }
        }.count
        return (completed, total)
    }

    /// Check if any segments have been modified since last blank rush generation
    var hasModifiedSegments: Bool {
        guard let linkingResult = linkingResult else { return false }

        for parent in linkingResult.parentsWithChildren {
            for child in parent.children {
                let segmentFileName = child.segment.fileName

                // Get file modification date
                if let fileModDate = getFileModificationDate(for: child.segment.url),
                    let trackedModDate = segmentModificationDates[segmentFileName]
                {

                    // If file is newer than our tracked date, it's been modified
                    if fileModDate > trackedModDate {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Get segments that have been modified since tracking started
    var modifiedSegments: [String] {
        guard let linkingResult = linkingResult else { return [] }
        var modified: [String] = []

        for parent in linkingResult.parentsWithChildren {
            for child in parent.children {
                let segmentFileName = child.segment.fileName

                if let fileModDate = getFileModificationDate(for: child.segment.url),
                    let trackedModDate = segmentModificationDates[segmentFileName],
                    fileModDate > trackedModDate
                {
                    modified.append(segmentFileName)
                }
            }
        }
        return modified
    }

    // MARK: - Initialization
    init(name: String, outputDirectory: URL, blankRushDirectory: URL) {
        self.name = name
        self.createdDate = Date()
        self.lastModified = Date()
        self.outputDirectory = outputDirectory
        self.blankRushDirectory = blankRushDirectory
    }

    // MARK: - Codable Implementation
    private enum CodingKeys: String, CodingKey {
        case name, createdDate, lastModified
        case ocfFiles, segments, linkingResult
        case blankRushStatus, segmentModificationDates, segmentFileSizes, offlineMediaFiles, offlineFileMetadata, lastPrintDate, printHistory
        case renderQueue, printStatus
        case outputDirectory, blankRushDirectory, fileURL
        case watchFolderSettings
        case ocfCardExpansionState
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        lastModified = try container.decode(Date.self, forKey: .lastModified)

        ocfFiles = try container.decode([MediaFileInfo].self, forKey: .ocfFiles)
        segments = try container.decode([MediaFileInfo].self, forKey: .segments)
        linkingResult = try container.decodeIfPresent(LinkingResult.self, forKey: .linkingResult)

        blankRushStatus = try container.decode(
            [String: BlankRushStatus].self, forKey: .blankRushStatus)
        segmentModificationDates =
            try container.decodeIfPresent([String: Date].self, forKey: .segmentModificationDates)
            ?? [:]
        segmentFileSizes = try container.decodeIfPresent([String: Int64].self, forKey: .segmentFileSizes) ?? [:]
        offlineMediaFiles = try container.decodeIfPresent(Set<String>.self, forKey: .offlineMediaFiles) ?? []
        offlineFileMetadata = try container.decodeIfPresent([String: OfflineFileMetadata].self, forKey: .offlineFileMetadata) ?? [:]
        lastPrintDate = try container.decodeIfPresent(Date.self, forKey: .lastPrintDate)
        printHistory = try container.decodeIfPresent([PrintRecord].self, forKey: .printHistory) ?? []
        
        renderQueue = try container.decodeIfPresent([RenderQueueItem].self, forKey: .renderQueue) ?? []
        printStatus = try container.decodeIfPresent([String: PrintStatus].self, forKey: .printStatus) ?? [:]

        outputDirectory = try container.decode(URL.self, forKey: .outputDirectory)
        blankRushDirectory = try container.decode(URL.self, forKey: .blankRushDirectory)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)

        watchFolderSettings = try container.decodeIfPresent(WatchFolderSettings.self, forKey: .watchFolderSettings) ?? WatchFolderSettings()

        ocfCardExpansionState = try container.decodeIfPresent([String: Bool].self, forKey: .ocfCardExpansionState) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lastModified, forKey: .lastModified)

        try container.encode(ocfFiles, forKey: .ocfFiles)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(linkingResult, forKey: .linkingResult)

        try container.encode(blankRushStatus, forKey: .blankRushStatus)
        try container.encode(segmentModificationDates, forKey: .segmentModificationDates)
        try container.encode(segmentFileSizes, forKey: .segmentFileSizes)
        try container.encode(offlineMediaFiles, forKey: .offlineMediaFiles)
        try container.encode(offlineFileMetadata, forKey: .offlineFileMetadata)
        try container.encodeIfPresent(lastPrintDate, forKey: .lastPrintDate)
        try container.encode(printHistory, forKey: .printHistory)
        
        try container.encode(renderQueue, forKey: .renderQueue)
        try container.encode(printStatus, forKey: .printStatus)

        try container.encode(outputDirectory, forKey: .outputDirectory)
        try container.encode(blankRushDirectory, forKey: .blankRushDirectory)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)

        try container.encode(watchFolderSettings, forKey: .watchFolderSettings)

        try container.encode(ocfCardExpansionState, forKey: .ocfCardExpansionState)
    }

    // MARK: - Project Management
    func updateModified() {
        lastModified = Date()
    }

    func addOCFFiles(_ files: [MediaFileInfo]) {
        ocfFiles.append(contentsOf: files)
        updateModified()
    }

    func addSegments(_ newSegments: [MediaFileInfo]) {
        segments.append(contentsOf: newSegments)

        // Track file sizes for new segments (but NOT modification dates - those are only for changed files)
        for segment in newSegments {
            if let fileSize = getFileSize(for: segment.url) {
                segmentFileSizes[segment.fileName] = fileSize
                NSLog("📊 Stored size for segment: %@ (size: %lld bytes)", segment.fileName, fileSize)
            }
        }

        updateModified()
    }

    /// Update modification dates for all segments (useful for refresh)
    func refreshSegmentModificationDates() {
        for segment in segments {
            if let modDate = getFileModificationDate(for: segment.url) {
                segmentModificationDates[segment.fileName] = modDate
            }
        }
        updateModified()
    }

    func updateLinkingResult(_ result: LinkingResult) {
        linkingResult = result
        updateModified()

        // Initialize blank rush status for new OCF parents
        for parent in result.parentsWithChildren {
            if blankRushStatus[parent.ocf.fileName] == nil {
                // Check if blank rush file already exists on disk
                if blankRushFileExists(for: parent.ocf.fileName) {
                    let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
                    let blankRushFileName = "\(baseName)_BlankRush.mov"
                    let blankRushURL = blankRushDirectory.appendingPathComponent(blankRushFileName)
                    blankRushStatus[parent.ocf.fileName] = .completed(
                        date: Date(), url: blankRushURL)
                } else {
                    blankRushStatus[parent.ocf.fileName] = .notCreated
                }
            }
        }
    }

    func updateBlankRushStatus(ocfFileName: String, status: BlankRushStatus) {
        blankRushStatus[ocfFileName] = status
        updateModified()
    }

    func addPrintRecord(_ record: PrintRecord) {
        printHistory.append(record)
        lastPrintDate = record.date
        updateModified()
    }
    
    /// Check for modified segments and automatically update print status to needsReprint
    func checkForModifiedSegmentsAndUpdatePrintStatus() {
        guard let linkingResult = linkingResult else { return }
        
        var statusChanged = false
        
        for parent in linkingResult.parentsWithChildren {
            let ocfFileName = parent.ocf.fileName
            
            // Only check OCFs that have been printed
            guard let currentPrintStatus = printStatus[ocfFileName],
                  case .printed(let lastPrintDate, let outputURL) = currentPrintStatus else {
                continue
            }
            
            // Check if any segments for this OCF have been modified since last print
            var hasModifiedSegments = false
            for child in parent.children {
                if let fileModDate = getFileModificationDate(for: child.segment.url),
                   fileModDate > lastPrintDate {
                    hasModifiedSegments = true
                    break
                }
            }
            
            // If segments have been modified, mark for re-print
            if hasModifiedSegments {
                printStatus[ocfFileName] = .needsReprint(
                    lastPrintDate: lastPrintDate,
                    reason: .segmentModified
                )
                statusChanged = true
                NSLog("🔄 Auto-flagged \(ocfFileName) for re-print: segments modified since \(DateFormatter.short.string(from: lastPrintDate))")
            }
        }
        
        if statusChanged {
            updateModified()
        }
    }
    
    /// Refresh print status for all OCFs - useful to call when project is loaded or segments are updated
    func refreshPrintStatus() {
        checkForModifiedSegmentsAndUpdatePrintStatus()
    }

    /// Remove OCF files by filename
    func removeOCFFiles(_ fileNames: [String]) {
        ocfFiles.removeAll { fileNames.contains($0.fileName) }

        // Also clean up related linking results and blank rush status
        for fileName in fileNames {
            blankRushStatus.removeValue(forKey: fileName)
        }

        // If linking result exists, invalidate it since OCF files changed
        if linkingResult != nil {
            linkingResult = nil
        }

        updateModified()
    }

    /// Remove segments by filename
    func removeSegments(_ fileNames: [String]) {
        segments.removeAll { fileNames.contains($0.fileName) }

        // Clean up segment modification tracking, file sizes, and offline status
        for fileName in fileNames {
            segmentModificationDates.removeValue(forKey: fileName)
            segmentFileSizes.removeValue(forKey: fileName)
            offlineMediaFiles.remove(fileName)
        }

        // If linking result exists, invalidate it since segments changed
        if linkingResult != nil {
            linkingResult = nil
        }

        updateModified()
    }

    /// Remove all offline media files from the project
    func removeOfflineMedia() {
        let offlineFileNames = Array(offlineMediaFiles)

        NSLog("🗑️ Removing %d offline media files from project", offlineFileNames.count)

        // Remove offline segments
        segments.removeAll { offlineMediaFiles.contains($0.fileName) }

        // Remove offline OCFs
        ocfFiles.removeAll { offlineMediaFiles.contains($0.fileName) }

        // Clean up tracking data
        for fileName in offlineFileNames {
            segmentModificationDates.removeValue(forKey: fileName)
            segmentFileSizes.removeValue(forKey: fileName)
            printStatus.removeValue(forKey: fileName)
            blankRushStatus.removeValue(forKey: fileName)
            offlineFileMetadata.removeValue(forKey: fileName)
        }

        // Clear offline set
        offlineMediaFiles.removeAll()

        // Invalidate linking if any files were removed
        if !offlineFileNames.isEmpty {
            linkingResult = nil
        }

        updateModified()
        NSLog("✅ Removed all offline media files")
    }

    /// Toggle VFX status for OCF file
    func toggleOCFVFXStatus(_ fileName: String, isVFX: Bool) {
        if let index = ocfFiles.firstIndex(where: { $0.fileName == fileName }) {
            ocfFiles[index].isVFXShot = isVFX
            updateModified()
        }
    }

    /// Toggle VFX status for segment file
    func toggleSegmentVFXStatus(_ fileName: String, isVFX: Bool) {
        if let index = segments.firstIndex(where: { $0.fileName == fileName }) {
            segments[index].isVFXShot = isVFX
            updateModified()
        }
    }

    // MARK: - File System Helpers

    /// Get file modification date from file system
    private func getFileModificationDate(for url: URL) -> Date? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            print("⚠️ Could not get modification date for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func getFileSize(for url: URL) -> Int64? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return resourceValues.fileSize.map { Int64($0) }
        } catch {
            print("⚠️ Could not get file size for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Calculate partial hash (first 1MB + last 1MB) for file comparison
    private func calculatePartialHash(for url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            NSLog("⚠️ Could not open file for hashing: %@", url.lastPathComponent)
            return nil
        }
        defer { try? fileHandle.close() }

        do {
            let chunkSize = 1024 * 1024  // 1MB
            var hasher = SHA256()

            // Get file size
            let fileSize = try fileHandle.seekToEnd()
            try fileHandle.seek(toOffset: 0)

            // Hash first chunk (or entire file if smaller)
            let firstChunkSize = min(UInt64(chunkSize), fileSize)
            if let firstData = try? fileHandle.read(upToCount: Int(firstChunkSize)) {
                hasher.update(data: firstData)
            }

            // Hash last chunk if file is large enough
            if fileSize > UInt64(chunkSize * 2) {
                try fileHandle.seek(toOffset: fileSize - UInt64(chunkSize))
                if let lastData = try? fileHandle.read(upToCount: chunkSize) {
                    hasher.update(data: lastData)
                }
            }

            let digest = hasher.finalize()
            let hashString = digest.map { String(format: "%02x", $0) }.joined()
            return hashString
        } catch {
            NSLog("⚠️ Error calculating hash for %@: %@", url.lastPathComponent, error.localizedDescription)
            return nil
        }
    }

    /// Scan for existing blank rush files and update status accordingly
    func scanForExistingBlankRushes() {
        guard let linkingResult = linkingResult else { return }

        for parent in linkingResult.parentsWithChildren {
            // Only check if we don't already have a status or if it's marked as not created
            if blankRushStatus[parent.ocf.fileName] == nil
                || blankRushStatus[parent.ocf.fileName] == .notCreated
            {
                if blankRushFileExists(for: parent.ocf.fileName) {
                    let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
                    let blankRushFileName = "\(baseName)_BlankRush.mov"
                    let blankRushURL = blankRushDirectory.appendingPathComponent(blankRushFileName)
                    blankRushStatus[parent.ocf.fileName] = .completed(
                        date: Date(), url: blankRushURL)
                    print("🔍 Found existing blank rush: \(blankRushFileName)")
                }
            }
        }
    }

    // MARK: - Watch Folder Monitoring

    private func updateWatchFolderMonitoring() {
        NSLog("🔄 Watch folder settings changed: enabled=%@", watchFolderSettings.isEnabled ? "true" : "false")

        if watchFolderSettings.isEnabled {
            startWatchFolderIfNeeded()
        } else {
            stopWatchFolder()
        }
    }

    private func startWatchFolderIfNeeded() {
        let gradePath = watchFolderSettings.primaryGradeFolder?.path
        let vfxPath = watchFolderSettings.vfxFolder?.path

        guard gradePath != nil || vfxPath != nil else {
            NSLog("⚠️ No watch folder paths specified")
            return
        }

        NSLog("🚀 Starting watch folder monitoring...")
        if let gradePath = gradePath {
            NSLog("📁 Grade folder: %@", gradePath)
        }
        if let vfxPath = vfxPath {
            NSLog("🎬 VFX folder: %@", vfxPath)
        }

        watchFolderService = SimpleWatchFolder()

        // Set up callback for when video files are detected
        watchFolderService?.onVideoFilesDetected = { [weak self] videoFiles, isVFX in
            DispatchQueue.main.async {
                self?.handleDetectedVideoFiles(videoFiles, isVFX: isVFX)
            }
        }

        // Set up callback for when video files are deleted
        watchFolderService?.onVideoFilesDeleted = { [weak self] fileNames, isVFX in
            DispatchQueue.main.async {
                self?.handleDeletedVideoFiles(fileNames, isVFX: isVFX)
            }
        }

        // Set up callback for when video files are modified
        watchFolderService?.onVideoFilesModified = { [weak self] fileNames, isVFX in
            DispatchQueue.main.async {
                self?.handleModifiedVideoFiles(fileNames, isVFX: isVFX)
            }
        }

        watchFolderService?.startWatching(gradePath: gradePath, vfxPath: vfxPath)

        // Check for files that changed while app was closed
        checkForChangedFilesOnStartup(gradePath: gradePath, vfxPath: vfxPath)
    }

    /// Check if any already-imported files in watch folders have changed while app was closed
    private func checkForChangedFilesOnStartup(gradePath: String?, vfxPath: String?) {
        NSLog("🔍 Checking for file changes that occurred while app was closed...")

        var changedCount = 0

        for segment in segments {
            let fileName = segment.fileName
            let fileURL = segment.url

            // Check if this segment is in a watch folder
            var isInWatchFolder = false
            if let gradePath = gradePath, fileURL.path.hasPrefix(gradePath) {
                isInWatchFolder = true
            } else if let vfxPath = vfxPath, fileURL.path.hasPrefix(vfxPath) {
                isInWatchFolder = true
            }

            guard isInWatchFolder else { continue }

            // Check if file exists and compare size
            if let storedSize = segmentFileSizes[fileName],
               let currentSize = getFileSize(for: fileURL) {

                if currentSize != storedSize {
                    // File size changed while app was closed
                    NSLog("⚠️ File changed while app was closed: %@ (old: %lld, new: %lld bytes)",
                          fileName, storedSize, currentSize)

                    // Update modification date and size
                    segmentModificationDates[fileName] = Date()
                    segmentFileSizes[fileName] = currentSize

                    // Mark affected OCFs for re-print
                    if let linkingResult = linkingResult {
                        for ocfParent in linkingResult.ocfParents {
                            for child in ocfParent.children {
                                if child.segment.fileName == fileName {
                                    let lastPrint = printStatus[ocfParent.ocf.fileName]
                                    let printDate: Date
                                    if case .printed(let date, _) = lastPrint {
                                        printDate = date
                                    } else {
                                        printDate = Date()
                                    }
                                    printStatus[ocfParent.ocf.fileName] = .needsReprint(lastPrintDate: printDate, reason: .segmentModified)
                                }
                            }
                        }
                    }

                    changedCount += 1
                }
            } else if !FileManager.default.fileExists(atPath: fileURL.path) {
                // File was deleted while app was closed
                if !offlineMediaFiles.contains(fileName) {
                    NSLog("⚠️ File deleted while app was closed: %@", fileName)
                    offlineMediaFiles.insert(fileName)

                    // Store metadata
                    if let storedSize = segmentFileSizes[fileName] {
                        let metadata = OfflineFileMetadata(
                            fileName: fileName,
                            fileSize: storedSize,
                            offlineDate: Date(),
                            partialHash: nil
                        )
                        offlineFileMetadata[fileName] = metadata
                    }

                    changedCount += 1
                }
            }
        }

        if changedCount > 0 {
            NSLog("✅ Found %d file(s) that changed while app was closed", changedCount)
            objectWillChange.send()
        } else {
            NSLog("✅ No changes detected in watch folders")
        }
    }

    private func stopWatchFolder() {
        NSLog("🛑 Stopping watch folder monitoring")
        watchFolderService?.stopWatching()
        watchFolderService = nil
    }

    /// Handle video files detected by the watch folder service
    private func handleDetectedVideoFiles(_ videoFiles: [URL], isVFX: Bool) {
        guard watchFolderSettings.autoImportEnabled else {
            NSLog("⚠️ Auto-import disabled, ignoring detected files")
            return
        }

        // Check for returning offline files first
        var returningOfflineFiles: [URL] = []
        var changedOfflineFiles: [URL] = []
        var newVideoFiles: [URL] = []

        let existingFileNames = Set(segments.map { $0.fileName })

        for url in videoFiles {
            let fileName = url.lastPathComponent

            // Check if this is a returning offline file
            if offlineMediaFiles.contains(fileName) {
                if let metadata = offlineFileMetadata[fileName],
                   let currentSize = getFileSize(for: url) {

                    if currentSize == metadata.fileSize {
                        // Same size - treat as same file returning
                        returningOfflineFiles.append(url)
                        NSLog("🔄 Offline file returned unchanged: %@ (size: %lld bytes)", fileName, currentSize)
                    } else {
                        // Different size - file has changed
                        changedOfflineFiles.append(url)
                        NSLog("⚠️ Offline file returned but CHANGED: %@ (old: %lld, new: %lld bytes)",
                              fileName, metadata.fileSize, currentSize)
                    }
                } else if let currentSize = getFileSize(for: url) {
                    // No metadata - use hash fallback
                    NSLog("🔐 No metadata for %@ - computing hash for comparison", fileName)

                    if let currentHash = calculatePartialHash(for: url) {
                        // Check if we have a stored hash to compare
                        if let metadata = offlineFileMetadata[fileName], let storedHash = metadata.partialHash {
                            if currentHash == storedHash {
                                // Hash matches - same file
                                returningOfflineFiles.append(url)
                                NSLog("🔄 Hash match - file unchanged: %@", fileName)
                            } else {
                                // Hash different - file changed
                                changedOfflineFiles.append(url)
                                NSLog("⚠️ Hash mismatch - file changed: %@", fileName)
                            }
                        } else {
                            // No stored hash - store for next time and treat as changed
                            let newMetadata = OfflineFileMetadata(
                                fileName: fileName,
                                fileSize: currentSize,
                                offlineDate: Date(),
                                partialHash: currentHash
                            )
                            offlineFileMetadata[fileName] = newMetadata
                            changedOfflineFiles.append(url)
                            NSLog("🔐 Computed and stored hash - treating as changed: %@", fileName)
                        }
                    } else {
                        // Hash computation failed - treat as returning with changes
                        changedOfflineFiles.append(url)
                        NSLog("⚠️ Hash computation failed - treating as changed: %@", fileName)
                    }
                } else {
                    // Can't get file size - treat as returning
                    returningOfflineFiles.append(url)
                    NSLog("🔄 Offline file returned (no size check possible): %@", fileName)
                }
            } else if existingFileNames.contains(fileName) {
                // File already exists and is online - check if it has changed
                if let storedSize = segmentFileSizes[fileName],
                   let currentSize = getFileSize(for: url) {

                    if currentSize != storedSize {
                        // Size changed - file has been replaced
                        changedOfflineFiles.append(url)
                        NSLog("⚠️ Online file CHANGED: %@ (old: %lld, new: %lld bytes)",
                              fileName, storedSize, currentSize)
                    } else {
                        // Size unchanged - ignore (already imported)
                        NSLog("📋 File already imported and unchanged: %@", fileName)
                    }
                } else {
                    // No stored size to compare - ignore
                    NSLog("📋 File already imported (no size tracking): %@", fileName)
                }
            } else {
                // Truly new file
                newVideoFiles.append(url)
            }
        }

        // Handle returning offline files (same size - just remove offline status)
        for url in returningOfflineFiles {
            let fileName = url.lastPathComponent
            offlineMediaFiles.remove(fileName)
            offlineFileMetadata.removeValue(forKey: fileName)
            NSLog("✅ File %@ is back online", fileName)
        }

        // Handle changed offline files (different size - treat as modified)
        for url in changedOfflineFiles {
            let fileName = url.lastPathComponent
            offlineMediaFiles.remove(fileName)
            offlineFileMetadata.removeValue(forKey: fileName)
            segmentModificationDates[fileName] = Date()

            // Update file size metadata with new size
            if let newSize = getFileSize(for: url) {
                segmentFileSizes[fileName] = newSize
                NSLog("📊 Updated size for changed file: %@ (new size: %lld bytes)", fileName, newSize)
            }

            NSLog("✅ File %@ is back online and marked as modified", fileName)

            // Mark affected OCFs for re-print
            if let linkingResult = linkingResult {
                for ocfParent in linkingResult.ocfParents {
                    for child in ocfParent.children {
                        if child.segment.fileName == fileName {
                            let lastPrint = printStatus[ocfParent.ocf.fileName]
                            let printDate: Date
                            if case .printed(let date, _) = lastPrint {
                                printDate = date
                            } else {
                                printDate = Date()
                            }
                            printStatus[ocfParent.ocf.fileName] = .needsReprint(lastPrintDate: printDate, reason: .segmentModified)
                        }
                    }
                }
            }
        }

        // Note: We no longer invalidate linking when files change
        // The "Updated" badge shows which files have changed
        // The OCF "Needs Re-print" status shows what needs to be re-printed
        // User can manually re-run linking if they want to refresh the analysis

        // Import truly new files
        guard !newVideoFiles.isEmpty else {
            if returningOfflineFiles.isEmpty && changedOfflineFiles.isEmpty {
                NSLog("⚠️ All detected files already imported, ignoring %d file(s)", videoFiles.count)
            }
            return
        }

        NSLog("🎬 Auto-importing %d new %@ files...", newVideoFiles.count, isVFX ? "VFX" : "grade")

        // Import as segments with VFX flag
        Task {
            let mediaFiles = await analyzeDetectedFiles(urls: newVideoFiles, isVFX: isVFX)

            await MainActor.run {
                addSegments(mediaFiles)
                NSLog("✅ Auto-imported %d new %@ files from watch folder",
                      mediaFiles.count, isVFX ? "VFX" : "grade")
            }
        }
    }

    /// Analyze detected video files for import
    private func analyzeDetectedFiles(urls: [URL], isVFX: Bool) async -> [MediaFileInfo] {
        NSLog("🔍 Analyzing %d detected %@ files...", urls.count, isVFX ? "VFX" : "grade")

        // Process files serially to avoid potential MediaAnalyzer threading issues on M1
        var results: [MediaFileInfo] = []

        for url in urls {
            do {
                NSLog("📹 Analyzing: %@", url.lastPathComponent)
                let mediaFile = try await MediaAnalyzer().analyzeMediaFile(
                    at: url,
                    type: .gradedSegment
                )

                // Set VFX flag on the media file if it's from VFX folder
                if isVFX {
                    var vfxMediaFile = mediaFile
                    vfxMediaFile.isVFXShot = true
                    results.append(vfxMediaFile)
                } else {
                    results.append(mediaFile)
                }

                NSLog("✅ Analyzed: %@", url.lastPathComponent)
            } catch {
                NSLog("❌ Failed to analyze watch folder file %@: %@", url.lastPathComponent, error.localizedDescription)
            }
        }

        NSLog("✅ Analysis complete: %d/%d files analyzed successfully", results.count, urls.count)
        return results
    }

    /// Handle video files deleted from watch folder
    private func handleDeletedVideoFiles(_ fileNames: [String], isVFX: Bool) {
        NSLog("📤 Marking %d deleted %@ files as offline...", fileNames.count, isVFX ? "VFX" : "grade")

        // Mark segments as offline instead of removing them
        var markedCount = 0
        for fileName in fileNames {
            if segments.contains(where: { $0.fileName == fileName }) {
                offlineMediaFiles.insert(fileName)

                // Store metadata using pre-stored file size
                if let fileSize = segmentFileSizes[fileName] {
                    let metadata = OfflineFileMetadata(
                        fileName: fileName,
                        fileSize: fileSize,
                        offlineDate: Date(),
                        partialHash: nil  // Hash will be computed on return if needed
                    )
                    offlineFileMetadata[fileName] = metadata
                    NSLog("📊 Stored metadata for offline file: %@ (size: %lld bytes)", fileName, fileSize)
                } else {
                    NSLog("⚠️ No pre-stored size for %@ - will use hash fallback on return", fileName)
                }

                markedCount += 1
            }
        }

        if markedCount > 0 {
            NSLog("✅ Marked %d deleted %@ files as offline", markedCount, isVFX ? "VFX" : "grade")

            // Mark affected OCFs for re-print
            if let linkingResult = linkingResult {
                for fileName in fileNames where offlineMediaFiles.contains(fileName) {
                    for ocfParent in linkingResult.ocfParents {
                        for child in ocfParent.children {
                            if child.segment.fileName == fileName {
                                let lastPrint = printStatus[ocfParent.ocf.fileName]
                                let printDate: Date
                                if case .printed(let date, _) = lastPrint {
                                    printDate = date
                                } else {
                                    printDate = Date()
                                }
                                printStatus[ocfParent.ocf.fileName] = .needsReprint(lastPrintDate: printDate, reason: .segmentOffline)
                                NSLog("⚠️ OCF %@ needs reprint due to offline segment", ocfParent.ocf.fileName)
                            }
                        }
                    }
                }
            }
        } else {
            NSLog("⚠️ No matching files found to mark offline for deleted %@ files", isVFX ? "VFX" : "grade")
        }
    }

    /// Handle video files modified in watch folder
    private func handleModifiedVideoFiles(_ fileNames: [String], isVFX: Bool) {
        NSLog("📝 Handling %d modified %@ files...", fileNames.count, isVFX ? "VFX" : "grade")

        // Track which OCF parents need re-printing due to modified segments
        var affectedOCFNames = Set<String>()

        for fileName in fileNames {
            // Find segment by filename
            if let segment = segments.first(where: { $0.fileName == fileName }) {
                NSLog("📝 Found modified segment: %@", fileName)

                // Update the segment's modification date to mark it as changed
                updateSegmentModificationDate(fileName)

                // Update file size for modified segment
                if let fileSize = getFileSize(for: segment.url) {
                    segmentFileSizes[fileName] = fileSize
                    NSLog("📊 Updated size for modified segment: %@ (size: %lld bytes)", fileName, fileSize)
                }

                // Find linked OCF files that use this segment
                if let linkingResult = linkingResult {
                    for ocfParent in linkingResult.ocfParents {
                        for child in ocfParent.children {
                            if child.segment.fileName == fileName {
                                affectedOCFNames.insert(ocfParent.ocf.fileName)
                                NSLog("📝 Segment %@ affects OCF: %@", fileName, ocfParent.ocf.fileName)
                            }
                        }
                    }
                }
            }
        }

        // Mark affected OCFs as needing re-printing
        for ocfFileName in affectedOCFNames {
            printStatus[ocfFileName] = .needsReprint(
                lastPrintDate: Date(),
                reason: .segmentModified
            )
            NSLog("🔄 Marked OCF %@ as needing re-print due to modified segment", ocfFileName)
        }

        if !affectedOCFNames.isEmpty {
            NSLog("✅ Marked %d OCFs as needing re-print due to %d modified %@ files",
                  affectedOCFNames.count, fileNames.count, isVFX ? "VFX" : "grade")
        }
    }

    /// Update modification date for a specific segment
    private func updateSegmentModificationDate(_ fileName: String) {
        if segments.contains(where: { $0.fileName == fileName }) {
            segmentModificationDates[fileName] = Date()
            NSLog("📅 Updated modification date for segment: %@", fileName)
        }
    }
}

// MARK: - Supporting Types

enum BlankRushStatus: Codable, Equatable {
    case notCreated
    case inProgress
    case completed(date: Date, url: URL)
    case failed(error: String)

    var statusIcon: String {
        switch self {
        case .notCreated: return "⚫️"
        case .inProgress: return "🟡"
        case .completed: return "🟢"
        case .failed: return "🔴"
        }
    }

    var description: String {
        switch self {
        case .notCreated: return "Not Created"
        case .inProgress: return "In Progress"
        case .completed(let date, _): return "Completed \(DateFormatter.short.string(from: date))"
        case .failed(let error): return "Failed: \(error)"
        }
    }
}

struct PrintRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let outputURL: URL
    let segmentCount: Int
    let duration: TimeInterval
    let success: Bool

    init(date: Date, outputURL: URL, segmentCount: Int, duration: TimeInterval, success: Bool) {
        self.id = UUID()
        self.date = date
        self.outputURL = outputURL
        self.segmentCount = segmentCount
        self.duration = duration
        self.success = success
    }

    var statusIcon: String {
        success ? "✅" : "❌"
    }
}

// MARK: - Render Queue System

struct RenderQueueItem: Codable, Identifiable {
    let id: UUID
    let ocfFileName: String
    let addedDate: Date
    var status: RenderQueueStatus
    
    init(ocfFileName: String) {
        self.id = UUID()
        self.ocfFileName = ocfFileName
        self.addedDate = Date()
        self.status = .queued
    }
}

enum RenderQueueStatus: String, Codable, CaseIterable {
    case queued = "queued"
    case rendering = "rendering"
    case completed = "completed"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .rendering: return "Rendering"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    
    var icon: String {
        switch self {
        case .queued: return "clock"
        case .rendering: return "gear"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .queued: return AppTheme.queued
        case .rendering: return AppTheme.rendering
        case .completed: return AppTheme.completed
        case .failed: return AppTheme.failed
        }
    }
}


enum PrintStatus: Codable {
    case notPrinted
    case printed(date: Date, outputURL: URL)
    case needsReprint(lastPrintDate: Date, reason: ReprintReason)
    
    var displayName: String {
        switch self {
        case .notPrinted:
            return "Not Printed"
        case .printed(let date, _):
            return "Printed \(DateFormatter.short.string(from: date))"
        case .needsReprint(let lastPrintDate, let reason):
            return "Needs Re-print (\(reason.displayName))"
        }
    }
    
    var icon: String {
        switch self {
        case .notPrinted: return "minus.circle"
        case .printed: return "checkmark.circle.fill"
        case .needsReprint: return "exclamationmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .notPrinted: return AppTheme.notPrinted
        case .printed: return AppTheme.printed
        case .needsReprint: return AppTheme.needsReprint
        }
    }
}

enum ReprintReason: String, Codable {
    case segmentModified = "segment_modified"
    case segmentOffline = "segment_offline"
    case manualRequest = "manual_request"
    case previousFailed = "previous_failed"

    var displayName: String {
        switch self {
        case .segmentModified: return "Segment Modified"
        case .segmentOffline: return "Segment Offline"
        case .manualRequest: return "Manual Request"
        case .previousFailed: return "Previous Failed"
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
