import AVFoundation
import CoreMedia
import Foundation
import TimecodeKit

Task {
    // Paths
    let blankRushURL = URL(
        fileURLWithPath:
            "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush/bR_COS AW25_4K_4444_24FPS_LR001_LOG.mov"
    )
    let segmentsDirectoryURL = URL(
        fileURLWithPath:
            "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/ALL_GRADES_MM/"
    )
    let outputURL = URL(
        fileURLWithPath:
            "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/OUT/w2/COS AW25_4K_4444_25FPS_LR001_LOG.mov"
    )

    await runComposition(
        blankRushURL: blankRushURL, segmentsDirectoryURL: segmentsDirectoryURL, outputURL: outputURL
    )
    exit(0)
}

RunLoop.main.run()

