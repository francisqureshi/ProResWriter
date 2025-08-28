//
//  pairingProcess.swift
//  ProResWriter
//
//  Created by mac10 on 15/08/2025.
//

import Foundation

// MARK: - Parent-Child Linking Data Structures

public struct ChildSegment {
    public let segment: MediaFileInfo
    public let linkConfidence: LinkConfidence
    public let linkMethod: String           // "filename", "metadata", "manual"
    
    public init(segment: MediaFileInfo, linkConfidence: LinkConfidence, linkMethod: String) {
        self.segment = segment
        self.linkConfidence = linkConfidence
        self.linkMethod = linkMethod
    }
}

public struct OCFParent {
    public let ocf: MediaFileInfo
    public let children: [ChildSegment]
    
    public var childCount: Int {
        return children.count
    }
    
    public var hasChildren: Bool {
        return !children.isEmpty
    }
    
    public init(ocf: MediaFileInfo, children: [ChildSegment]) {
        self.ocf = ocf
        self.children = children
    }
}

public enum LinkConfidence {
    case high       // OCF filename contained in segment filename + tech specs
    case medium     // Good technical specs match (resolution + fps)
    case low        // Partial match or fallback
    case none       // No match found
}

public struct LinkingResult {
    public let ocfParents: [OCFParent]
    public let unmatchedSegments: [MediaFileInfo]
    public let unmatchedOCFs: [MediaFileInfo]
    
    public init(ocfParents: [OCFParent], unmatchedSegments: [MediaFileInfo], unmatchedOCFs: [MediaFileInfo]) {
        self.ocfParents = ocfParents
        self.unmatchedSegments = unmatchedSegments
        self.unmatchedOCFs = unmatchedOCFs
    }
    
    public var totalLinkedSegments: Int {
        return ocfParents.reduce(0) { $0 + $1.childCount }
    }
    
    public var totalSegments: Int {
        return totalLinkedSegments + unmatchedSegments.count
    }
    
    public var successRate: Double {
        guard totalSegments > 0 else { return 0.0 }
        return Double(totalLinkedSegments) / Double(totalSegments)
    }
    
    public var summary: String {
        let parentCount = ocfParents.filter { $0.hasChildren }.count
        return "\(parentCount) OCF parents with \(totalLinkedSegments) child segments (\(Int(successRate * 100))% success)"
    }
}

// MARK: - Parent-Child Linking Engine

public class SegmentOCFLinker {
    
    public init() {}
    
    public func linkSegments(_ segments: [MediaFileInfo], withOCFParents ocfs: [MediaFileInfo]) -> LinkingResult {
        print("🔗 Linking \(segments.count) segments with \(ocfs.count) OCF parent files...")
        
        // Dictionary to group children by OCF parent (using full path as unique key)
        var ocfToChildren: [String: [ChildSegment]] = [:]
        var unmatchedSegments: [MediaFileInfo] = []
        var usedOCFs: Set<String> = []
        
        // Initialize dictionary with empty arrays for all OCFs (using full path as key)
        for ocf in ocfs {
            ocfToChildren[ocf.url.path] = []
        }
        
        // Link each segment to its best parent OCF
        for segment in segments {
            if let (matchedOCF, confidence, method) = findBestMatch(for: segment, in: ocfs) {
                let childSegment = ChildSegment(
                    segment: segment,
                    linkConfidence: confidence,
                    linkMethod: method
                )
                
                ocfToChildren[matchedOCF.url.path]?.append(childSegment)
                usedOCFs.insert(matchedOCF.fileName)
                
                print("  ✅ \(segment.fileName) → \(matchedOCF.fileName) (\(confidence), \(method))")
            } else {
                unmatchedSegments.append(segment)
                print("  ❌ \(segment.fileName) → No parent OCF found")
            }
        }
        
        // Build OCFParent structures
        var ocfParents: [OCFParent] = []
        for ocf in ocfs {
            let children = ocfToChildren[ocf.url.path] ?? []
            let parent = OCFParent(ocf: ocf, children: children)
            ocfParents.append(parent)
        }
        
        // Calculate which OCF files were never used
        let unmatchedOCFs = ocfs.filter { !usedOCFs.contains($0.fileName) }
        
        let result = LinkingResult(
            ocfParents: ocfParents,
            unmatchedSegments: unmatchedSegments,
            unmatchedOCFs: unmatchedOCFs
        )
        
        print("🔗 Linking complete: \(result.summary)")
        
        return result
    }
    
