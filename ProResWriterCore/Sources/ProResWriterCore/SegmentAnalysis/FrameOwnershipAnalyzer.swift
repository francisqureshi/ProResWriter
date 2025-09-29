import Foundation
import AVFoundation
import SwiftFFmpeg

// MARK: - Core Data Structures

/// Represents ownership of a single frame in the timeline
public struct FrameOwnership {
    /// The frame number in the output timeline (0-based)
    public let frameNumber: Int

    /// The segment that owns this frame
    public let owningSegment: FFmpegGradedSegment

    /// Which frame from the segment to use (0-based, relative to segment start)
    public let sourceFrame: Int

    /// Priority level (higher wins: VFX = 1000, grades by index 0-999)
    public let priority: Int

    /// Debug information about why this segment won
    public let reason: String
}

/// A contiguous range of frames from a single segment
public struct ProcessingRange {
    /// Start frame in the output timeline (0-based, inclusive)
    public let startFrame: Int

    /// End frame in the output timeline (0-based, exclusive)
    public let endFrame: Int

    /// The segment providing frames for this range
    public let segment: FFmpegGradedSegment

    /// Offset into the segment where to start reading (0-based)
    public let segmentStartOffset: Int

    /// Number of frames to copy from the segment
    public var frameCount: Int {
        return endFrame - startFrame
    }

    /// Description for debugging
    public var description: String {
        let segmentName = segment.url.lastPathComponent
        return "[\(startFrame)-\(endFrame)): \(segmentName) @ offset \(segmentStartOffset) (\(frameCount) frames)"
    }
}

/// Complete processing plan with all frame assignments
public struct ProcessingPlan {
    /// Consolidated ranges for efficient copying
    public let consolidatedRanges: [ProcessingRange]

    /// Warnings about overlaps for user notification
    public let overlapWarnings: [String]

    /// Statistics about the analysis
    public let statistics: AnalysisStatistics

    /// Optional detailed frame ownership map for debugging
    public let frameOwnerships: [FrameOwnership]?

    /// Timeline visualization data for UI preview
    public let visualizationData: TimelineVisualization?
}

/// Statistics about the frame ownership analysis
public struct AnalysisStatistics: Codable {
    public let totalFrames: Int
    public let segmentCount: Int
    public let vfxSegmentCount: Int
    public let overlapCount: Int
    public let framesOverwritten: Int
    public let vfxFrames: Int
    public let gradeFrames: Int
}

/// Data for UI timeline visualization
public struct TimelineVisualization {
    public struct SegmentPlacement {
        public let segment: FFmpegGradedSegment
        public let startFrame: Int
        public let endFrame: Int
        public let isVFX: Bool
        public let overwrittenRanges: [(start: Int, end: Int)]
        public let color: String // Hex color for UI

        public init(segment: FFmpegGradedSegment, startFrame: Int, endFrame: Int, isVFX: Bool, overwrittenRanges: [(start: Int, end: Int)], color: String) {
            self.segment = segment
            self.startFrame = startFrame
            self.endFrame = endFrame
            self.isVFX = isVFX
            self.overwrittenRanges = overwrittenRanges
            self.color = color
        }
    }

    public let totalFrames: Int
    public let placements: [SegmentPlacement]
    public let conflictZones: [(start: Int, end: Int, description: String)]

    public init(totalFrames: Int, placements: [SegmentPlacement], conflictZones: [(start: Int, end: Int, description: String)]) {
        self.totalFrames = totalFrames
        self.placements = placements
        self.conflictZones = conflictZones
    }
}

// MARK: - Frame Ownership Analyzer

public class FrameOwnershipAnalyzer {

    private let baseProperties: VideoStreamProperties
    private let segments: [FFmpegGradedSegment]
    private let totalFrames: Int
    private let verbose: Bool

    public init(baseProperties: VideoStreamProperties, segments: [FFmpegGradedSegment], totalFrames: Int, verbose: Bool = false) {
        self.baseProperties = baseProperties
        self.segments = segments
        self.totalFrames = totalFrames
        self.verbose = verbose
    }

    // MARK: - Public API

