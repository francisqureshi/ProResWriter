import AVFoundation
import CoreMedia
import Foundation
import ProResWriterCore
import TimecodeKit

// MARK: - Core functionality imported from ProResWriterCore package

// // MARK: - Test Configuration Paths
let testPaths = (
    gradedSegments: "/Users/fq/Movies/ProResWriter/Ganni/ALL_GRADES_MM",
    ocfParents: ["/Volumes/EVO-POST/__POST/1683 - GANNI/02_FOOTAGE/OCF/3"],
    outputComposition: "/Users/fq/Movies/ProResWriter/Ganni/w2",
    projectBlankRushDirectory: "/Users/fq/Movies/ProResWriter/Ganni/blankRush"
)

// MARK: - Test Configuration Paths
// let testPaths = (
//     gradedSegments:
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/08_GRADE/02_GRADED CLIPS/1684_Levi's_Nov-Dec/03 INTERMEDIATE/ALL_GRADES_MM",
//     ocfParents: [
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/02_FOOTAGE/OCF/25_03_25",
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/02_FOOTAGE/OCF/25_03_26",
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/02_FOOTAGE/OCF/25_03_27",
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/02_FOOTAGE/OCF/25_03_28",
//     ],
//     outputComposition:
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/08_GRADE/02_GRADED CLIPS/1684_Levi's_Nov-Dec/03 INTERMEDIATE/test",
//     projectBlankRushDirectory:
//         "/Volumes/EVO-POST/__POST/1629 - LEVI'S GDA/08_GRADE/02_GRADED CLIPS/1684_Levi's_Nov-Dec/03 INTERMEDIATE/blankTest/"
// )

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
    let segmentsDirectoryURL = URL(fileURLWithPath: testPaths.gradedSegments)

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

    let ocfDirectoryURLs = testPaths.ocfParents.map { URL(fileURLWithPath: $0) }

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

func testBlankRushCreation(linkingResult: LinkingResult) async -> [BlankRushResult] {
    print("\n" + String(repeating: "=", count: 50))
    print("🎬 Testing blank rush creation...")

    print("📊 \(linkingResult.blankRushSummary)")

    let blankRushIntermediate = BlankRushIntermediate(
        projectDirectory: testPaths.projectBlankRushDirectory)
    
    // Test 1: Traditional TUI progress bar (no callback)
    print("\n📊 Test 1: Using TUI progress bar system (no callback)")
    let tuiResults = await blankRushIntermediate.createBlankRushes(from: linkingResult)

    print("\n📊 TUI Progress Bar Results:")
    for result in tuiResults {
        if result.success {
            print("  ✅ \(result.originalOCF.fileName) → \(result.blankRushURL.lastPathComponent)")
        } else {
            print("  ❌ \(result.originalOCF.fileName) → \(result.error ?? "Unknown error")")
        }
    }
    
    // Test 2: New progress callback system (simulating GUI usage)
    print("\n" + String(repeating: "-", count: 50))
    print("📊 Test 2: Using progress callback system (simulating GUI)")
    
    // Create a simple progress callback that prints updates
    let progressCallback: BlankRushIntermediate.ProgressCallback = { clipName, current, total, fps in
        let percentage = Int((current / total) * 100)
        let progressBar = String(repeating: "█", count: percentage / 4)  // Smaller bar for CLI
        let emptyBar = String(repeating: "░", count: 25 - (percentage / 4))
        let fpsText = fps > 0 ? String(format: " @ %.1ffps", fps) : ""
        print("\r  📞 \(clipName): [\(progressBar)\(emptyBar)] \(percentage)%\(fpsText)", terminator: "")
        if percentage >= 100 {
            print("")  // New line when complete
        }
    }
    
    let callbackResults = await blankRushIntermediate.createBlankRushes(from: linkingResult, progressCallback: progressCallback)

    print("\n📊 Progress Callback Results:")
    for result in callbackResults {
        if result.success {
            print("  ✅ \(result.originalOCF.fileName) → \(result.blankRushURL.lastPathComponent)")
        } else {
            print("  ❌ \(result.originalOCF.fileName) → \(result.error ?? "Unknown error")")
        }
    }
    
    // Verify both approaches produce identical results
    let tuiSuccess = tuiResults.filter { $0.success }.count
    let callbackSuccess = callbackResults.filter { $0.success }.count
    
    if tuiSuccess == callbackSuccess {
        print("\n✅ Both TUI and callback systems produced identical results: \(tuiSuccess) successful")
    } else {
        print("\n❌ Results differ: TUI=\(tuiSuccess), Callback=\(callbackSuccess)")
    }

    return tuiResults
}

