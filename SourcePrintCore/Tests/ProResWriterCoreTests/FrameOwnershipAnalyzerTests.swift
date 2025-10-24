import XCTest
import AVFoundation
import SwiftFFmpeg
@testable import SourcePrintCore

class FrameOwnershipAnalyzerTests: XCTestCase {

    // MARK: - Test Helpers

    private func createMockVideoStreamProperties(frameRate: (num: Int, den: Int) = (24000, 1001), duration: Double = 42.0, timecode: String? = "01:00:00:00") -> VideoStreamProperties {
        return VideoStreamProperties(
            width: 1920,
            height: 1080,
            frameRate: AVRational(num: Int32(frameRate.num), den: Int32(frameRate.den)),
            frameRateFloat: Float(frameRate.num) / Float(frameRate.den),
            duration: duration,
            timebase: AVRational(num: Int32(frameRate.den), den: Int32(frameRate.num)),
            timecode: timecode
        )
    }

    private func createMockSegment(
        name: String,
        startTime: Double,
        duration: Double,
        isVFX: Bool = false,
        sourceTimecode: String? = nil,
        frameRate: (num: Int, den: Int) = (24000, 1001)
    ) -> FFmpegGradedSegment {
        let url = URL(fileURLWithPath: "/test/\(name).mov")
        let fps = Float(frameRate.num) / Float(frameRate.den)

        return FFmpegGradedSegment(
            url: url,
            startTime: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            sourceStartTime: CMTime.zero,
            isVFXShot: isVFX,
            sourceTimecode: sourceTimecode,
            frameRate: fps,
            isDropFrame: false
        )
    }

    // MARK: - Basic Tests

    func testEmptySegments() throws {
        let baseProperties = createMockVideoStreamProperties()
        let analyzer = FrameOwnershipAnalyzer(baseProperties: baseProperties, segments: [], totalFrames: 1000, verbose: false)

        let plan = try analyzer.analyze()

        XCTAssertEqual(plan.consolidatedRanges.count, 0)
        XCTAssertEqual(plan.overlapWarnings.count, 0)
        XCTAssertEqual(plan.statistics.segmentCount, 0)
        XCTAssertEqual(plan.statistics.totalFrames, 1000)
    }

    func testSingleSegmentNoOverlap() throws {
        let baseProperties = createMockVideoStreamProperties()
        let segment = createMockSegment(
            name: "Seg1",
            startTime: 10.0,  // ~240 frames @ 23.976fps
            duration: 5.0,    // ~120 frames
            isVFX: false
        )

        let analyzer = FrameOwnershipAnalyzer(baseProperties: baseProperties, segments: [segment], totalFrames: 1000, verbose: true)
        let plan = try analyzer.analyze()

        XCTAssertEqual(plan.consolidatedRanges.count, 1)
        XCTAssertEqual(plan.consolidatedRanges[0].startFrame, 240, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[0].frameCount, 120, accuracy: 1)
        XCTAssertEqual(plan.overlapWarnings.count, 0)
        XCTAssertEqual(plan.statistics.gradeFrames, 120, accuracy: 1)
    }

    // MARK: - Grade Overlap Tests