    /// Analyze all segments and generate a processing plan
    public func analyze() throws -> ProcessingPlan {
        guard !segments.isEmpty else {
            // No segments, return empty plan
            return ProcessingPlan(
                consolidatedRanges: [],
                overlapWarnings: [],
                statistics: AnalysisStatistics(
                    totalFrames: totalFrames,
                    segmentCount: 0,
                    vfxSegmentCount: 0,
                    overlapCount: 0,
                    framesOverwritten: 0,
                    vfxFrames: 0,
                    gradeFrames: 0
                ),
                frameOwnerships: nil,
                visualizationData: nil
            )
        }

        // Step 1: Calculate frame positions for all segments
        let positionedSegments = try calculateSegmentPositions()

        // Step 2: Build frame ownership map
        let (ownershipMap, warnings) = buildFrameOwnershipMap(from: positionedSegments)

        // Step 3: Consolidate into processing ranges
        let consolidatedRanges = consolidateToRanges(from: ownershipMap)

        // Step 4: Generate statistics
        let statistics = generateStatistics(
            from: ownershipMap,
            positionedSegments: positionedSegments
        )

        // Step 5: Generate visualization data if requested
        let visualizationData = verbose ? generateVisualizationData(
            from: positionedSegments,
            ownershipMap: ownershipMap
        ) : nil

        return ProcessingPlan(
            consolidatedRanges: consolidatedRanges,
            overlapWarnings: warnings,
            statistics: statistics,
            frameOwnerships: verbose ? ownershipMap : nil,
            visualizationData: visualizationData
        )
    }

    // MARK: - Private Implementation

    private struct PositionedSegment {
        let segment: FFmpegGradedSegment
        let startFrame: Int
        let endFrame: Int  // Exclusive
        let priority: Int
        let isVFX: Bool

        var frameCount: Int {
            return endFrame - startFrame
        }
    }

    /// Calculate exact frame positions for all segments using SMPTE timecode or time-based fallback
    private func calculateSegmentPositions() throws -> [PositionedSegment] {
        var positionedSegments: [PositionedSegment] = []

        // Separate VFX and regular segments
        let vfxSegments = segments.filter { $0.isVFXShot }
        let regularSegments = segments.filter { !$0.isVFXShot }

        // Process regular segments first (priority by order)
        for (index, segment) in regularSegments.enumerated() {
            let position = try calculateSegmentFramePosition(segment)
            positionedSegments.append(PositionedSegment(
                segment: segment,
                startFrame: position.start,
                endFrame: position.end,
                priority: index,  // Later segments have higher priority
                isVFX: false
            ))
        }

        // Process VFX segments with maximum priority
        for segment in vfxSegments {
            let position = try calculateSegmentFramePosition(segment)
            positionedSegments.append(PositionedSegment(
                segment: segment,
                startFrame: position.start,
                endFrame: position.end,
                priority: 1000,  // VFX always wins
                isVFX: true
            ))
        }

        return positionedSegments
    }

    /// Calculate frame position for a single segment
    private func calculateSegmentFramePosition(_ segment: FFmpegGradedSegment) throws -> (start: Int, end: Int) {
        var startFrame: Int
        var endFrame: Int

        // Try SMPTE timecode calculation first (most accurate)
        if let baseTimecode = baseProperties.timecode,
           let segmentTimecode = segment.sourceTimecode,
           let segmentFrameRate = segment.frameRate {

            let smpte = SMPTE(fps: Double(segmentFrameRate), dropFrame: segment.isDropFrame ?? false)

            // Calculate base timeline start in frames
            let baseFrames = try smpte.getFrames(tc: baseTimecode)

            // Calculate segment start in frames
            let segmentStartFrames = try smpte.getFrames(tc: segmentTimecode)
            startFrame = segmentStartFrames - baseFrames

            // Calculate segment end using duration in frames
            // Segment must have exact AVRational from import/linking stage
            guard let segmentFrameRateRational = segment.frameRateRational else {
                throw FrameOwnershipError.missingRationalFrameRate(segment: segment.url.lastPathComponent)
            }
            let durationFrames = convertTimeToFrame(seconds: segment.duration.seconds, frameRate: segmentFrameRateRational)
            endFrame = startFrame + durationFrames
        } else {
            // Fallback to time-based calculation
            startFrame = convertTimeToFrame(seconds: segment.startTime.seconds, frameRate: baseProperties.frameRate)
            let durationFrames = convertTimeToFrame(seconds: segment.duration.seconds, frameRate: baseProperties.frameRate)
            endFrame = startFrame + durationFrames
        }

        // Clamp to timeline boundaries
        startFrame = max(0, startFrame)
        endFrame = min(totalFrames, endFrame)

        return (startFrame, endFrame)
    }

