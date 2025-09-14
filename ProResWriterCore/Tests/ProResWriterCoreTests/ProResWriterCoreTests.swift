import XCTest
@testable import ProResWriterCore

final class ProResWriterCoreTests: XCTestCase {
    
    func testSMPTETimecodeConversion() throws {
        let smpte = SMPTE(fps: 24.0, dropFrame: false)
        
        // Test timecode to frames conversion
        let frames = try smpte.getFrames(tc: "01:00:00:00")
        XCTAssertEqual(frames, 86400) // 1 hour * 60 minutes * 60 seconds * 24 fps
        
        // Test frames to timecode conversion
        let timecode = smpte.getTC(frames: 86400)
        XCTAssertEqual(timecode, "01:00:00:00")
    }
    
    func testSMPTEDropFrameTimecode() throws {
        let smpte = SMPTE(fps: 29.97, dropFrame: true)
        
        // Test drop frame timecode validation
        XCTAssertTrue(smpte.isValidTimecode("01:00:00;02"))
        XCTAssertFalse(smpte.isValidTimecode("01:00:00:02")) // Wrong separator for DF
    }
    
    func testImportProcessInitialization() {
        let importer = ImportProcess()
        XCTAssertNotNil(importer)
    }
    
    func testMediaAnalyzerInitialization() {
        let analyzer = MediaAnalyzer()
        XCTAssertNotNil(analyzer)
    }
    
    func testSegmentOCFLinkerInitialization() {
        let linker = SegmentOCFLinker()
        XCTAssertNotNil(linker)
    }
    
    func testLinkingResultInitialization() {
        let linkingResult = LinkingResult(
            ocfParents: [],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )
        
        XCTAssertEqual(linkingResult.totalLinkedSegments, 0)
        XCTAssertEqual(linkingResult.totalSegments, 0)
        XCTAssertEqual(linkingResult.successRate, 0.0)
        XCTAssertTrue(linkingResult.parentsWithChildren.isEmpty)
    }
    
    func testMediaTypeEnum() {
        let ocfType = MediaType.originalCameraFile
        let segmentType = MediaType.gradedSegment
        
        XCTAssertNotEqual(ocfType, segmentType)
    }
    
    func testLinkConfidenceEnum() {
        let highConfidence = LinkConfidence.high
        let lowConfidence = LinkConfidence.low

        XCTAssertNotEqual(highConfidence, lowConfidence)
    }

    // MARK: - Frame Rate Matching Tests

    func testFrameRateMatchingExact() throws {
        let linker = SegmentOCFLinker()

        // Create test OCF and segment with identical frame rates
        let ocf24 = MediaFileInfo(
            fileName: "test_ocf_24.mov",
            url: URL(fileURLWithPath: "/test_ocf_24.mov"),
            resolution: CGSize(width: 1920, height: 1080),
            displayResolution: CGSize(width: 1920, height: 1080),
            sampleAspectRatio: "1:1",
            frameRate: 24.0,
            sourceTimecode: "01:00:00:00",
            endTimecode: "01:01:40:00",
            durationInFrames: 2400,
            isDropFrame: false,
            reelName: "A001",
            isInterlaced: false,
            fieldOrder: nil,
            mediaType: .originalCameraFile
        )

        let segment24 = MediaFileInfo(
            fileName: "test_segment_24.mov",
            url: URL(fileURLWithPath: "/test_segment_24.mov"),
            resolution: CGSize(width: 1920, height: 1080),
            displayResolution: CGSize(width: 1920, height: 1080),
            sampleAspectRatio: "1:1",
            frameRate: 24.0,
            sourceTimecode: "01:00:30:00",
            endTimecode: "01:00:40:00",
            durationInFrames: 240,
            isDropFrame: false,
            reelName: "A001",
            isInterlaced: false,
            fieldOrder: nil,
            mediaType: .gradedSegment
        )

        // Test exact match
        let result = linker.linkSegments([segment24], withOCFParents: [ocf24])
        XCTAssertEqual(result.totalLinkedSegments, 1, "24fps segment should match 24fps OCF")
        XCTAssertEqual(result.totalSegments, 1)
    }

