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
}