func testTranscodeBlank() async {
    // Test simple transcoding directly
    print("\n" + String(repeating: "=", count: 50))
    print("🎬 Testing simple transcoding...")

    let blankRushIntermediate = BlankRushIntermediate(
        projectDirectory: testPaths.projectBlankRushDirectory)

    // Create a minimal test - use shorter source file for debugging
    let inputPath = "/Users/fq/Movies/ProResWriter/testMaterialNonQT/23.98/A002C010_250605_RP4Z.mxf"
    // let inputPath = "/Users/mac10/Desktop/59.94/A001C001_2505193L_CANON.MXF"
    let outputPath =
        "/Users/fq/Movies/ProResWriter/SwiftFFmpeg_out/23976fps_422_proxy_transcode.mov"

    do {
        let success = try await blankRushIntermediate.generateBlackFramesToProRes(
            inputPath: inputPath,
            outputPath: outputPath
        )

        if success {
            print("✅ Test simple transcoding succeeded!")
        } else {
            print("❌ Test simple transcoding failed")
        }
    } catch {
        print("❌ Test simple transcoding error: \(error)")
    }

    print("\n" + String(repeating: "=", count: 50))

}

func testBlackFrameGeneration() async {
    // Test black frame generation using MediaFileInfo data directly
    print("\n" + String(repeating: "=", count: 50))
    print("🖤 Testing black frame generation with MediaFileInfo...")

    // First, import the file to get proper MediaFileInfo with correct frame count
    let importProcess = ImportProcess()
    // let testFileURL = URL(fileURLWithPath: "/Users/fq/Movies/ProResWriter/testMaterialNonQT/23.98")

    let testFileURL = URL(
        fileURLWithPath: "/Users/fq/Movies/ProResWriter/testMaterialNonQT/59.94 DF")

    do {
        // Import single file to get MediaFileInfo with accurate frame count
        let mediaFiles = try await importProcess.importOriginalCameraFiles(
            from: testFileURL)

        guard let testFile = mediaFiles.first else {
            print("❌ Test file not found in import results")
            return
        }

        print("📊 MediaFileInfo frame count: \(testFile.durationInFrames ?? 0) frames")
        if let frameRate = testFile.frameRate, let frameCount = testFile.durationInFrames {
            let calculatedDuration = Double(frameCount) / Double(frameRate)
            print(
                "📊 MediaFileInfo calculated duration: \(String(format: "%.3f", calculatedDuration))s"
            )
        }

        let blankRushIntermediate = BlankRushIntermediate(
            projectDirectory: testPaths.projectBlankRushDirectory)
        // let outputPath = "/Users/fq/Movies/ProResWriter/SwiftFFmpeg_out/23976fps_422_proxy_blackframes.mov"
        let outputPath =
            "/Users/fq/Movies/ProResWriter/SwiftFFmpeg_out/5999fps_422_proxy_blackframes.mov"

        // Use MediaFileInfo-based method (more accurate)
        let success = try await blankRushIntermediate.generateBlankRushFromOCF(
            ocfFile: testFile,
            outputPath: outputPath
        )

        if success {
            print("✅ Test black frame generation with MediaFileInfo succeeded!")
            print("📁 Compare with transcode: /Users/fq/Movies/ProResWriter/SwiftFFmpeg_out/")
        } else {
            print("❌ Test black frame generation failed")
        }
    } catch {
        print("❌ Test black frame generation error: \(error)")
    }

    print("\n" + String(repeating: "=", count: 50))
}