    func testCriticalFrameRateMismatch24vs23976() throws {
        let linker = SegmentOCFLinker()

        // Create OCF at 24fps and segment at 23.976fps (should NOT match)
        let ocf24 = MediaFileInfo(
            fileName: "test_ocf_24.mov",
            url: URL(fileURLWithPath: "/test_ocf_24.mov"),
            resolution: CGSize(width: 1920, height: 1080),
            displayResolution: CGSize(width: 1920, height: 1080),
            sampleAspectRatio: "1:1",
            frameRate: 24.0,
            sourceTimecode: "01:00:00:00",
            endTimecode: "01:01:40:00",
            durationInFrames: 2400,
            isDropFrame: false,
            reelName: "A001",
            isInterlaced: false,
            fieldOrder: nil,
            mediaType: .originalCameraFile
        )

        let segment23976 = MediaFileInfo(
            fileName: "test_segment_23976.mov",
            url: URL(fileURLWithPath: "/test_segment_23976.mov"),
            resolution: CGSize(width: 1920, height: 1080),
            displayResolution: CGSize(width: 1920, height: 1080),
            sampleAspectRatio: "1:1",
            frameRate: 23.976,
            sourceTimecode: "01:00:30:00",
            endTimecode: "01:00:40:00",
            durationInFrames: 240,
            isDropFrame: false,
            reelName: "A001",
            isInterlaced: false,
            fieldOrder: nil,
            mediaType: .gradedSegment
        )

        // Test critical mismatch - these should NOT link with new rational arithmetic
        let result = linker.linkSegments([segment23976], withOCFParents: [ocf24])
        XCTAssertEqual(result.totalLinkedSegments, 0, "CRITICAL: 23.976fps segment should NOT match 24fps OCF")
        XCTAssertEqual(result.totalSegments, 1)
        XCTAssertEqual(result.unmatchedSegments.count, 1)
    }

    func testCriticalFrameRateMismatch23976vs24() throws {
        let linker = SegmentOCFLinker()

        // Create OCF at 23.976fps and segment at 24fps (should NOT match)
        let ocf23976 = MediaFileInfo(
            fileName: "test_ocf_23976.mov",
            url: URL(fileURLWithPath: "/test_ocf_23976.mov"),
            resolution: CGSize(width: 1920, height: 1080),
            displayResolution: CGSize(width: 1920, height: 1080),
            sampleAspectRatio: "1:1",
            frameRate: 23.976,
            sourceTimecode: "01:00:00:00",
            endTimecode: "01:01:40:00",
            durationInFrames: 2398,
            isDropFrame: false,
            reelName: "A001",
            isInterlaced: false,
            fieldOrder: nil,
            mediaType: .originalCameraFile
        )

        let segment24 = MediaFileInfo(
            fileName: "test_segment_24.mov",
            url: URL(fileURLWithPath: "/test_segment_24.mov"),
            resolution: CGSize(width: 1920, height: 1080),
            displayResolution: CGSize(width: 1920, height: 1080),
            sampleAspectRatio: "1:1",
            frameRate: 24.0,
            sourceTimecode: "01:00:30:00",
            endTimecode: "01:00:40:00",
            durationInFrames: 240,
            isDropFrame: false,
            reelName: "A001",
            isInterlaced: false,
            fieldOrder: nil,
            mediaType: .gradedSegment
        )

        // Test critical mismatch - these should NOT link with new rational arithmetic
        let result = linker.linkSegments([segment24], withOCFParents: [ocf23976])
        XCTAssertEqual(result.totalLinkedSegments, 0, "CRITICAL: 24fps segment should NOT match 23.976fps OCF")
        XCTAssertEqual(result.totalSegments, 1)
        XCTAssertEqual(result.unmatchedSegments.count, 1)
    }

    // MARK: - FrameRateManager Tests

    func testFrameRateManagerRationalConversion() throws {
        // Test professional frame rate identification
        let film23976 = FrameRateManager.identifyProfessionalRate(frameRate: 23.976)
        XCTAssertEqual(film23976, .film23_976, "Should identify 23.976fps as film rate")

        let film24 = FrameRateManager.identifyProfessionalRate(frameRate: 24.0)
        XCTAssertEqual(film24, .film24, "Should identify 24fps as film rate")

        let ntsc2997 = FrameRateManager.identifyProfessionalRate(frameRate: 29.97)
        XCTAssertEqual(ntsc2997, .ntsc29_97, "Should identify 29.97fps as NTSC rate")

        // Test rational conversion
        let rational23976 = FrameRateManager.convertToRational(frameRate: 23.976)
        XCTAssertEqual(rational23976.num, 24000, "23.976fps should convert to 24000/1001")
        XCTAssertEqual(rational23976.den, 1001, "23.976fps should convert to 24000/1001")
    }

    func testFrameRateManagerCompatibility() throws {
        // Test exact matches
        XCTAssertTrue(FrameRateManager.areFrameRatesCompatible(24.0, 24.0), "Identical frame rates should match")
        XCTAssertTrue(FrameRateManager.areFrameRatesCompatible(23.976, 23.976), "Identical 23.976 rates should match")

        // Test critical mismatches that should NOT match
        XCTAssertFalse(FrameRateManager.areFrameRatesCompatible(24.0, 23.976), "24fps and 23.976fps should NOT match")
        XCTAssertFalse(FrameRateManager.areFrameRatesCompatible(23.976, 24.0), "23.976fps and 24fps should NOT match")
        XCTAssertFalse(FrameRateManager.areFrameRatesCompatible(29.97, 30.0), "29.97fps and 30fps should NOT match")
        XCTAssertFalse(FrameRateManager.areFrameRatesCompatible(59.94, 60.0), "59.94fps and 60fps should NOT match")
    }

