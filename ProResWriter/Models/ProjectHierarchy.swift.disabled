//
//  ProjectHierarchy.swift
//  ProResWriter
//
//  Created by Claude on 25/08/2025.
//

import Foundation
import SwiftUI

// MARK: - Hierarchical Data Models for UI

/// Represents a hierarchical item in the project outline view
protocol HierarchicalItem: Identifiable, ObservableObject {
    var id: String { get }
    var displayName: String { get }
    var children: [HierarchicalItem]? { get }
    var statusIcon: String { get }
    var metadata: String { get }
    var timecodeRange: String { get }
}

// MARK: - OCF Parent Item

class OCFParentItem: HierarchicalItem, ObservableObject {
    let id: String
    let ocfFile: MediaFileInfo
    let linkedSegments: [LinkedSegment]
    let blankRushStatus: BlankRushStatus
    
    init(ocfFile: MediaFileInfo, linkedSegments: [LinkedSegment], blankRushStatus: BlankRushStatus) {
        self.id = ocfFile.fileName
        self.ocfFile = ocfFile
        self.linkedSegments = linkedSegments
        self.blankRushStatus = blankRushStatus
    }
    
    var displayName: String {
        ocfFile.fileName
    }
    
    var children: [HierarchicalItem]? {
        linkedSegments.map { SegmentChildItem(segment: $0.segment, linkConfidence: $0.linkConfidence) }
    }
    
    var statusIcon: String {
        blankRushStatus.statusIcon
    }
    
    var metadata: String {
        var parts: [String] = []
        
        if let resolution = ocfFile.displayResolution ?? ocfFile.resolution {
            parts.append("\(Int(resolution.width))x\(Int(resolution.height))")
        }
        
        parts.append(ocfFile.frameRateDescription)
        
        if let reel = ocfFile.reelName {
            parts.append("Reel: \(reel)")
        }
        
        return parts.joined(separator: " • ")
    }
    
    var timecodeRange: String {
        guard let startTC = ocfFile.sourceTimecode,
              let frameRate = ocfFile.frameRate,
              let frameCount = ocfFile.durationInFrames else {
            return "Unknown"
        }
        
        // Calculate end timecode using SMPTE
        let smpte = SMPTE(fps: Double(frameRate), dropFrame: ocfFile.isDropFrame ?? false)
        
        do {
            let startFrames = try smpte.getFrames(tc: startTC)
            let endFrames = startFrames + frameCount
            let endTC = smpte.getTC(frames: endFrames)
            
            return "\(startTC) → \(endTC)"
        } catch {
            return startTC
        }
    }
}

// MARK: - Segment Child Item

class SegmentChildItem: HierarchicalItem, ObservableObject {
    let id: String
    let segment: MediaFileInfo
    let linkConfidence: LinkConfidence
    
    init(segment: MediaFileInfo, linkConfidence: LinkConfidence) {
        self.id = segment.fileName
        self.segment = segment
        self.linkConfidence = linkConfidence
    }
    
    var displayName: String {
        segment.fileName
    }
    
    var children: [HierarchicalItem]? {
        nil // Segments don't have children
    }
    
    var statusIcon: String {
        switch linkConfidence {
        case .high: return "🟢"
        case .medium: return "🟡" 
        case .low, .manual: return "🔴"
        }
    }
    
    var metadata: String {
        var parts: [String] = []
        
        if let resolution = segment.displayResolution ?? segment.resolution {
            parts.append("\(Int(resolution.width))x\(Int(resolution.height))")
        }
        
        parts.append(segment.frameRateDescription)
        parts.append("Confidence: \(linkConfidence.rawValue)")
        
        return parts.joined(separator: " • ")
    }
    
    var timecodeRange: String {
        guard let startTC = segment.sourceTimecode,
              let frameRate = segment.frameRate,
              let frameCount = segment.durationInFrames else {
            return "Unknown"
        }
        
        // Calculate end timecode using SMPTE
        let smpte = SMPTE(fps: Double(frameRate), dropFrame: segment.isDropFrame ?? false)
        
        do {
            let startFrames = try smpte.getFrames(tc: startTC)
            let endFrames = startFrames + frameCount
            let endTC = smpte.getTC(frames: endFrames)
            
            return "\(startTC) → \(endTC)"
        } catch {
            return startTC
        }
    }
}

// MARK: - Project Hierarchy Builder

class ProjectHierarchy: ObservableObject {
    @Published var items: [HierarchicalItem] = []
    
    func updateFromProject(_ project: Project) {
        guard let linkingResult = project.linkingResult else {
            items = []
            return
        }
        
        items = linkingResult.ocfParents.compactMap { parent in
            guard parent.hasChildren else { return nil }
            
            let blankRushStatus = project.blankRushStatus[parent.ocf.fileName] ?? .notCreated
            
            return OCFParentItem(
                ocfFile: parent.ocf,
                linkedSegments: parent.children,
                blankRushStatus: blankRushStatus
            )
        }
    }
}

// MARK: - UI Helpers

extension HierarchicalItem {
    var isExpandable: Bool {
        children?.isEmpty == false
    }
    
    var childCount: Int {
        children?.count ?? 0
    }
}

// MARK: - Type-Erased Wrapper for SwiftUI

struct AnyHierarchicalItem: HierarchicalItem {
    let id: String
    let displayName: String
    let children: [HierarchicalItem]?
    let statusIcon: String
    let metadata: String
    let timecodeRange: String
    
    private let _item: any HierarchicalItem
    
    init<T: HierarchicalItem>(_ item: T) {
        self._item = item
        self.id = item.id
        self.displayName = item.displayName
        self.children = item.children
        self.statusIcon = item.statusIcon
        self.metadata = item.metadata
        self.timecodeRange = item.timecodeRange
    }
}