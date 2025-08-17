import AVFoundation
import CoreMedia
import Foundation
import TimecodeKit

func testSMPTE() {

    // Test SMPTE library first
    print("🧪 Testing SMPTE library...")

    // Test 1: Non-drop frame 25fps
    let smpte25 = SMPTE(fps: 25.0, dropFrame: false)
    do {
        let frames = try smpte25.getFrames(tc: "01:00:00:00")
        let timecode = smpte25.getTC(frames: frames)
        print("✅ 25fps: 01:00:00:00 = \(frames) frames = \(timecode)")

        // Test our OCF range
        let ocfStartFrames = try smpte25.getFrames(tc: "01:00:00:00")
        let ocfEndFrames = try smpte25.getFrames(tc: "01:07:05:10")
        print(
            "✅ OCF range: \(ocfStartFrames) to \(ocfEndFrames) frames (\(ocfEndFrames - ocfStartFrames) frame duration)"
        )

        // Test segment
        let segmentStartFrames = try smpte25.getFrames(tc: "01:00:07:09")
        let segmentEndFrames = try smpte25.getFrames(tc: "01:00:09:24")
        print(
            "✅ Segment range: \(segmentStartFrames) to \(segmentEndFrames) frames (\(segmentEndFrames - segmentStartFrames) frame duration)"
        )

    } catch {
        print("❌ SMPTE 25fps test failed: \(error)")
    }

    // Test 2: Drop frame 29.97fps
    let smpte2997 = SMPTE(fps: 29.97, dropFrame: true)
    do {
        let frames = try smpte2997.getFrames(tc: "01:00:00;00")
        let timecode = smpte2997.getTC(frames: frames)
        print("✅ 29.97fps DF: 01:00:00;00 = \(frames) frames = \(timecode)")

        // Test the Python example from the library
        let testFrames = smpte2997.getTC(frames: 1800)
        print("✅ 29.97fps DF: 1800 frames = \(testFrames) (should match Python example)")

    } catch {
        print("❌ SMPTE 29.97fps test failed: \(error)")
    }

    // Test 3: 23.976fps
    let smpte23976 = SMPTE(fps: 23.976, dropFrame: false)
    do {
        let frames = try smpte23976.getFrames(tc: "12:25:29:19")
        let endTimecode = smpte23976.getTC(frames: frames + 565)
        print("✅ 23.976fps: 12:25:29:19 + 565 frames = \(endTimecode)")

    } catch {
        print("❌ SMPTE 23.976fps test failed: \(error)")
    }

    print("\n" + String(repeating: "=", count: 50))
}

func testImport() async -> [MediaFileInfo] {
    print("🧪 Testing import functionality...")

    let importProcess = ImportProcess()
    let segmentsDirectoryURL = URL(
        fileURLWithPath:
            // actual source file ---> // "/Volumes/EVO-POST/__POST/1642 - COS AW/02_FOOTAGE/OCF/8MM/COS AW25_4K_4444_24FPS_LR001_LOG & HD Best Light/"
            "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/ALL_GRADES_MM"
    )

    var gradedSegments: [MediaFileInfo] = []

    do {
        gradedSegments = try await importProcess.importGradedSegments(
            from: segmentsDirectoryURL)
        print("✅ Successfully imported \(gradedSegments.count) graded segments")

        for segment in gradedSegments {
            print("\n📄 \(segment.fileName)")
            print("  📁 Type: \(segment.mediaType)")

            // Use computed properties for cleaner display
            if let resolution = segment.resolution {
                print("  📐 Coded Resolution: \(Int(resolution.width))x\(Int(resolution.height))")
            }

            if segment.hasSensorCropping, let effectiveRes = segment.effectiveDisplayResolution {
                print(
                    "  📺 Cropped Resolution: \(Int(effectiveRes.width))x\(Int(effectiveRes.height)) (sensor crop applied)"
                )
                print("  🔲 Sample Aspect Ratio: \(segment.sampleAspectRatio!) (crop factor)")
            }

            print("  🎬 Frame Rate: \(segment.frameRateDescription)")
            print("  📺 Scan Type: \(segment.scanTypeDescription)")

            if let fieldOrder = segment.fieldOrder {
                print("  🔄 Field Order: \(fieldOrder)")
            }

            if let timecode = segment.sourceTimecode {
                print("  ⏰ Source Timecode: \(timecode)")
            }
            if let reel = segment.reelName {
                print("  🎞️ Reel Name: \(reel)")
            }

            // Show compact technical summary
            print("  📋 Summary: \(segment.technicalSummary)")
        }
    } catch {
        print("❌ Import failed: \(error)")
    }
    
    return gradedSegments
}