    private func findBestMatch(for segment: MediaFileInfo, in ocfs: [MediaFileInfo]) -> (MediaFileInfo, LinkConfidence, String)? {
        var bestMatch: (MediaFileInfo, LinkConfidence, String)? = nil
        var bestScore = 0
        
        // Find the OCF with the highest matching score
        for ocf in ocfs {
            let score = calculateMatchScore(segment: segment, ocf: ocf)
            
            if score.total > bestScore {
                bestScore = score.total
                
                // Determine confidence based on score and filename match
                let confidence: LinkConfidence
                if score.total >= 4 && score.description.contains("filename_contains") {
                    confidence = .high  // OCF name in segment + tech specs
                } else if score.total >= 2 {
                    confidence = .medium  // Good tech specs match
                } else if score.total >= 1 {
                    confidence = .low     // Partial match
                } else {
                    confidence = .none
                }
                
                bestMatch = (ocf, confidence, score.description)
            }
        }
        
        // If no scoring match, try filename-based fallback
        if bestScore == 0, let baseFileName = extractBaseFileName(from: segment.fileName) {
            for ocf in ocfs {
                if ocf.fileName.lowercased().contains(baseFileName.lowercased()) {
                    return (ocf, .low, "filename_contains")
                }
            }
        }
        
        // Only return matches with confidence .low or higher
        if let match = bestMatch, match.1 != .none {
            return match
        }
        
        return nil
    }
    
    private func calculateMatchScore(segment: MediaFileInfo, ocf: MediaFileInfo) -> (total: Int, description: String) {
        var score = 0
        var matches: [String] = []
        
        // 1. Filename matching - OCF name should be contained in segment name
        let ocfBaseName = (ocf.fileName as NSString).deletingPathExtension
        let segmentFileName = segment.fileName.lowercased()
        let ocfFileName = ocfBaseName.lowercased()
        
        if segmentFileName.contains(ocfFileName) {
            score += 3  // High weight - OCF name found in segment name
            matches.append("filename_contains")
        } else if let segmentBase = extractBaseFileName(from: segment.fileName) {
            // Fallback: try base name comparison
            if ocfFileName.contains(segmentBase.lowercased()) {
                score += 1  // Lower weight for partial match
                matches.append("filename_partial")
            }
        }
        
        // 2. Resolution match (using effective display resolution)
        if let segmentRes = segment.effectiveDisplayResolution,
           let ocfRes = ocf.effectiveDisplayResolution {
            let widthDiff = abs(segmentRes.width - ocfRes.width)
            let heightDiff = abs(segmentRes.height - ocfRes.height)
            
            if widthDiff <= 5 && heightDiff <= 5 { // Exact match
                score += 1
                matches.append("resolution")
            }
        }
        
        // 3. FPS match
        if let segmentFR = segment.frameRate, let ocfFR = ocf.frameRate {
            if abs(segmentFR - ocfFR) <= 0.1 {
                score += 1
                matches.append("fps")
            }
        }
        
        // 4. Source Timecode range match - entire segment should fall within OCF range
        if let segmentStartTC = segment.sourceTimecode,
           let segmentEndTC = segment.endTimecode,
           let ocfStartTC = ocf.sourceTimecode,
           let ocfEndTC = ocf.endTimecode,
           let segmentFR = segment.frameRate,
           let ocfFR = ocf.frameRate,
           abs(segmentFR - ocfFR) <= 0.1 { // Only compare if frame rates match
            
            if isSegmentInOCFRange(segmentStartTimecode: segmentStartTC,
                                 segmentEndTimecode: segmentEndTC,
                                 ocfStartTimecode: ocfStartTC, 
                                 ocfEndTimecode: ocfEndTC, 
                                 frameRate: segmentFR,
                                 segmentDropFrame: segment.isDropFrame,
                                 ocfDropFrame: ocf.isDropFrame) {
                score += 1
                matches.append("timecode_range")
            }
        }
        
        // 5. Reel Name match
        if let segmentReel = segment.reelName, let ocfReel = ocf.reelName {
            if segmentReel.lowercased() == ocfReel.lowercased() {
                score += 1
                matches.append("reel")
            }
        }
        
        let description = matches.isEmpty ? "no_match" : matches.joined(separator: "+")
        return (score, description)
    }
    
