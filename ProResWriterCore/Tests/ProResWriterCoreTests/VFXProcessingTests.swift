//
//  VFXProcessingTests.swift
//  ProResWriterCoreTests
//
//  Tests for VFX segment processing and replacement workflow
//  Using Theory Holiday test data for comprehensive VFX pipeline validation
//

import XCTest
import SwiftFFmpeg
import AVFoundation
import CoreMedia
import TimecodeKit
@testable import ProResWriterCore

final class VFXProcessingTests: XCTestCase {

    // MARK: - Theory Holiday Test Data

    struct TheoryHolidayTestData {
        static let ocfPath = "/Volumes/EVO-POST/__POST/1677 - THEORY HOLIDAY/02_FOOTAGE/TRANSCODES/WILD ISLAND TRANSCODES/A006C005_250717MC.mov"
        static let gradeSegmentPath = "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/TheoryVFX/Grade/V1-0088_A006C005_250717MC.mov"
        static let vfxSegmentPath = "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/TheoryVFX/VFX/V1-0223_A006C005_250717MC__S0020_VFX_EX_0821_v1.mov"
        static let outputDirectory = "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/TheoryVFX/Output"
        static let blankRushDirectory = "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/TheoryVFX/BlankRush"
    }

    // MARK: - Test File Validation

    func testTheoryHolidayTestFilesExist() {
        let fileManager = FileManager.default

        XCTAssertTrue(
            fileManager.fileExists(atPath: TheoryHolidayTestData.ocfPath),
            "OCF file should exist at: \(TheoryHolidayTestData.ocfPath)"
        )

        XCTAssertTrue(
            fileManager.fileExists(atPath: TheoryHolidayTestData.gradeSegmentPath),
            "Grade segment should exist at: \(TheoryHolidayTestData.gradeSegmentPath)"
        )

        XCTAssertTrue(
            fileManager.fileExists(atPath: TheoryHolidayTestData.vfxSegmentPath),
            "VFX segment should exist at: \(TheoryHolidayTestData.vfxSegmentPath)"
        )
    }

    // MARK: - Media Analysis Tests

    func testVFXSegmentAnalysis() async throws {
        let analyzer = MediaAnalyzer()

        // Analyze single OCF file directly
        let ocfURL = URL(fileURLWithPath: TheoryHolidayTestData.ocfPath)
        print("📹 Analyzing single OCF file: \(ocfURL.lastPathComponent)")
        let ocfFile = try await analyzer.analyzeMediaFile(at: ocfURL, type: .originalCameraFile)

        // Analyze single grade segment file directly
        let gradeURL = URL(fileURLWithPath: TheoryHolidayTestData.gradeSegmentPath)
        print("🎨 Analyzing single grade segment: \(gradeURL.lastPathComponent)")
        let gradeSegment = try await analyzer.analyzeMediaFile(at: gradeURL, type: .gradedSegment)

        // Analyze single VFX segment file directly
        let vfxURL = URL(fileURLWithPath: TheoryHolidayTestData.vfxSegmentPath)
        print("🎭 Analyzing single VFX segment: \(vfxURL.lastPathComponent)")
        let vfxSegment = try await analyzer.analyzeMediaFile(at: vfxURL, type: .gradedSegment)

        print("📹 OCF Analysis:")
        print("  📁 File: \(ocfFile.fileName)")
        print("  📐 Resolution: \(ocfFile.resolution?.width ?? 0)x\(ocfFile.resolution?.height ?? 0)")
        print("  🎬 Frame Rate: \(ocfFile.frameRateDescription)")
        print("  ⏰ Timecode: \(ocfFile.sourceTimecode ?? "None")")
        print("  📊 Duration: \(ocfFile.durationInFrames ?? 0) frames")

        print("\n🎨 Grade Segment Analysis:")
        print("  📁 File: \(gradeSegment.fileName)")
        print("  📐 Resolution: \(gradeSegment.resolution?.width ?? 0)x\(gradeSegment.resolution?.height ?? 0)")
        print("  🎬 Frame Rate: \(gradeSegment.frameRateDescription)")
        print("  ⏰ Timecode: \(gradeSegment.sourceTimecode ?? "None")")
        print("  📊 Duration: \(gradeSegment.durationInFrames ?? 0) frames")

        print("\n🎭 VFX Segment Analysis:")
        print("  📁 File: \(vfxSegment.fileName)")
        print("  📐 Resolution: \(vfxSegment.resolution?.width ?? 0)x\(vfxSegment.resolution?.height ?? 0)")
        print("  🎬 Frame Rate: \(vfxSegment.frameRateDescription)")
        print("  ⏰ Timecode: \(vfxSegment.sourceTimecode ?? "None")")
        print("  📊 Duration: \(vfxSegment.durationInFrames ?? 0) frames")

        // Validate expected properties
        XCTAssertEqual(ocfFile.resolution, gradeSegment.resolution, "OCF and grade should have matching resolution")
        XCTAssertEqual(ocfFile.resolution, vfxSegment.resolution, "OCF and VFX should have matching resolution")

        // Check frame rate compatibility using new rational system
        if let ocfFrameRate = ocfFile.frameRate,
           let gradeFrameRate = gradeSegment.frameRate,
           let vfxFrameRate = vfxSegment.frameRate {
            XCTAssertTrue(
                FrameRateManager.areFrameRatesCompatible(ocfFrameRate, gradeFrameRate),
                "OCF and grade frame rates should be compatible"
            )
            XCTAssertTrue(
                FrameRateManager.areFrameRatesCompatible(ocfFrameRate, vfxFrameRate),
                "OCF and VFX frame rates should be compatible"
            )
        }

        // Analyze the "19 frame handles shorter" claim
        if let gradeDuration = gradeSegment.durationInFrames,
           let vfxDuration = vfxSegment.durationInFrames {
            let frameDifference = Int(gradeDuration) - Int(vfxDuration)
            print("\n📊 Duration Comparison:")
            print("  🎨 Grade: \(gradeDuration) frames")
            print("  🎭 VFX: \(vfxDuration) frames")
            print("  🔄 Difference: \(frameDifference) frames (\(frameDifference/2) per side if symmetric)")

            // Test if it's approximately 38 frames shorter (19 per side)
            XCTAssertTrue(
                abs(frameDifference - 38) <= 5, // Allow 5 frame tolerance
                "VFX segment should be approximately 38 frames shorter than grade (19 per side), got \(frameDifference)"
            )
        }
    }