    /// Build frame ownership map considering overlaps and priorities
    private func buildFrameOwnershipMap(from positionedSegments: [PositionedSegment]) -> ([FrameOwnership], [String]) {
        var ownershipMap: [Int: FrameOwnership] = [:]
        var warnings: [String] = []

        // Sort segments by priority (lower priority first, so higher priority overwrites)
        let sortedSegments = positionedSegments.sorted { $0.priority < $1.priority }

        for positioned in sortedSegments {
            var overwrites = 0

            for frameIdx in positioned.startFrame..<positioned.endFrame {
                let sourceFrame = frameIdx - positioned.startFrame

                // Check if this frame is already owned
                if let existing = ownershipMap[frameIdx] {
                    // Generate warning if appropriate
                    if positioned.isVFX {
                        if existing.priority == 1000 {
                            // VFX overwriting VFX
                            warnings.append("VFX segment '\(positioned.segment.url.lastPathComponent)' overlaps with another VFX segment at frame \(frameIdx)")
                        }
                        // VFX always wins, no warning for overwriting grade
                    } else if existing.priority == 1000 {
                        // Grade trying to overwrite VFX - skip this frame
                        continue
                    } else {
                        // Grade overwriting grade - this is expected behavior
                        overwrites += 1
                    }
                }

                // Assign ownership
                ownershipMap[frameIdx] = FrameOwnership(
                    frameNumber: frameIdx,
                    owningSegment: positioned.segment,
                    sourceFrame: sourceFrame,
                    priority: positioned.priority,
                    reason: positioned.isVFX ? "VFX priority" : "Grade segment (priority: \(positioned.priority))"
                )
            }

            if overwrites > 0 && verbose {
                warnings.append("Segment '\(positioned.segment.url.lastPathComponent)' overwrote \(overwrites) frames from earlier segments")
            }
        }

        // Convert map to sorted array
        let sortedOwnerships = ownershipMap.keys.sorted().compactMap { ownershipMap[$0] }

        return (sortedOwnerships, warnings)
    }

    /// Consolidate frame ownerships into contiguous processing ranges
    private func consolidateToRanges(from ownerships: [FrameOwnership]) -> [ProcessingRange] {
        guard !ownerships.isEmpty else { return [] }

        var ranges: [ProcessingRange] = []
        var currentRange: ProcessingRange?

        for ownership in ownerships {
            if let range = currentRange {
                // Check if this frame continues the current range
                let expectedSourceFrame = ownership.frameNumber - range.startFrame + range.segmentStartOffset

                if ownership.owningSegment.url == range.segment.url &&
                   ownership.sourceFrame == expectedSourceFrame {
                    // Continue current range (update by creating new with extended end)
                    currentRange = ProcessingRange(
                        startFrame: range.startFrame,
                        endFrame: ownership.frameNumber + 1,
                        segment: range.segment,
                        segmentStartOffset: range.segmentStartOffset
                    )
                } else {
                    // Different segment or non-contiguous frames - save current and start new
                    ranges.append(range)
                    currentRange = ProcessingRange(
                        startFrame: ownership.frameNumber,
                        endFrame: ownership.frameNumber + 1,
                        segment: ownership.owningSegment,
                        segmentStartOffset: ownership.sourceFrame
                    )
                }
            } else {
                // Start first range
                currentRange = ProcessingRange(
                    startFrame: ownership.frameNumber,
                    endFrame: ownership.frameNumber + 1,
                    segment: ownership.owningSegment,
                    segmentStartOffset: ownership.sourceFrame
                )
            }
        }

        // Add final range
        if let range = currentRange {
            ranges.append(range)
        }

        return ranges
    }