    func testFrameRateManagerDescription() throws {
        // Test professional descriptions with rational notation
        let desc23976 = FrameRateManager.getFrameRateDescription(frameRate: 23.976)
        XCTAssertEqual(desc23976, "23.976fps (24000/1001)", "Should provide rational notation for 23.976fps")

        let desc24 = FrameRateManager.getFrameRateDescription(frameRate: 24.0)
        XCTAssertEqual(desc24, "24fps (24000/1000)", "Should provide 1000-scale rational notation for 24fps")

        let desc25 = FrameRateManager.getFrameRateDescription(frameRate: 25.0)
        XCTAssertEqual(desc25, "25fps (25000/1000)", "Should provide 1000-scale rational notation for 25fps")

        let descWithDF = FrameRateManager.getFrameRateDescription(frameRate: 29.97, isDropFrame: true)
        XCTAssertEqual(descWithDF, "29.97fps (30000/1001) (drop frame)", "Should include drop frame indicator")
    }

    func testFrameRateManagerDropFrameDetection() throws {
        // Test correct drop frame detection
        XCTAssertTrue(FrameRateManager.detectDropFrame(timecode: "01:00:00;00", frameRate: 29.97),
                     "Should detect drop frame with semicolon separator and 29.97fps")

        XCTAssertFalse(FrameRateManager.detectDropFrame(timecode: "01:00:00:00", frameRate: 24.0),
                      "Should detect non-drop frame with colon separator and 24fps")

        // Test inconsistent cases
        let inconsistentDF = FrameRateManager.detectDropFrame(timecode: "01:00:00;00", frameRate: 24.0)
        XCTAssertTrue(inconsistentDF, "Should trust semicolon separator even with non-DF rate")

        let inconsistentNDF = FrameRateManager.detectDropFrame(timecode: "01:00:00:00", frameRate: 29.97)
        XCTAssertFalse(inconsistentNDF, "Should trust colon separator even with DF rate")
    }

    func testFrameRateManagerTimecodeKitIntegration() throws {
        // Test TimecodeKit frame rate conversion
        let timecodeRate23 = FrameRateManager.getTimecodeFrameRate(for: 23)
        XCTAssertEqual(timecodeRate23, .fps23_976, "Should convert 23 to TimecodeKit 23.976")

        let timecodeRate24 = FrameRateManager.getTimecodeFrameRate(for: 24)
        XCTAssertEqual(timecodeRate24, .fps24, "Should convert 24 to TimecodeKit 24fps")

        let timecodeRate29 = FrameRateManager.getTimecodeFrameRate(for: 29)
        XCTAssertEqual(timecodeRate29, .fps29_97, "Should convert 29 to TimecodeKit 29.97")
    }

    func testFrameRateManagerTimescaleCalculation() throws {
        // Test CMTime timescale calculation using rational arithmetic
        let timescale23976 = FrameRateManager.getTimescale(for: 23)
        XCTAssertEqual(timescale23976, 24000, "23.976fps should use 24000 timescale for 24000/1001")

        let timescale24 = FrameRateManager.getTimescale(for: 24)
        XCTAssertEqual(timescale24, 24000, "24fps should use 24000 timescale")

        let timescale2997 = FrameRateManager.getTimescale(for: 29)
        XCTAssertEqual(timescale2997, 30000, "29.97fps should use 30000 timescale for 30000/1001")
    }

    func testFrameRateManagerValidation() throws {
        // Test professional frame rate validation
        XCTAssertTrue(FrameRateManager.isValidProfessionalFrameRate(23.976), "23.976fps should be valid professional rate")
        XCTAssertTrue(FrameRateManager.isValidProfessionalFrameRate(29.97), "29.97fps should be valid professional rate")
        XCTAssertFalse(FrameRateManager.isValidProfessionalFrameRate(27.5), "27.5fps should not be valid professional rate")

        // Test all professional frame rates are available
        let allRates = FrameRateManager.getAllProfessionalFrameRates()
        XCTAssertTrue(allRates.contains(.film23_976), "Should include 23.976fps in professional rates")
        XCTAssertTrue(allRates.contains(.ntsc29_97), "Should include 29.97fps in professional rates")
        XCTAssertGreaterThan(allRates.count, 10, "Should have comprehensive set of professional rates")
    }
}