    func testGradeSegmentOverlap_LaterWins() throws {
        let baseProperties = createMockVideoStreamProperties()

        // Seg1: frames 100-200
        let seg1 = createMockSegment(
            name: "Seg1",
            startTime: 4.17,  // ~100 frames
            duration: 4.17,   // ~100 frames
            isVFX: false
        )

        // Seg2: frames 150-250 (overlaps last 50 frames of Seg1)
        let seg2 = createMockSegment(
            name: "Seg2",
            startTime: 6.26,  // ~150 frames
            duration: 4.17,   // ~100 frames
            isVFX: false
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [seg1, seg2],  // Order matters - seg2 should win
            totalFrames: 1000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // Should have 2 ranges: Seg1[100-150], Seg2[150-250]
        XCTAssertEqual(plan.consolidatedRanges.count, 2)

        // First range: Seg1 frames 100-150
        XCTAssertEqual(plan.consolidatedRanges[0].segment.url.lastPathComponent, "Seg1.mov")
        XCTAssertEqual(plan.consolidatedRanges[0].startFrame, 100, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[0].frameCount, 50, accuracy: 1)

        // Second range: Seg2 frames 150-250
        XCTAssertEqual(plan.consolidatedRanges[1].segment.url.lastPathComponent, "Seg2.mov")
        XCTAssertEqual(plan.consolidatedRanges[1].startFrame, 150, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[1].frameCount, 100, accuracy: 1)

        // Check statistics
        XCTAssertEqual(plan.statistics.overlapCount, 1)
        XCTAssertEqual(plan.statistics.framesOverwritten, 50, accuracy: 1)
    }

    func testComplexGradeOverlap_ThreeSegments() throws {
        let baseProperties = createMockVideoStreamProperties()

        // Seg1: frames 100-300
        let seg1 = createMockSegment(
            name: "Seg1",
            startTime: 4.17,   // ~100 frames
            duration: 8.34,    // ~200 frames
            isVFX: false
        )

        // Seg2: frames 200-400 (overlaps last 100 frames of Seg1)
        let seg2 = createMockSegment(
            name: "Seg2",
            startTime: 8.34,   // ~200 frames
            duration: 8.34,    // ~200 frames
            isVFX: false
        )

        // Seg3: frames 250-350 (overlaps both Seg1 and Seg2)
        let seg3 = createMockSegment(
            name: "Seg3",
            startTime: 10.43,  // ~250 frames
            duration: 4.17,    // ~100 frames
            isVFX: false
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [seg1, seg2, seg3],  // Order: seg3 wins 250-350
            totalFrames: 1000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // Expected ranges: Seg1[100-200], Seg2[200-250], Seg3[250-350], Seg2[350-400]
        XCTAssertEqual(plan.consolidatedRanges.count, 4)

        // Check Seg3 owns frames 250-350
        let seg3Range = plan.consolidatedRanges.first { $0.segment.url.lastPathComponent == "Seg3.mov" }
        XCTAssertNotNil(seg3Range)
        XCTAssertEqual(seg3Range?.startFrame ?? 0, 250, accuracy: 1)
        XCTAssertEqual(seg3Range?.frameCount ?? 0, 100, accuracy: 1)
    }

    // MARK: - VFX Priority Tests

    func testVFXOverridesGrade() throws {
        let baseProperties = createMockVideoStreamProperties()

        // Grade segment: frames 100-300
        let gradeSeg = createMockSegment(
            name: "GradeSeg",
            startTime: 4.17,   // ~100 frames
            duration: 8.34,    // ~200 frames
            isVFX: false
        )

        // VFX segment: frames 150-175 (within grade segment)
        let vfxSeg = createMockSegment(
            name: "VFXSeg",
            startTime: 6.26,   // ~150 frames
            duration: 1.04,    // ~25 frames
            isVFX: true
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [gradeSeg, vfxSeg],
            totalFrames: 1000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // Should have 3 ranges: Grade[100-150], VFX[150-175], Grade[175-300]
        XCTAssertEqual(plan.consolidatedRanges.count, 3)

        // First range: Grade segment frames 100-150
        XCTAssertEqual(plan.consolidatedRanges[0].segment.url.lastPathComponent, "GradeSeg.mov")
        XCTAssertEqual(plan.consolidatedRanges[0].startFrame, 100, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[0].frameCount, 50, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[0].segmentStartOffset, 0)

        // Second range: VFX segment frames 150-175
        XCTAssertEqual(plan.consolidatedRanges[1].segment.url.lastPathComponent, "VFXSeg.mov")
        XCTAssertEqual(plan.consolidatedRanges[1].startFrame, 150, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[1].frameCount, 25, accuracy: 1)

        // Third range: Grade segment frames 175-300 (continues from frame 75 of grade)
        XCTAssertEqual(plan.consolidatedRanges[2].segment.url.lastPathComponent, "GradeSeg.mov")
        XCTAssertEqual(plan.consolidatedRanges[2].startFrame, 175, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[2].frameCount, 125, accuracy: 1)
        XCTAssertEqual(plan.consolidatedRanges[2].segmentStartOffset, 75) // Should start from frame 75 of grade segment
    }

    func testVFXNeverOverwritten() throws {
        let baseProperties = createMockVideoStreamProperties()

        // VFX segment: frames 150-175
        let vfxSeg = createMockSegment(
            name: "VFXSeg",
            startTime: 6.26,   // ~150 frames
            duration: 1.04,    // ~25 frames
            isVFX: true
        )

        // Later grade segment that would normally override: frames 100-300
        let gradeSeg = createMockSegment(
            name: "GradeSeg",
            startTime: 4.17,   // ~100 frames
            duration: 8.34,    // ~200 frames
            isVFX: false
        )

        // Test with grade after VFX in array (grade has higher index/priority)
        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [vfxSeg, gradeSeg],  // Grade comes after but VFX should still win
            totalFrames: 1000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // VFX should still own frames 150-175
        let vfxRange = plan.consolidatedRanges.first {
            $0.segment.url.lastPathComponent == "VFXSeg.mov" &&
            $0.startFrame >= 150 && $0.startFrame < 175
        }
        XCTAssertNotNil(vfxRange)
        XCTAssertEqual(vfxRange?.frameCount ?? 0, 25, accuracy: 1)

        // Check statistics
        XCTAssertEqual(plan.statistics.vfxFrames, 25, accuracy: 1)
    }

    func testMultipleVFXSegments() throws {
        let baseProperties = createMockVideoStreamProperties()

        // VFX1: frames 100-150
        let vfx1 = createMockSegment(
            name: "VFX1",
            startTime: 4.17,   // ~100 frames
            duration: 2.09,    // ~50 frames
            isVFX: true
        )

        // VFX2: frames 125-175 (overlaps with VFX1)
        let vfx2 = createMockSegment(
            name: "VFX2",
            startTime: 5.21,   // ~125 frames
            duration: 2.09,    // ~50 frames
            isVFX: true
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [vfx1, vfx2],
            totalFrames: 1000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // Both VFX segments should be in the output (though overlapping)
        // The second VFX wins the overlap
        XCTAssertTrue(plan.overlapWarnings.contains { $0.contains("VFX segment") && $0.contains("overlaps") })
        XCTAssertEqual(plan.statistics.vfxSegmentCount, 2)
    }

    // MARK: - Complex Scenario Tests

    func testRealWorldScenario() throws {
        let baseProperties = createMockVideoStreamProperties()

        // Grade1: frames 100-500
        let grade1 = createMockSegment(
            name: "Grade1",
            startTime: 4.17,    // ~100 frames
            duration: 16.68,    // ~400 frames
            isVFX: false
        )

        // VFX1: frames 200-250 (within Grade1)
        let vfx1 = createMockSegment(
            name: "VFX1",
            startTime: 8.34,    // ~200 frames
            duration: 2.09,     // ~50 frames
            isVFX: true
        )

        // Grade2: frames 300-700 (overlaps Grade1 and VFX1)
        let grade2 = createMockSegment(
            name: "Grade2",
            startTime: 12.51,   // ~300 frames
            duration: 16.68,    // ~400 frames
            isVFX: false
        )

        // VFX2: frames 450-550 (overlaps Grade2)
        let vfx2 = createMockSegment(
            name: "VFX2",
            startTime: 18.77,   // ~450 frames
            duration: 4.17,     // ~100 frames
            isVFX: true
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [grade1, vfx1, grade2, vfx2],
            totalFrames: 2000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // Expected timeline:
        // 100-200: Grade1
        // 200-250: VFX1 (overrides Grade1)
        // 250-300: Grade1 (continues)
        // 300-450: Grade2 (overrides Grade1)
        // 450-550: VFX2 (overrides Grade2)
        // 550-700: Grade2 (continues)

        // Verify VFX segments are preserved
        let vfx1Range = plan.consolidatedRanges.first { $0.segment.url.lastPathComponent == "VFX1.mov" }
        XCTAssertNotNil(vfx1Range)
        XCTAssertEqual(vfx1Range?.frameCount ?? 0, 50, accuracy: 1)

        let vfx2Range = plan.consolidatedRanges.first { $0.segment.url.lastPathComponent == "VFX2.mov" }
        XCTAssertNotNil(vfx2Range)
        XCTAssertEqual(vfx2Range?.frameCount ?? 0, 100, accuracy: 1)

        // Check statistics
        XCTAssertEqual(plan.statistics.vfxSegmentCount, 2)
        XCTAssertEqual(plan.statistics.vfxFrames, 150, accuracy: 1)
        XCTAssertGreaterThan(plan.statistics.gradeFrames, 0)
    }

    // MARK: - Edge Case Tests

    func testSegmentAtTimelineBoundary() throws {
        let baseProperties = createMockVideoStreamProperties()

        // Segment that extends beyond timeline
        let segment = createMockSegment(
            name: "BoundarySeg",
            startTime: 18.77,   // ~450 frames
            duration: 4.17,     // ~100 frames (would go to 550)
            isVFX: false
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [segment],
            totalFrames: 500,
            verbose: true
        )
        let plan = try analyzer.analyze()

        // Should be clamped to timeline boundary
        XCTAssertEqual(plan.consolidatedRanges.count, 1)
        let range = plan.consolidatedRanges[0]
        XCTAssertEqual(range.startFrame, 450, accuracy: 1)
        XCTAssertEqual(range.endFrame, 500) // Clamped to timeline end
        XCTAssertEqual(range.frameCount, 50, accuracy: 1)
    }

    func testSingleFrameSegment() throws {
        let baseProperties = createMockVideoStreamProperties()

        let segment = createMockSegment(
            name: "SingleFrame",
            startTime: 4.17,    // ~100 frames
            duration: 0.0417,   // ~1 frame
            isVFX: false
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [segment],
            totalFrames: 1000,
            verbose: true
        )
        let plan = try analyzer.analyze()

        XCTAssertEqual(plan.consolidatedRanges.count, 1)
        XCTAssertEqual(plan.consolidatedRanges[0].frameCount, 1)
    }

    func testVisualizationData() throws {
        let baseProperties = createMockVideoStreamProperties()

        let grade = createMockSegment(
            name: "Grade",
            startTime: 4.17,
            duration: 8.34,
            isVFX: false
        )

        let vfx = createMockSegment(
            name: "VFX",
            startTime: 6.26,
            duration: 2.09,
            isVFX: true
        )

        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: [grade, vfx],
            totalFrames: 1000,
            verbose: true  // Enable visualization
        )
        let plan = try analyzer.analyze()

        XCTAssertNotNil(plan.visualizationData)
        XCTAssertEqual(plan.visualizationData?.placements.count, 2)
        XCTAssertEqual(plan.visualizationData?.totalFrames, 1000)

        // Check VFX has red color, grade has blue
        let vfxPlacement = plan.visualizationData?.placements.first { $0.isVFX }
        XCTAssertEqual(vfxPlacement?.color, "#FF6B6B")

        let gradePlacement = plan.visualizationData?.placements.first { !$0.isVFX }
        XCTAssertEqual(gradePlacement?.color, "#4DABF7")
    }
}

// MARK: - Helper Extensions for Testing

private extension Int {
    func isEqual(to other: Int, accuracy: Int) -> Bool {
        return abs(self - other) <= accuracy
    }
}

private func XCTAssertEqual(_ expression1: Int, _ expression2: Int, accuracy: Int,
                           _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    if !expression1.isEqual(to: expression2, accuracy: accuracy) {
        XCTFail("\(expression1) is not equal to \(expression2) +/- \(accuracy). \(message())",
                file: file, line: line)
    }
}