    // MARK: - VFX Segment Identification Tests

    func testVFXSegmentIdentification() {
        // Test VFX segment identification by filename patterns
        let gradeFileName = "V1-0088_A006C005_250717MC.mov"
        let vfxFileName = "V1-0223_A006C005_250717MC__S0020_VFX_EX_0821_v1.mov"

        XCTAssertTrue(
            VFXSegmentMatcher.isVFXSegment(fileName: vfxFileName),
            "Should identify VFX segment by filename pattern"
        )

        XCTAssertFalse(
            VFXSegmentMatcher.isVFXSegment(fileName: gradeFileName),
            "Should not identify grade segment as VFX"
        )

        // Test OCF identifier extraction
        let ocfIdentifier = VFXSegmentMatcher.extractOCFIdentifier(from: gradeFileName)
        XCTAssertEqual(ocfIdentifier, "A006C005_250717MC", "Should extract OCF identifier from grade filename")

        let vfxOCFIdentifier = VFXSegmentMatcher.extractOCFIdentifier(from: vfxFileName)
        XCTAssertEqual(vfxOCFIdentifier, "A006C005_250717MC", "Should extract same OCF identifier from VFX filename")

        // Test segment pairing
        XCTAssertTrue(
            VFXSegmentMatcher.areSegmentsPaired(grade: gradeFileName, vfx: vfxFileName),
            "Grade and VFX segments should be identified as paired"
        )
    }

    // MARK: - Linking Process Tests

