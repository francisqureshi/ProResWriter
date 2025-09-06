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

    // MARK: - Status Tracking
    @Published var blankRushStatus: [String: BlankRushStatus] = [:]  // OCF filename → status
    @Published var segmentModificationDates: [String: Date] = [:]  // Segment filename → last modified date
    @Published var lastPrintDate: Date?
    @Published var printHistory: [PrintRecord] = []

    // MARK: - Project Settings
    @Published var outputDirectory: URL
    @Published var blankRushDirectory: URL

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
        case blankRushStatus, segmentModificationDates, lastPrintDate, printHistory
        case outputDirectory, blankRushDirectory
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
        lastPrintDate = try container.decodeIfPresent(Date.self, forKey: .lastPrintDate)
        printHistory = try container.decode([PrintRecord].self, forKey: .printHistory)

        outputDirectory = try container.decode(URL.self, forKey: .outputDirectory)
        blankRushDirectory = try container.decode(URL.self, forKey: .blankRushDirectory)
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
        try container.encodeIfPresent(lastPrintDate, forKey: .lastPrintDate)
        try container.encode(printHistory, forKey: .printHistory)

        try container.encode(outputDirectory, forKey: .outputDirectory)
        try container.encode(blankRushDirectory, forKey: .blankRushDirectory)
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

        // Clean up segment modification tracking
        for fileName in fileNames {
            segmentModificationDates.removeValue(forKey: fileName)
        }

        // If linking result exists, invalidate it since segments changed
        if linkingResult != nil {
            linkingResult = nil
        }

        updateModified()
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

// MARK: - Extensions

extension DateFormatter {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