func testLinking(segments: [MediaFileInfo]) async -> LinkingResult? {
    print("\n" + String(repeating: "=", count: 50))
    print("🔗 Testing parent-child linking process...")

    let importProcess = ImportProcess()
    
    // Test linking functionality with multiple OCF parent directories
    let ocfDirectoryURLs = [
        URL(
            fileURLWithPath:
                "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/02_FOOTAGE/OCF/8MM/COS AW25_4K_4444_LR001_LOG"
        ),
        URL(
            fileURLWithPath:
                "/Users/fq/Movies/ProResWriter/testMaterialNonQT/59.94 DF"
        ),
    ]

    do {
        // Import OCF files from multiple directories
        var allOCFFiles: [MediaFileInfo] = []

        for (index, ocfDirectoryURL) in ocfDirectoryURLs.enumerated() {
            print(
                "📹 Importing OCF files from directory \(index + 1): \(ocfDirectoryURL.lastPathComponent)"
            )
            let ocfFiles = try await importProcess.importOriginalCameraFiles(from: ocfDirectoryURL)
            allOCFFiles.append(contentsOf: ocfFiles)
        }

        print(
            "✅ Successfully imported \(allOCFFiles.count) total OCF files from \(ocfDirectoryURLs.count) directories"
        )

        // Create linker and test
        let linker = SegmentOCFLinker()
        let linkingResult = linker.linkSegments(segments, withOCFParents: allOCFFiles)

        print("\n📊 Linking Results:")
        print("  📊 \(linkingResult.summary)")
        print("  📁 OCF Parents: \(linkingResult.ocfParents.count)")
        print("  📝 Child Segments: \(linkingResult.totalLinkedSegments)")
        print("  ❌ Unmatched Segments: \(linkingResult.unmatchedSegments.count)")
        print("  ❌ Unmatched OCFs: \(linkingResult.unmatchedOCFs.count)")
        
        // Show parent-child breakdown
        print("\n🔗 Parent-Child Breakdown:")
        for parent in linkingResult.ocfParents {
            if parent.hasChildren {
                print("  📁 \(parent.ocf.fileName) → \(parent.childCount) children")
                for child in parent.children {
                    print("    📝 \(child.segment.fileName) (\(child.linkConfidence))")
                }
            }
        }
        
        return linkingResult

    } catch {
        print("❌ OCF import or linking failed: \(error)")
    }
    
    return nil
}

func testBlankRushCreation(linkingResult: LinkingResult) async {
    print("\n" + String(repeating: "=", count: 50))
    print("🎬 Testing blank rush creation...")
    
    print("📊 \(linkingResult.blankRushSummary)")
    
    let blankRushCreator = BlankRushCreator()
    let results = await blankRushCreator.createBlankRushes(from: linkingResult)
    
    print("\n📊 Blank Rush Results:")
    for result in results {
        if result.success {
            print("  ✅ \(result.originalOCF.fileName) → \(result.blankRushURL.lastPathComponent)")
        } else {
            print("  ❌ \(result.originalOCF.fileName) → \(result.error ?? "Unknown error")")
        }
    }
}

Task {
    // Test SMPTE library first
    testSMPTE()
    // exit(0)

    // Test import and linking
    let gradedSegments = await testImport()
    if let linkingResult = await testLinking(segments: gradedSegments) {
        await testBlankRushCreation(linkingResult: linkingResult)
    }

    print("\n" + String(repeating: "=", count: 50))
    print("🎬 Starting composition process...")

    // Original paths
    let blankRushURL = URL(
        fileURLWithPath:
            "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush/bR_COS AW25_4K_4444_24FPS_LR001_LOG.mov"
    )
    let outputURL = URL(
        fileURLWithPath:
            "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/OUT/w2/COS AW25_4K_4444_25FPS_LR001_LOG.mov"
    )

    // await runComposition(
    //     blankRushURL: blankRushURL, segmentsDirectoryURL: segmentsDirectoryURL, outputURL: outputURL
    // )
    exit(0)
}

RunLoop.main.run()