    private func extractBaseFileName(from fileName: String) -> String? {
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        
        // Common segment patterns to remove
        let patterns = [
            "_s\\d+$",           // _s001, _s002, etc.
            "_S\\d+$",           // _S001, _S002, etc.
            " S\\d+$",           // S001, S002, etc.
            "_seg\\d+$",         // _seg001, _seg002
            "_segment\\d+$",     // _segment001
            "\\s+S\\d+\\s*$"     // " S10 " at end
        ]
        
        var baseName = nameWithoutExtension
        for pattern in patterns {
            baseName = baseName.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespaces)
        }
        
        return baseName.isEmpty ? nil : baseName
    }
    
    private func technicalSpecsMatch(segment: MediaFileInfo, ocf: MediaFileInfo) -> Bool {
        // Frame rate match (within tolerance)
        if let segmentFR = segment.frameRate, let ocfFR = ocf.frameRate {
            if abs(segmentFR - ocfFR) > 0.1 {
                return false
            }
        }
        
        // Resolution match (use effective resolution for sensor cropping)
        if let segmentRes = segment.effectiveDisplayResolution,
           let ocfRes = ocf.effectiveDisplayResolution {
            let widthDiff = abs(segmentRes.width - ocfRes.width)
            let heightDiff = abs(segmentRes.height - ocfRes.height)
            
            // Allow some tolerance for resolution differences
            if widthDiff > 10 || heightDiff > 10 {
                return false
            }
        }
        
        return true
    }
    
    private func isSegmentInOCFRange(segmentStartTimecode: String, segmentEndTimecode: String, ocfStartTimecode: String, ocfEndTimecode: String, frameRate: Float, segmentDropFrame: Bool? = nil, ocfDropFrame: Bool? = nil) -> Bool {
        // Use SMPTE library for professional timecode handling
        // Prefer the detected drop frame information, fall back to separator detection
        let isDropFrame = segmentDropFrame ?? ocfDropFrame ?? 
                         (segmentStartTimecode.contains(";") || segmentEndTimecode.contains(";") || 
                          ocfStartTimecode.contains(";") || ocfEndTimecode.contains(";"))
        
        let smpte = SMPTE(fps: Double(frameRate), dropFrame: isDropFrame)
        
        do {
            // Convert all timecodes to frame numbers using SMPTE library
            let segmentStartFrame = try smpte.getFrames(tc: segmentStartTimecode)
            let segmentEndFrame = try smpte.getFrames(tc: segmentEndTimecode)
            let ocfStartFrame = try smpte.getFrames(tc: ocfStartTimecode)
            let ocfEndFrame = try smpte.getFrames(tc: ocfEndTimecode)
            
            // Check if entire segment duration falls within OCF range
            let segmentStartInRange = segmentStartFrame >= ocfStartFrame && segmentStartFrame <= ocfEndFrame
            let segmentEndInRange = segmentEndFrame >= ocfStartFrame && segmentEndFrame <= ocfEndFrame
            let entireSegmentInRange = segmentStartInRange && segmentEndInRange
            
            if entireSegmentInRange {
                let dropFrameInfo = isDropFrame ? " (drop frame)" : ""
                print("    ✅ Segment range \(segmentStartTimecode)-\(segmentEndTimecode) (frames \(segmentStartFrame)-\(segmentEndFrame)) within OCF range \(ocfStartTimecode)-\(ocfEndTimecode) (frames \(ocfStartFrame)-\(ocfEndFrame))\(dropFrameInfo)")
            } else {
                let dropFrameInfo = isDropFrame ? " (drop frame)" : ""
                print("    ❌ Segment range \(segmentStartTimecode)-\(segmentEndTimecode) (frames \(segmentStartFrame)-\(segmentEndFrame)) NOT within OCF range \(ocfStartTimecode)-\(ocfEndTimecode) (frames \(ocfStartFrame)-\(ocfEndFrame))\(dropFrameInfo)")
            }
            
            return entireSegmentInRange
            
        } catch let error as SMPTEError {
            print("    ⚠️ SMPTE timecode error: \(error.localizedDescription)")
            return false
        } catch {
            print("    ⚠️ Unexpected timecode error: \(error)")
            return false
        }
    }
}