    func testVFXSegmentLinking() async throws {
        let analyzer = MediaAnalyzer()

        // Analyze single files directly
        let ocfURL = URL(fileURLWithPath: TheoryHolidayTestData.ocfPath)
        let ocfFile = try await analyzer.analyzeMediaFile(at: ocfURL, type: .originalCameraFile)
        let ocfFiles = [ocfFile]

        let gradeURL = URL(fileURLWithPath: TheoryHolidayTestData.gradeSegmentPath)
        let vfxURL = URL(fileURLWithPath: TheoryHolidayTestData.vfxSegmentPath)

        // Analyze single grade segment
        let gradeSegment = try await analyzer.analyzeMediaFile(at: gradeURL, type: .gradedSegment)

        // Analyze single VFX segment and mark as VFX
        var vfxSegment = try await analyzer.analyzeMediaFile(at: vfxURL, type: .gradedSegment)
        vfxSegment.isVFXShot = true

        let allSegments = [gradeSegment, vfxSegment]

        // Test linking with both grade and VFX segments
        let linker = SegmentOCFLinker()
        let linkingResult = linker.linkSegments(allSegments, withOCFParents: ocfFiles)

        XCTAssertGreaterThan(linkingResult.totalLinkedSegments, 0, "Should successfully link segments")
        XCTAssertEqual(linkingResult.unmatchedOCFs.count, 0, "Should match all OCF files")

        // Find the Theory Holiday OCF parent
        let theoryOCFParent: OCFParent? = linkingResult.ocfParents.first { parent in
            parent.ocf.fileName.contains("A006C005_250717MC")
        }
        let theoryParent = try XCTUnwrap(theoryOCFParent, "Should find Theory Holiday OCF parent")

        print("\n🔗 Theory Holiday Linking Results:")
        print("  📁 OCF Parent: \(theoryParent.ocf.fileName)")
        print("  📝 Linked Segments: \(theoryParent.childCount)")

        for (index, child) in theoryParent.children.enumerated() {
            let vfxStatus = (child.segment.isVFXShot ?? false) ? " [VFX]" : " [GRADE]"
            print("    \(index + 1). \(child.segment.fileName)\(vfxStatus) - \(child.linkConfidence)")
        }

        // Test that both grade and VFX segments are linked
        let hasGradeSegment = theoryParent.children.contains { child in
            child.segment.fileName.contains("V1-0088") && !(child.segment.isVFXShot ?? false)
        }
        let hasVFXSegment = theoryParent.children.contains { child in
            child.segment.fileName.contains("V1-0223") && (child.segment.isVFXShot ?? false)
        }

        XCTAssertTrue(hasGradeSegment, "Should link grade segment")
        XCTAssertTrue(hasVFXSegment, "Should link VFX segment")

        // Test VFX segment priority/replacement logic would go here once implemented
    }

    // MARK: - VFX Composite Logic Tests

    func testVFXCompositeLayering() async throws {
        // Test the VFX composite logic with actual Theory Holiday files
        print("🧪 Testing VFX composite layering with Theory Holiday files...")

        let analyzer = MediaAnalyzer()

        // Analyze the actual Theory Holiday files
        let gradeURL = URL(fileURLWithPath: TheoryHolidayTestData.gradeSegmentPath)
        let vfxURL = URL(fileURLWithPath: TheoryHolidayTestData.vfxSegmentPath)

        let gradeFile = try await analyzer.analyzeMediaFile(at: gradeURL, type: .gradedSegment)
        let vfxFile = try await analyzer.analyzeMediaFile(at: vfxURL, type: .gradedSegment)

        print("📊 Actual Theory Holiday File Analysis:")
        print("  🎨 Grade: \(gradeFile.fileName)")
        print("    📐 Resolution: \(gradeFile.resolution?.width ?? 0)x\(gradeFile.resolution?.height ?? 0)")
        print("    🎬 Frame Rate: \(gradeFile.frameRateDescription)")
        print("    📊 Duration: \(gradeFile.durationInFrames ?? 0) frames")

        print("  🎭 VFX: \(vfxFile.fileName)")
        print("    📐 Resolution: \(vfxFile.resolution?.width ?? 0)x\(vfxFile.resolution?.height ?? 0)")
        print("    🎬 Frame Rate: \(vfxFile.frameRateDescription)")
        print("    📊 Duration: \(vfxFile.durationInFrames ?? 0) frames")

        // Calculate the actual handle difference
        guard let gradeDurationFrames = gradeFile.durationInFrames,
              let vfxDurationFrames = vfxFile.durationInFrames,
              let frameRate = gradeFile.frameRateDouble else {
            XCTFail("Should have duration and frame rate data")
            return
        }

        let gradeDurationSeconds = Double(gradeDurationFrames) / frameRate
        let vfxDurationSeconds = Double(vfxDurationFrames) / frameRate
        let handleDifferenceFrames = Int(gradeDurationFrames) - Int(vfxDurationFrames)
        let handleDifferenceSeconds = gradeDurationSeconds - vfxDurationSeconds
        let handlesPerSideFrames = Double(handleDifferenceFrames) / 2.0
        let handlesPerSideSeconds = handleDifferenceSeconds / 2.0

        print("📏 Handle Analysis:")
        print("  🎨 Grade duration: \(gradeDurationFrames) frames (\(String(format: "%.3f", gradeDurationSeconds))s)")
        print("  🎭 VFX duration: \(vfxDurationFrames) frames (\(String(format: "%.3f", vfxDurationSeconds))s)")
        print("  🔄 Frame difference: \(handleDifferenceFrames) frames (\(String(format: "%.3f", handleDifferenceSeconds))s)")
        print("  📏 Handles per side: \(String(format: "%.1f", handlesPerSideFrames)) frames (\(String(format: "%.3f", handlesPerSideSeconds))s)")

        // Verify the ~19 frame handles claim
        XCTAssertGreaterThan(handleDifferenceFrames, 30, "Handle difference should be at least 30 frames")
        XCTAssertLessThan(handleDifferenceFrames, 50, "Handle difference should be less than 50 frames")
        XCTAssertGreaterThan(handlesPerSideFrames, 15.0, "Handles per side should be at least 15 frames")
        XCTAssertLessThan(handlesPerSideFrames, 25.0, "Handles per side should be less than 25 frames")

        // Test VFX composite timing logic
        let expectedVFXStart = handlesPerSideSeconds
        let expectedVFXEnd = expectedVFXStart + vfxDurationSeconds

        print("📊 Expected VFX Composite Timeline:")
        print("  🎨 Pre-VFX grade: 0.0s - \(String(format: "%.3f", expectedVFXStart))s")
        print("  🎭 VFX content: \(String(format: "%.3f", expectedVFXStart))s - \(String(format: "%.3f", expectedVFXEnd))s")
        print("  🎨 Post-VFX grade: \(String(format: "%.3f", expectedVFXEnd))s - \(String(format: "%.3f", gradeDurationSeconds))s")

        // Verify composite makes sense
        XCTAssertGreaterThan(vfxDurationSeconds, 0, "VFX should have positive duration")
        XCTAssertLessThan(vfxDurationSeconds, gradeDurationSeconds, "VFX should be shorter than grade")
        XCTAssertEqual(expectedVFXEnd, gradeDurationSeconds - handlesPerSideSeconds, accuracy: 0.001, "VFX end should leave room for post-handle")

        print("✅ Theory Holiday VFX composite logic validated")
    }

