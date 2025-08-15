import AVFoundation
import CoreMedia
import Foundation
import TimecodeKit

Task {
    // Test import functionality first
    print("🧪 Testing import functionality...")

    let importProcess = ImportProcess()
    // let segmentsDirectoryURL = URL(fileURLWithPath: "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/ALL_GRADES_MM")
    let segmentsDirectoryURL = URL(
        fileURLWithPath: "/Users/fq/Movies/ProResWriter/testMaterialNonQT/30.00")

    do {
        let gradedSegments = try await importProcess.importGradedSegments(
            from: segmentsDirectoryURL)
        print("✅ Successfully imported \(gradedSegments.count) graded segments")

        for segment in gradedSegments {
            print("📄 \(segment.fileName)")
            print(
                "  📐 Resolution: \(Int(segment.resolution.width))x\(Int(segment.resolution.height))"
            )
            print("  🎬 Frame Rate: \(segment.frameRate)fps")
            print("  📁 Type: \(segment.mediaType)")
        }
    } catch {
        print("❌ Import failed: \(error)")
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
