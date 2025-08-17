import AVFoundation
import CoreMedia
import Foundation
import TimecodeKit

Task {
    // Test import functionality first
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

    print("\n" + String(repeating: "=", count: 50))
    print("🔗 Testing pairing process...")

    // Test pairing functionality with multiple OCF directories
    let ocfDirectoryURLs = [
        URL(fileURLWithPath: "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/02_FOOTAGE/OCF/8MM/COS AW25_4K_4444_LR001_LOG"),
        URL(fileURLWithPath: "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/02_FOOTAGE/OCF/8MM/COS AW25_4K_4444_LR001_LOG/subfolder")
    ]

    do {
        // Import OCF files from multiple directories
        var allOCFFiles: [MediaFileInfo] = []
        
        for (index, ocfDirectoryURL) in ocfDirectoryURLs.enumerated() {
            print("📹 Importing OCF files from directory \(index + 1): \(ocfDirectoryURL.lastPathComponent)")
            let ocfFiles = try await importProcess.importOriginalCameraFiles(from: ocfDirectoryURL)
            allOCFFiles.append(contentsOf: ocfFiles)
        }
        
        print("✅ Successfully imported \(allOCFFiles.count) total OCF files from \(ocfDirectoryURLs.count) directories")

        // Create pairer and test
        let pairer = SegmentOCFPairer()
        let pairingResult = pairer.pairSegments(gradedSegments, withOCFs: allOCFFiles)

        print("\n📊 Pairing Results:")
        print("  Success Rate: \(Int(pairingResult.successRate * 100))%")
        print("  Matched Pairs: \(pairingResult.pairs.filter { $0.ocf != nil }.count)")
        print("  Unmatched Segments: \(pairingResult.unmatchedSegments.count)")
        print("  Unmatched OCFs: \(pairingResult.unmatchedOCFs.count)")

    } catch {
        print("❌ OCF import or pairing failed: \(error)")
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