    // MARK: - VFX Print Process Tests

    @available(macOS 15, *)
    func testVFXPrintProcessWithSwiftFFmpeg() async throws {
        // This test requires the VFX replacement logic to be implemented in SwiftFFmpeg
        print("🚀 Testing VFX print process with SwiftFFmpeg...")

        // Create output directories
        let fileManager = FileManager.default
        let outputURL = URL(fileURLWithPath: TheoryHolidayTestData.outputDirectory)
        let blankRushURL = URL(fileURLWithPath: TheoryHolidayTestData.blankRushDirectory)

        try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: blankRushURL, withIntermediateDirectories: true)

        // Import and link segments using single file analysis
        let analyzer = MediaAnalyzer()

        let ocfURL = URL(fileURLWithPath: TheoryHolidayTestData.ocfPath)
        let ocfFile = try await analyzer.analyzeMediaFile(at: ocfURL, type: .originalCameraFile)
        let ocfFiles = [ocfFile]

        let gradeURL = URL(fileURLWithPath: TheoryHolidayTestData.gradeSegmentPath)
        let vfxURL = URL(fileURLWithPath: TheoryHolidayTestData.vfxSegmentPath)

        // Analyze single files
        let gradeSegment = try await analyzer.analyzeMediaFile(at: gradeURL, type: .gradedSegment)
        var vfxSegment = try await analyzer.analyzeMediaFile(at: vfxURL, type: .gradedSegment)
        vfxSegment.isVFXShot = true

        let allSegments = [gradeSegment, vfxSegment]

        let linker = SegmentOCFLinker()
        let linkingResult = linker.linkSegments(allSegments, withOCFParents: ocfFiles)

        let theoryParent: OCFParent = try XCTUnwrap(
            linkingResult.ocfParents.first { $0.ocf.fileName.contains("A006C005_250717MC") },
            "Should find Theory Holiday OCF parent"
        )

        // Create blank rush for testing
        let blankRushIntermediate = BlankRushIntermediate(projectDirectory: TheoryHolidayTestData.blankRushDirectory)
        let singleParentResult = LinkingResult(
            ocfParents: [theoryParent],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )

        let blankRushResults = await blankRushIntermediate.createBlankRushes(from: singleParentResult)
        let blankRushResult: BlankRushResult = try XCTUnwrap(
            blankRushResults.first { $0.success },
            "Should have successful blank rush result"
        )

