//
//  Project.swift
//  ProResWriter
//
//  Created by Claude on 25/08/2025.
//

import Foundation
import SwiftUI

// MARK: - Project Data Model

class Project: ObservableObject, Codable {
    
    // MARK: - Basic Project Info
    @Published var name: String
    @Published var createdDate: Date
    @Published var lastModified: Date
    
    // MARK: - Core Data Integration
    @Published var ocfFiles: [MediaFileInfo] = []
    @Published var segments: [MediaFileInfo] = []
    @Published var linkingResult: LinkingResult?
    
    // MARK: - Status Tracking
    @Published var blankRushStatus: [String: BlankRushStatus] = [:]  // OCF filename → status
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
    
    var blankRushProgress: (completed: Int, total: Int) {
        let total = linkingResult?.parentsWithChildren.count ?? 0
        let completed = blankRushStatus.values.compactMap { 
            if case .completed = $0 { return 1 } else { return nil }
        }.count
        return (completed, total)
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
        case blankRushStatus, lastPrintDate, printHistory
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
        
        blankRushStatus = try container.decode([String: BlankRushStatus].self, forKey: .blankRushStatus)
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
        updateModified()
    }
    
    func updateLinkingResult(_ result: LinkingResult) {
        linkingResult = result
        updateModified()
        
        // Initialize blank rush status for new OCF parents
        for parent in result.parentsWithChildren {
            if blankRushStatus[parent.ocf.fileName] == nil {
                blankRushStatus[parent.ocf.fileName] = .notCreated
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
    let id = UUID()
    let date: Date
    let outputURL: URL
    let segmentCount: Int
    let duration: TimeInterval
    let success: Bool
    
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