    /// Generate statistics about the analysis
    private func generateStatistics(
        from ownershipMap: [FrameOwnership],
        positionedSegments: [PositionedSegment]
    ) -> AnalysisStatistics {
        let vfxFrames = ownershipMap.filter { $0.priority == 1000 }.count
        let gradeFrames = ownershipMap.filter { $0.priority < 1000 }.count

        // Count overlaps
        var overlapCount = 0
        var totalOverwrittenFrames = 0

        for i in 0..<positionedSegments.count {
            for j in i+1..<positionedSegments.count {
                let seg1 = positionedSegments[i]
                let seg2 = positionedSegments[j]

                let overlapStart = max(seg1.startFrame, seg2.startFrame)
                let overlapEnd = min(seg1.endFrame, seg2.endFrame)

                if overlapStart < overlapEnd {
                    overlapCount += 1
                    totalOverwrittenFrames += (overlapEnd - overlapStart)
                }
            }
        }

        return AnalysisStatistics(
            totalFrames: totalFrames,
            segmentCount: segments.count,
            vfxSegmentCount: segments.filter { $0.isVFXShot }.count,
            overlapCount: overlapCount,
            framesOverwritten: totalOverwrittenFrames,
            vfxFrames: vfxFrames,
            gradeFrames: gradeFrames
        )
    }

    /// Generate visualization data for UI timeline preview
    private func generateVisualizationData(
        from positionedSegments: [PositionedSegment],
        ownershipMap: [FrameOwnership]
    ) -> TimelineVisualization {
        var placements: [TimelineVisualization.SegmentPlacement] = []
        var conflictZones: [(start: Int, end: Int, description: String)] = []

        // Create ownership lookup
        var frameOwners: [Int: FFmpegGradedSegment] = [:]
        for ownership in ownershipMap {
            frameOwners[ownership.frameNumber] = ownership.owningSegment
        }

        // Generate placements with overwritten ranges
        for positioned in positionedSegments {
            var overwrittenRanges: [(start: Int, end: Int)] = []
            var currentOverwriteStart: Int?

            for frame in positioned.startFrame..<positioned.endFrame {
                let isOwned = frameOwners[frame]?.url == positioned.segment.url

                if !isOwned {
                    if currentOverwriteStart == nil {
                        currentOverwriteStart = frame
                    }
                } else if let start = currentOverwriteStart {
                    overwrittenRanges.append((start, frame))
                    currentOverwriteStart = nil
                }
            }

            // Close any open overwrite range
            if let start = currentOverwriteStart {
                overwrittenRanges.append((start, positioned.endFrame))
            }

            let color = positioned.isVFX ? "#FF6B6B" : "#4DABF7" // Red for VFX, blue for grades

            placements.append(TimelineVisualization.SegmentPlacement(
                segment: positioned.segment,
                startFrame: positioned.startFrame,
                endFrame: positioned.endFrame,
                isVFX: positioned.isVFX,
                overwrittenRanges: overwrittenRanges,
                color: color
            ))
        }

        // Find conflict zones
        for i in 0..<positionedSegments.count {
            for j in i+1..<positionedSegments.count {
                let seg1 = positionedSegments[i]
                let seg2 = positionedSegments[j]

                let overlapStart = max(seg1.startFrame, seg2.startFrame)
                let overlapEnd = min(seg1.endFrame, seg2.endFrame)

                if overlapStart < overlapEnd {
                    let description = "\(seg1.segment.url.lastPathComponent) vs \(seg2.segment.url.lastPathComponent)"
                    conflictZones.append((overlapStart, overlapEnd, description))
                }
            }
        }

        return TimelineVisualization(
            totalFrames: totalFrames,
            placements: placements,
            conflictZones: conflictZones
        )
    }

    // MARK: - Helper Functions

    private func convertTimeToFrame(seconds: Double, frameRate: AVRational) -> Int {
        let fps = Double(frameRate.num) / Double(frameRate.den)
        return Int(round(seconds * fps))
    }
}

// MARK: - Frame Ownership Errors

enum FrameOwnershipError: Error {
    case missingRationalFrameRate(segment: String)

    var localizedDescription: String {
        switch self {
        case .missingRationalFrameRate(let segment):
            return "Segment '\(segment)' is missing exact AVRational frame rate from import/linking stage"
        }
    }
}