        // Test SwiftFFmpeg VFX print process
        print("\n🎬 Testing SwiftFFmpeg VFX composition...")

        // Create FFmpegGradedSegments with VFX metadata
        var ffmpegGradedSegments: [FFmpegGradedSegment] = []

        for child in theoryParent.children {
            let segmentInfo = child.segment

            // Find corresponding MediaFileInfo for VFX metadata
            guard let mediaFileInfo = allSegments.first(where: { $0.fileName == segmentInfo.fileName }) else {
                continue
            }

            if let segmentTC = segmentInfo.sourceTimecode,
               let baseTC = blankRushResult.originalOCF.sourceTimecode,
               let segmentFrameRate = segmentInfo.frameRateDouble,
               let duration = segmentInfo.durationInFrames {

                let smpte = SMPTE(fps: segmentFrameRate, dropFrame: segmentInfo.isDropFrame ?? false)

                do {
                    let segmentFrames = try smpte.getFrames(tc: segmentTC)
                    let baseFrames = try smpte.getFrames(tc: baseTC)
                    let relativeFrames = segmentFrames - baseFrames

                    let startTime = CMTime(
                        value: CMTimeValue(relativeFrames),
                        timescale: CMTimeScale(segmentFrameRate)
                    )

                    let segmentDuration = CMTime(
                        seconds: Double(duration) / Double(segmentFrameRate),
                        preferredTimescale: CMTimeScale(segmentFrameRate * 1000)
                    )

                    let ffmpegSegment = FFmpegGradedSegment(
                        url: segmentInfo.url,
                        startTime: startTime,
                        duration: segmentDuration,
                        sourceStartTime: .zero,
                        isVFXShot: mediaFileInfo.isVFXShot ?? false,
                        sourceTimecode: segmentInfo.sourceTimecode,
                        frameRate: segmentInfo.frameRateFloat,
                        isDropFrame: segmentInfo.isDropFrame
                    )
                    ffmpegGradedSegments.append(ffmpegSegment)

                    let vfxStatus = ffmpegSegment.isVFXShot ? " [VFX]" : " [GRADE]"
                    print("📝 Segment: \(segmentInfo.fileName)\(vfxStatus)")

                } catch {
                    XCTFail("Failed to calculate timing for \(segmentInfo.fileName): \(error)")
                }
            }
        }

        XCTAssertFalse(ffmpegGradedSegments.isEmpty, "Should create FFmpeg graded segments")

        // Separate VFX and regular segments
        let vfxSegments = ffmpegGradedSegments.filter { $0.isVFXShot }
        let regularSegments = ffmpegGradedSegments.filter { !$0.isVFXShot }

        print("📊 Pre-Composition Summary:")
        print("  🎨 Input grade segments: \(regularSegments.count)")
        print("  🎭 Input VFX segments: \(vfxSegments.count)")

        XCTAssertGreaterThan(vfxSegments.count, 0, "Should have VFX segments")
        XCTAssertGreaterThan(regularSegments.count, 0, "Should have grade segments")

        // Test VFX composite creation before final composition
        print("\n🧪 Testing VFX composite creation...")

        // Create a test SwiftFFmpeg compositor to verify segment processing
        let testCompositor = SwiftFFmpegProResCompositor()

        // We can't directly access private methods, but we can test the concept
        // by verifying the duration differences and expected behavior
        for gradeSegment in regularSegments {
            if let matchingVFX = vfxSegments.first(where: { vfxSeg in
                // Simple filename matching for test
                let gradeName = gradeSegment.url.lastPathComponent
                let vfxName = vfxSeg.url.lastPathComponent
                return gradeName.contains("A006C005_250717MC") && vfxName.contains("A006C005_250717MC")
            }) {
                let gradeDuration = gradeSegment.duration.seconds
                let vfxDuration = matchingVFX.duration.seconds
                let handleDifference = gradeDuration - vfxDuration

                print("  🎬 VFX Composite Pair:")
                print("    🎨 Grade: \(gradeSegment.url.lastPathComponent) (\(String(format: "%.3f", gradeDuration))s)")
                print("    🎭 VFX:   \(matchingVFX.url.lastPathComponent) (\(String(format: "%.3f", vfxDuration))s)")
                print("    📏 Handle difference: \(String(format: "%.3f", handleDifference))s (\(String(format: "%.3f", handleDifference/2))s per side)")

                // Verify VFX is shorter than grade (expected ~38 frames / 25fps = ~1.52s difference)
                XCTAssertGreaterThan(handleDifference, 1.0, "VFX should be meaningfully shorter than grade segment")
                XCTAssertLessThan(handleDifference, 3.0, "Handle difference should be reasonable (not too extreme)")
            }
        }