@available(macOS 15, *)
func testPrintProcess(linkingResult: LinkingResult, blankRushResults: [BlankRushResult]) async {
    print("🎬 Starting batch print process with linked data...")

    // Process all OCF parents that have children and successful blank rushes
    let validParents = linkingResult.ocfParents.filter { $0.hasChildren }
    let successfulBlankRushes = blankRushResults.filter { $0.success }

    print(
        "📊 Found \(validParents.count) OCF parents with children and \(successfulBlankRushes.count) successful blank rushes"
    )

    for (index, ocfParent) in validParents.enumerated() {
        guard
            let blankRushResult = successfulBlankRushes.first(where: {
                $0.originalOCF.fileName == ocfParent.ocf.fileName
            })
        else {
            print("⚠️ No matching blank rush found for \(ocfParent.ocf.fileName)")
            continue
        }

        let blankRushURL = blankRushResult.blankRushURL

        // Generate output filename using just the OCF parent name
        let baseName = (ocfParent.ocf.fileName as NSString).deletingPathExtension
        let outputFileName = "\(baseName).mov"
        let outputURL = URL(fileURLWithPath: testPaths.outputComposition).appendingPathComponent(
            outputFileName)

        print("\n==================================================")
        print(
            "🎬 Processing OCF Parent \(index + 1)/\(validParents.count): \(ocfParent.ocf.fileName)")
        print("📁 Using blank rush: \(blankRushURL.lastPathComponent)")
        print("📝 Processing \(ocfParent.children.count) linked segments")
        print("🎯 Output: \(outputFileName)")

        // Create graded segments from the linked children
        let compositor = ProResVideoCompositor()

        do {
            let baseAsset = AVURLAsset(url: blankRushURL)
            let baseTrack = try await compositor.getVideoTrack(from: baseAsset)
            let baseProperties = try await compositor.getVideoProperties(from: baseTrack)
            let baseDuration = try await baseAsset.load(.duration)

            // Convert linked children to GradedSegment objects
            var gradedSegments: [GradedSegment] = []
            for child in ocfParent.children {
                let segmentInfo = child.segment

                // Calculate start time from the segment's timecode relative to base
                if let segmentTC = segmentInfo.sourceTimecode,
                    let baseTC = baseProperties.sourceTimecode
                {
                    if let startTime = compositor.timecodeToCMTime(
                        segmentTC, frameRate: baseProperties.frameRate, baseTimecode: baseTC),
                        let duration = segmentInfo.durationInFrames
                    {

                        let segmentDuration = CMTime(
                            seconds: Double(duration) / Double(baseProperties.frameRate),
                            preferredTimescale: CMTimeScale(baseProperties.frameRate * 1000)
                        )

                        let gradedSegment = GradedSegment(
                            url: segmentInfo.url,
                            startTime: startTime,
                            duration: segmentDuration,
                            sourceStartTime: .zero
                        )
                        gradedSegments.append(gradedSegment)

                        let frameNumber = Int(
                            round(startTime.seconds * Double(baseProperties.frameRate)))
                        print("📝 \(segmentInfo.fileName): Frame \(frameNumber) (TC: \(segmentTC))")
                    }
                }
            }

            if gradedSegments.isEmpty {
                print(
                    "❌ No valid graded segments could be created from linked data for \(ocfParent.ocf.fileName)"
                )
                continue
            }

            let settings = CompositorSettings(
                outputURL: outputURL,
                baseVideoURL: blankRushURL,
                gradedSegments: gradedSegments,
                proResType: .proRes4444
            )

            // Setup completion handler and wait for completion
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                compositor.completionHandler = { result in
                    print("\n")  // New line after progress bar
                    switch result {
                    case .success(let outputURL):
                        print("✅ Composition complete!")
                        print("📁 Output file: \(outputURL.path)")
                        continuation.resume()
                    case .failure(let error):
                        print("❌ Composition failed: \(error.localizedDescription)")
                        continuation.resume()
                    }
                }

                // Start the composition
                compositor.composeVideo(with: settings)
            }

        } catch {
            print("❌ Print process failed for \(ocfParent.ocf.fileName): \(error)")
        }
    }

    print("\n==================================================")
    print("🎬 Batch print process complete!")
}

Task {
    // Test SMPTE library first
    // testSMPTE()
    // exit(0)

    // Test import and linking
    let gradedSegments = await testImport()
    if let linkingResult = await testLinking(segments: gradedSegments) {
        let blankRushResults = await testBlankRushCreation(linkingResult: linkingResult)

        // Pass the linked data to print process instead of re-discovering
        if #available(macOS 15, *) {
            await testPrintProcess(linkingResult: linkingResult, blankRushResults: blankRushResults)
        } else {
            print("⚠️ Print process requires macOS 15+ - skipping")
        }
    }

    // await testBlackFrameGeneration()  // Test new black frame generation
    exit(0)
}

RunLoop.main.run()
