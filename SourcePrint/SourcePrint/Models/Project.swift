//
//  Project.swift
//  ProResWriter
//
//  Created by Claude on 25/08/2025.
//

import Foundation
import ProResWriterCore
import SwiftUI

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
    @Published var offlineMediaFiles: Set<String> = []  // Track offline (deleted/moved) media files
    @Published var lastPrintDate: Date?
    @Published var printHistory: [PrintRecord] = []
    
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
        case blankRushStatus, segmentModificationDates, offlineMediaFiles, lastPrintDate, printHistory
        case renderQueue, printStatus
        case outputDirectory, blankRushDirectory, fileURL
        case watchFolderSettings
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
        offlineMediaFiles = try container.decodeIfPresent(Set<String>.self, forKey: .offlineMediaFiles) ?? []
        lastPrintDate = try container.decodeIfPresent(Date.self, forKey: .lastPrintDate)
        printHistory = try container.decodeIfPresent([PrintRecord].self, forKey: .printHistory) ?? []
        
        renderQueue = try container.decodeIfPresent([RenderQueueItem].self, forKey: .renderQueue) ?? []
        printStatus = try container.decodeIfPresent([String: PrintStatus].self, forKey: .printStatus) ?? [:]

        outputDirectory = try container.decode(URL.self, forKey: .outputDirectory)
        blankRushDirectory = try container.decode(URL.self, forKey: .blankRushDirectory)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)

        watchFolderSettings = try container.decodeIfPresent(WatchFolderSettings.self, forKey: .watchFolderSettings) ?? WatchFolderSettings()
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
        try container.encode(offlineMediaFiles, forKey: .offlineMediaFiles)
        try container.encodeIfPresent(lastPrintDate, forKey: .lastPrintDate)
        try container.encode(printHistory, forKey: .printHistory)
        
        try container.encode(renderQueue, forKey: .renderQueue)
        try container.encode(printStatus, forKey: .printStatus)

        try container.encode(outputDirectory, forKey: .outputDirectory)
        try container.encode(blankRushDirectory, forKey: .blankRushDirectory)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)

        try container.encode(watchFolderSettings, forKey: .watchFolderSettings)
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

        // Track modification dates for new segments
        for segment in newSegments {
            if let modDate = getFileModificationDate(for: segment.url) {
                segmentModificationDates[segment.fileName] = modDate
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

        // Clean up segment modification tracking and offline status
        for fileName in fileNames {
            segmentModificationDates.removeValue(forKey: fileName)
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
            printStatus.removeValue(forKey: fileName)
            blankRushStatus.removeValue(forKey: fileName)
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

        // Filter out files that are already imported (prevent duplicates on file overwrites)
        let existingFileNames = Set(segments.map { $0.fileName })
        let newVideoFiles = videoFiles.filter { url in
            !existingFileNames.contains(url.lastPathComponent)
        }

        guard !newVideoFiles.isEmpty else {
            NSLog("⚠️ All detected files already imported, ignoring %d file(s)", videoFiles.count)
            return
        }

        NSLog("🎬 Auto-importing %d new %@ files (filtered %d duplicates)...",
              newVideoFiles.count, isVFX ? "VFX" : "grade", videoFiles.count - newVideoFiles.count)

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

        return await withTaskGroup(of: MediaFileInfo?.self, returning: [MediaFileInfo].self) { taskGroup in
            // Add tasks for each URL
            for url in urls {
                taskGroup.addTask {
                    do {
                        let mediaFile = try await MediaAnalyzer().analyzeMediaFile(
                            at: url,
                            type: .gradedSegment
                        )

                        // Set VFX flag on the media file if it's from VFX folder
                        if isVFX {
                            var vfxMediaFile = mediaFile
                            vfxMediaFile.isVFXShot = true
                            return vfxMediaFile
                        }

                        return mediaFile
                    } catch {
                        NSLog("❌ Failed to analyze watch folder file %@: %@", url.lastPathComponent, error.localizedDescription)
                        return nil
                    }
                }
            }

            // Collect results
            var results: [MediaFileInfo] = []
            for await result in taskGroup {
                if let mediaFile = result {
                    results.append(mediaFile)
                }
            }
            return results
        }
    }

    /// Handle video files deleted from watch folder
    private func handleDeletedVideoFiles(_ fileNames: [String], isVFX: Bool) {
        NSLog("📤 Marking %d deleted %@ files as offline...", fileNames.count, isVFX ? "VFX" : "grade")

        // Mark segments as offline instead of removing them
        var markedCount = 0
        for fileName in fileNames {
            if segments.contains(where: { $0.fileName == fileName }) {
                offlineMediaFiles.insert(fileName)
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