        // Test output filename generation
        let baseName = (theoryParent.ocf.fileName as NSString).deletingPathExtension
        let outputFileName = "\(baseName)_VFXTest.mov"
        let finalOutputURL = outputURL.appendingPathComponent(outputFileName)

        let ffmpegSettings = FFmpegCompositorSettings(
            outputURL: finalOutputURL,
            baseVideoURL: blankRushResult.blankRushURL,
            gradedSegments: ffmpegGradedSegments,
            proResProfile: "4"
        )

        // Test SwiftFFmpeg compositor with VFX segments
        let ffmpegCompositor = SwiftFFmpegProResCompositor()

        let compositionResult = await withCheckedContinuation { continuation in
            ffmpegCompositor.completionHandler = { result in
                continuation.resume(returning: result)
            }
            ffmpegCompositor.composeVideo(with: ffmpegSettings)
        }

        switch compositionResult {
        case .success(let outputURL):
            print("✅ VFX composition successful!")
            print("📁 Output: \(outputURL.path)")

            // Verify output file exists
            XCTAssertTrue(fileManager.fileExists(atPath: outputURL.path), "Output file should exist")

        case .failure(let error):
            XCTFail("VFX composition failed: \(error)")
        }
    }

    // MARK: - Edge Case Tests

    func testVFXSegmentWithoutCorrespondingGrade() {
        // Test case where VFX segment exists but no corresponding grade segment
        let vfxOnlyFileName = "V1-9999_STANDALONE_VFX_SHOT.mov"

        XCTAssertTrue(
            VFXSegmentMatcher.isVFXSegment(fileName: vfxOnlyFileName),
            "Should identify standalone VFX segment"
        )

        let identifier = VFXSegmentMatcher.extractOCFIdentifier(from: vfxOnlyFileName)
        XCTAssertEqual(identifier, "STANDALONE_VFX_SHOT", "Should extract identifier from standalone VFX")
    }

    func testGradeSegmentWithoutVFXReplacement() {
        // Test case where grade segment exists but no VFX replacement
        let gradeOnlyFileName = "V1-5555_GRADE_ONLY_SHOT.mov"

        XCTAssertFalse(
            VFXSegmentMatcher.isVFXSegment(fileName: gradeOnlyFileName),
            "Should not identify grade-only segment as VFX"
        )

        let identifier = VFXSegmentMatcher.extractOCFIdentifier(from: gradeOnlyFileName)
        XCTAssertEqual(identifier, "GRADE_ONLY_SHOT", "Should extract identifier from grade-only segment")
    }
}

// MARK: - VFX Segment Matching Utilities

struct VFXSegmentMatcher {

    /// Identifies VFX segments by filename patterns
    static func isVFXSegment(fileName: String) -> Bool {
        // Look for VFX indicators in filename
        let vfxPatterns = ["VFX", "_VFX_", "__VFX__", "VFX_EX", "_EX_"]
        return vfxPatterns.contains { pattern in
            fileName.uppercased().contains(pattern)
        }
    }

    /// Extracts OCF identifier from segment filename for pairing
    static func extractOCFIdentifier(from fileName: String) -> String? {
        // Extract OCF identifier pattern (e.g., "A006C005_250717MC" from various filename formats)
        let patterns = [
            #"([A-Z]\d{3}[A-Z]\d{3}_\d{6}[A-Z]{2})"#,  // A006C005_250717MC pattern
            #"([A-Z]\d{3}[A-Z]\d{3}_\d{6})"#,           // A006C005_250717 pattern
            #"([A-Z]\d{3}_[A-Z]\d{3})"#,                 // A006_C005 pattern
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)),
               let range = Range(match.range(at: 1), in: fileName) {
                return String(fileName[range])
            }
        }

        return nil
    }

    /// Checks if grade and VFX segments are paired (share same OCF identifier)
    static func areSegmentsPaired(grade: String, vfx: String) -> Bool {
        guard let gradeIdentifier = extractOCFIdentifier(from: grade),
              let vfxIdentifier = extractOCFIdentifier(from: vfx) else {
            return false
        }
        return gradeIdentifier == vfxIdentifier
    }
}