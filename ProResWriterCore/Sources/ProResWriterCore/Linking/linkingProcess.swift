//
//  pairingProcess.swift
//  ProResWriter
//
//  Created by mac10 on 15/08/2025.
//

import Foundation

// MARK: - Parent-Child Linking Data Structures

public struct LinkedSegment: Codable {
    public let segment: MediaFileInfo
    public let linkConfidence: LinkConfidence
    public let linkMethod: String           // "filename", "metadata", "manual"
    
    public init(segment: MediaFileInfo, linkConfidence: LinkConfidence, linkMethod: String) {
        self.segment = segment
        self.linkConfidence = linkConfidence
        self.linkMethod = linkMethod
    }
}

public struct OCFParent: Codable {
    public let ocf: MediaFileInfo
    public let children: [LinkedSegment]
    
    public var childCount: Int {
        return children.count
    }
    
    public var hasChildren: Bool {
        return !children.isEmpty
    }
    
    public init(ocf: MediaFileInfo, children: [LinkedSegment]) {
        self.ocf = ocf
        self.children = children
    }
}

public enum LinkConfidence: Codable {
    case high       // OCF filename contained in segment filename + tech specs
    case medium     // Good technical specs match (resolution + fps)
    case low        // Partial match or fallback
    case none       // No match found
}

public struct LinkingResult: Codable {
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
        var ocfToChildren: [String: [LinkedSegment]] = [:]
        var unmatchedSegments: [MediaFileInfo] = []
        var usedOCFs: Set<String> = []
        
        // Initialize dictionary with empty arrays for all OCFs (using full path as key)
        for ocf in ocfs {
            ocfToChildren[ocf.url.path] = []
        }
        
        // Link each segment to its best parent OCF
        for segment in segments {
            if let (matchedOCF, confidence, method) = findBestMatch(for: segment, in: ocfs) {
                let linkedSegment = LinkedSegment(
                    segment: segment,
                    linkConfidence: confidence,
                    linkMethod: method
                )
                
                ocfToChildren[matchedOCF.url.path]?.append(linkedSegment)
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
        var validMatches: [(MediaFileInfo, LinkConfidence, String)] = []
        
        // Try to match with each OCF using strict validation
        for ocf in ocfs {
            if let matchResult = validateStrictMatch(segment: segment, ocf: ocf) {
                validMatches.append(matchResult)
            }
        }
        
        // Return the best match if we have any
        // Prefer high confidence, then medium, then low
        if let highConfMatch = validMatches.first(where: { $0.1 == .high }) {
            return highConfMatch
        } else if let medConfMatch = validMatches.first(where: { $0.1 == .medium }) {
            return medConfMatch
        } else if let lowConfMatch = validMatches.first(where: { $0.1 == .low }) {
            return lowConfMatch
        }
        
        return nil
    }
    
    private func validateStrictMatch(segment: MediaFileInfo, ocf: MediaFileInfo) -> (MediaFileInfo, LinkConfidence, String)? {
        var matchCriteria: [String] = []
        
        // STEP 1: Hard Requirements - Resolution & FPS must match
        // Check resolution (using effective display resolution)
        guard let segmentRes = segment.effectiveDisplayResolution,
              let ocfRes = ocf.effectiveDisplayResolution else {
            return nil // No resolution info = no match
        }
        
        // Resolution must match EXACTLY
        if segmentRes.width != ocfRes.width || segmentRes.height != ocfRes.height {
            // Resolution mismatch = instant disqualification
            return nil
        }
        matchCriteria.append("resolution")
        
        // Check FPS
        guard let segmentFR = segment.frameRate, 
              let ocfFR = ocf.frameRate else {
            return nil // No frame rate info = no match
        }
        
        if abs(segmentFR - ocfFR) > 0.1 {
            // FPS mismatch = instant disqualification
            return nil
        }
        matchCriteria.append("fps")
        
        // STEP 2: Detect if this is a consumer camera
        let isConsumerCamera = isConsumerCameraOCF(ocf)
        
        // STEP 3: Check filename matching
        let ocfBaseName = (ocf.fileName as NSString).deletingPathExtension
        let segmentFileName = segment.fileName.lowercased()
        let ocfFileName = ocfBaseName.lowercased()
        let hasFilenameMatch = segmentFileName.contains(ocfFileName)
        
        if hasFilenameMatch {
            matchCriteria.append("filename_contains")
        }
        
        // STEP 4: Apply different rules based on camera type
        if isConsumerCamera {
            // Consumer camera (00:00:00:00) - STRICTEST verification
            
            // Must have filename match (even for VFX shots)
            if !hasFilenameMatch {
                return nil
            }
            
            // Additional validation: Check reel name if available
            if let segmentReel = segment.reelName, 
               let ocfReel = ocf.reelName,
               segmentReel.lowercased() == ocfReel.lowercased() {
                matchCriteria.append("reel")
            }
            
            // Additional validation: Segment can't be longer than OCF
            if let segmentDuration = segment.durationInFrames,
               let ocfDuration = ocf.durationInFrames,
               segmentDuration > ocfDuration {
                // Segment longer than OCF = not possible
                return nil
            }
            
            // Consumer camera matches always get LOW confidence as a warning
            matchCriteria.append("consumer_camera")
            let description = matchCriteria.joined(separator: "+")
            return (ocf, .low, description)
            
        } else {
            // Professional camera - check timecode
            
            // Validate timecode range
            if let segmentStartTC = segment.sourceTimecode,
               let segmentEndTC = segment.endTimecode,
               let ocfStartTC = ocf.sourceTimecode,
               let ocfEndTC = ocf.endTimecode {
                
                let inRange = isSegmentInOCFRange(
                    segmentStartTimecode: segmentStartTC,
                    segmentEndTimecode: segmentEndTC,
                    ocfStartTimecode: ocfStartTC,
                    ocfEndTimecode: ocfEndTC,
                    frameRate: segmentFR,
                    segmentDropFrame: segment.isDropFrame,
                    ocfDropFrame: ocf.isDropFrame
                )
                
                if !inRange {
                    // Timecode not in range = no match for professional cameras
                    return nil
                }
                matchCriteria.append("timecode_range")
            } else {
                // No timecode for professional camera = no match
                return nil
            }
            
            // Check if this is a VFX shot
            let isVFXShot = segment.isVFX == true
            
            // For professional cameras: require filename match unless VFX
            if !isVFXShot && !hasFilenameMatch {
                return nil
            }
            
            if isVFXShot && !hasFilenameMatch {
                matchCriteria.append("vfx_exemption")
            }
            
            // Check reel name for additional confidence
            if let segmentReel = segment.reelName,
               let ocfReel = ocf.reelName,
               segmentReel.lowercased() == ocfReel.lowercased() {
                matchCriteria.append("reel")
            }
            
            // Determine confidence for professional camera
            let confidence: LinkConfidence
            if hasFilenameMatch && matchCriteria.contains("timecode_range") {
                confidence = .high // Has everything
            } else if matchCriteria.contains("timecode_range") && isVFXShot {
                confidence = .medium // VFX with valid timecode
            } else {
                confidence = .low // Shouldn't happen with our strict rules
            }
            
            let description = matchCriteria.joined(separator: "+")
            return (ocf, confidence, description)
        }
    }
    
    private func isConsumerCameraOCF(_ ocf: MediaFileInfo) -> Bool {
        // Check if start timecode is 00:00:00:00 or 00:00:00;00
        if let startTC = ocf.sourceTimecode {
            let cleanTC = startTC.replacingOccurrences(of: ";", with: ":")
            return cleanTC == "00:00:00:00"
        }
        return false
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
