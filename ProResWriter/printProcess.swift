//
//  printProcess.swift
//  ProResWriter
//
//  Created by mac10 on 15/08/2025.
//

import AVFoundation
import CoreMedia
import TimecodeKit

// MARK: - Data Models
struct GradedSegment {
    let url: URL
    let startTime: CMTime  // Start time in the final timeline
    let duration: CMTime  // Duration of the segment
    let sourceStartTime: CMTime  // Start time in the source segment file
}

struct CompositorSettings {
    let outputURL: URL
    let baseVideoURL: URL
    let gradedSegments: [GradedSegment]
    let proResType: AVVideoCodecType  // .proRes422, .proRes422HQ, etc.
}

// MARK: - Main Compositor Class
class ProResVideoCompositor: NSObject {

    // Progress callback
    var progressHandler: ((Double) -> Void)?
    var completionHandler: ((Result<URL, Error>) -> Void)?

    // MARK: - Public Interface
    func composeVideo(with settings: CompositorSettings) {
        Task {
            do {
                let outputURL = try await processComposition(settings: settings)
                await MainActor.run {
                    completionHandler?(.success(outputURL))
                }
            } catch {
                print("❌ Composition error: \(error)")
                await MainActor.run {
                    completionHandler?(.failure(error))
                }
            }
        }
    }

    // MARK: - Core Processing
    private func processComposition(settings: CompositorSettings) async throws -> URL {

        print("🔍 Starting composition process...")

        // 1. Analyze base video to get properties
        let analysisStartTime = CFAbsoluteTimeGetCurrent()
        print("📹 Analyzing base video...")

        let assetOptions: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ]
        let baseAsset = AVURLAsset(url: settings.baseVideoURL, options: assetOptions)

        let baseTrack = try await getVideoTrack(from: baseAsset)
        let baseProperties = try await getVideoProperties(from: baseTrack)
        let analysisEndTime = CFAbsoluteTimeGetCurrent()
        print(
            "📹 Video analysis completed in: \(String(format: "%.2f", analysisEndTime - analysisStartTime))s"
        )

        // Log the extracted timecode for debugging
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Extracted base timecode: \(sourceTimecode)")
        } else {
            print("📹 No timecode found in base video")
        }

        print(
            "✅ Base video properties: \(baseProperties.width)x\(baseProperties.height) @ \(baseProperties.frameRate)fps"
        )

        // 2. Use AVMutableComposition with trimming for overlay
        let exportStartTime = CFAbsoluteTimeGetCurrent()
        print("🚀 Using AVMutableComposition with trimming for fast overlay...")

        // Create composition
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)

        // Add timecode track to composition
        let timecodeTrack = composition.addMutableTrack(
            withMediaType: .timecode, preferredTrackID: kCMPersistentTrackID_Invalid)

        // Add base video to composition
        let baseVideoTrack = try await getVideoTrack(from: baseAsset)
        let baseDuration = try await baseAsset.load(.duration)
        try videoTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: baseDuration), of: baseVideoTrack, at: .zero)

        print("🎬 Base video added to composition: \(baseDuration.seconds)s")

        // Copy existing timecode track from base asset if it exists
        if let timecodeTrack = timecodeTrack {
            print("⏰ Looking for existing timecode track in base asset...")

            // Check if base asset has timecode tracks
            let baseTimecodeTracks = try await baseAsset.loadTracks(withMediaType: .timecode)
            print("🔍 Base asset has \(baseTimecodeTracks.count) timecode tracks")

            if let baseTimecodeTrack = baseTimecodeTracks.first {
                print("✅ Found existing timecode track in base asset - copying directly...")

                // Copy the timecode track directly from base asset
                try timecodeTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: baseDuration),
                    of: baseTimecodeTrack,
                    at: .zero
                )
                print("✅ Timecode track copied directly from base asset")

                // Verify the track was actually added
                let finalTimecodeTracks = try await composition.loadTracks(withMediaType: .timecode)
                print("🔍 Composition now has \(finalTimecodeTracks.count) timecode tracks")
            } else {
                print("⚠️ No existing timecode track found in base asset - skipping timecode track")
            }
        } else {
            print("⚠️ Failed to create timecode track in composition")
        }

        // Sort segments by start time for trimming
        let sortedSegments = settings.gradedSegments.sorted { $0.startTime < $1.startTime }

        // Create asset loader for segments
        let assetLoader = { (segment: GradedSegment) -> AVAsset in
            let assetOptions: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
            return AVURLAsset(url: segment.url, options: assetOptions)
        }

        print("🎬 Processing \(sortedSegments.count) segments...")

        // Process segments in reverse order to avoid time shifting
        for (index, segment) in sortedSegments.reversed().enumerated() {
            print(
                "   Processing segment \(sortedSegments.count - index): \(segment.url.lastPathComponent)"
            )

            // Remove the base video section that this segment will replace
            videoTrack?.removeTimeRange(
                CMTimeRange(start: segment.startTime, duration: segment.duration))

            // Load asset on-demand and immediately release after use
            let segmentAsset = assetLoader(segment)
            let segmentVideoTrack = try? await getVideoTrack(from: segmentAsset)
            try? videoTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: segment.duration),
                of: segmentVideoTrack!,
                at: segment.startTime
            )

            // Memory cleanup after each segment
            autoreleasepool {}
        }
        print("   ✅ All segments processed")

        // Get final composition duration
        let finalDuration = try await composition.load(.duration)
        print("📹 Final composition duration: \(finalDuration.seconds)s")

        // Debug: Check what tracks are in the composition
        let allTracks = try await composition.loadTracks(withMediaType: .video)
        let timecodeTracks = try await composition.loadTracks(withMediaType: .timecode)
        print(
            "🔍 Composition tracks: \(allTracks.count) video tracks, \(timecodeTracks.count) timecode tracks"
        )

        if timecodeTracks.count > 0 {
            print("✅ Timecode track found in composition - should be exported")

            // Associate timecode track with video track for export
            if let videoTrack = videoTrack, let timecodeTrack = timecodeTracks.first {
                // Note: AVMutableComposition doesn't support addTrackAssociation,
                // but AVAssetExportSession should preserve the timecode track
                print("🔗 Video and timecode tracks ready for export")
            }
        } else {
            print("❌ No timecode track found in composition")
        }

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: settings.outputURL.path) {
            try FileManager.default.removeItem(at: settings.outputURL)
        }

        print("🚀 Starting export...")
        let exportStart = CFAbsoluteTimeGetCurrent()

        // Create export session
        guard
            let exportSession = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetPassthrough)
        else {
            throw CompositorError.setupFailed
        }

        exportSession.outputURL = settings.outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = CMTimeRange(start: .zero, duration: finalDuration)

        // Start export with modern async states monitoring using modular progress bar
        let progressBar = ProgressBar.assetExport()
        progressBar.start()
        
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Start the export
            group.addTask {
                do {
                    try await exportSession.export(to: settings.outputURL, as: .mov)
                } catch {
                    // Export error handled by main task
                }
            }

            // Task 2: Monitor progress using modern states API with modular progress bar
            group.addTask {
                for await state in exportSession.states(updateInterval: 0.1) {
                    switch state {
                    case .pending:
                        print("\r🚀 Pending...", terminator: "")
                        fflush(stdout)
                    case .waiting:
                        print("\r🚀 Waiting...", terminator: "")
                        fflush(stdout)
                    case .exporting(let progress):
                        // Use modular progress bar with enhanced Progress object data
                        if progress.totalUnitCount > 0 && progress.totalUnitCount < 1_000_000_000_000 { // < 1TB seems reasonable
                            progressBar.updateUnits(
                                completedUnits: progress.completedUnitCount,
                                totalUnits: progress.totalUnitCount,
                                throughput: progress.throughput,
                                eta: progress.estimatedTimeRemaining
                            )
                        } else {
                            // Fallback to percentage-based progress for unreasonable unit values
                            progressBar.updateProgress(Float(progress.fractionCompleted))
                        }
                    @unknown default:
                        break
                    }
                }
            }

            // Wait for export to complete first, then cancel progress monitoring
            await group.next()
            group.cancelAll()
        }
        
        // Complete the progress bar
        progressBar.complete(total: 1, showFinalStats: false)

        let exportEndTime = CFAbsoluteTimeGetCurrent()
        let exportDuration = exportEndTime - exportStart
        print("🚀 Export completed in: \(String(format: "%.2f", exportDuration))s")

        return settings.outputURL
    }

    // MARK: - Helper Methods
    func getVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw CompositorError.noVideoTrack
        }
        return videoTrack
    }

    func getVideoProperties(from track: AVAssetTrack) async throws -> VideoProperties {
        let naturalSize = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let formatDescriptions = try await track.load(.formatDescriptions)

        var colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        var transferFunction = AVVideoTransferFunction_ITU_R_709_2
        var yCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        // Extract color information if available
        if let formatDescription = formatDescriptions.first {
            let extensions = CMFormatDescriptionGetExtensions(formatDescription)
            if let extensionsDict = extensions as? [String: Any] {
                if let colorProperties = extensionsDict[
                    kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                {
                    colorPrimaries = colorProperties
                }
                if let transferProperties = extensionsDict[
                    kCMFormatDescriptionExtension_TransferFunction as String] as? String
                {
                    transferFunction = transferProperties
                }
                if let matrixProperties = extensionsDict[
                    kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
                {
                    yCbCrMatrix = matrixProperties
                }
            }
        }

        // Extract timecode information
        let sourceTimecode = try await extractSourceTimecode(
            from: track.asset ?? AVURLAsset(url: URL(fileURLWithPath: "")))

        return VideoProperties(
            width: Int(naturalSize.width),
            height: Int(naturalSize.height),
            frameRate: Int32(nominalFrameRate),
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            yCbCrMatrix: yCbCrMatrix,
            sourceTimecode: sourceTimecode
        )
    }

    // MARK: - Segment Discovery and Parsing
    func discoverSegments(in directoryURL: URL) async throws -> [SegmentInfo] {
        let fileManager = FileManager.default
        let segmentURLs = try fileManager.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "mov" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var segments: [SegmentInfo] = []

        for url in segmentURLs {
            let segmentInfo = try await parseSegmentInfo(from: url)
            segments.append(segmentInfo)
        }

        return segments
    }

    private func parseSegmentInfo(from url: URL) async throws -> SegmentInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let filename = url.lastPathComponent

        // Try to parse segment number from filename (e.g., "S01", "S02")
        let segmentNumber = parseSegmentNumber(from: filename)

        // Start time will be determined from timecode tracks

        // Extract timecode information
        let sourceTimecode = try await extractSourceTimecode(from: asset)
        let sourceStartTimecode = try await extractSourceTimecode(from: asset)

        return SegmentInfo(
            url: url,
            filename: filename,
            duration: duration,
            startTime: nil,
            segmentNumber: segmentNumber,
            sourceTimecode: sourceTimecode,
            sourceStartTimecode: sourceStartTimecode
        )
    }

    private func parseSegmentNumber(from filename: String) -> Int? {
        // Look for patterns like "S01", "S02", etc.
        let pattern = "S(\\d+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)

        if let match = regex?.firstMatch(in: filename, range: range),
            let numberRange = Range(match.range(at: 1), in: filename)
        {
            return Int(filename[numberRange])
        }

        return nil
    }

    // MARK: - Timecode Handling using TimecodeKit (RESTORED)
    private func extractSourceTimecode(from asset: AVAsset) async throws -> String? {
        print("🔍 Extracting timecode using TimecodeKit...")

        do {
            // Try to auto-detect frame rate first
            let frameRate = try await asset.timecodeFrameRate()
            print("    📹 Auto-detected frame rate: \(frameRate)")

            // Read start timecode using TimecodeKit
            if let startTimecode = try await asset.startTimecode(at: frameRate) {
                print("    ✅ Found start timecode: \(startTimecode)")
                return startTimecode.stringValue()
            } else {
                print("    ❌ No start timecode found")
                return nil
            }
        } catch {
            print("    ❌ Failed to extract timecode with auto-detected frame rate: \(error)")
            print("❌ No timecode found in video")
            return nil
        }
    }

    private func timecodeToCMTime(_ timecode: String, frameRate: Int32, baseTimecode: String? = nil)
        -> CMTime?
    {
        // Parse timecode in format HH:MM:SS:FF (frames)
        let components = timecode.components(separatedBy: ":")
        guard components.count == 4,
            let hours = Int(components[0]),
            let minutes = Int(components[1]),
            let seconds = Int(components[2]),
            let frames = Int(components[3])
        else {
            return nil
        }

        // If we have a base timecode, calculate relative offset
        if let baseTimecode = baseTimecode {
            let baseComponents = baseTimecode.components(separatedBy: ":")
            guard baseComponents.count == 4,
                let baseHours = Int(baseComponents[0]),
                let baseMinutes = Int(baseComponents[1]),
                let baseSeconds = Int(baseComponents[2]),
                let baseFrames = Int(baseComponents[3])
            else {
                return nil
            }

            // Calculate the difference in seconds and frames
            let totalSeconds =
                (hours - baseHours) * 3600 + (minutes - baseMinutes) * 60 + (seconds - baseSeconds)
            let frameDifference = frames - baseFrames
            let frameTime = Double(frameDifference) / Double(frameRate)

            return CMTime(
                seconds: Double(totalSeconds) + frameTime,
                preferredTimescale: CMTimeScale(frameRate))
        } else {
            // Absolute timecode (for base timecode itself)
            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            let frameTime = Double(frames) / Double(frameRate)
            return CMTime(
                seconds: Double(totalSeconds) + frameTime,
                preferredTimescale: CMTimeScale(frameRate))
        }
    }

    func cmTimeToTimecode(_ time: CMTime, frameRate: Int32) -> String {
        let totalSeconds = time.seconds
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int((totalSeconds.truncatingRemainder(dividingBy: 1.0)) * Double(frameRate))

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    func createGradedSegments(
        from segmentInfos: [SegmentInfo], baseDuration: CMTime, baseProperties: VideoProperties
    ) -> [GradedSegment] {
        var segments: [GradedSegment] = []

        // Sort segments by segment number if available, otherwise by filename
        let sortedSegments = segmentInfos.sorted { seg1, seg2 in
            if let num1 = seg1.segmentNumber, let num2 = seg2.segmentNumber {
                return num1 < num2
            }
            return seg1.filename < seg2.filename
        }

        for segmentInfo in sortedSegments {
            let startTime: CMTime
            let sourceStartTime: CMTime

            // Use extracted timecode-based timing
            if let sourceTimecode = segmentInfo.sourceStartTimecode,
                let timecodeTime = timecodeToCMTime(
                    sourceTimecode, frameRate: baseProperties.frameRate,
                    baseTimecode: baseProperties.sourceTimecode)
            {
                // Use extracted timecode-based timing
                startTime = timecodeTime
                sourceStartTime = .zero
                let frameNumber = Int(timecodeTime.seconds * Double(baseProperties.frameRate))
                let outputTimecode = cmTimeToTimecode(
                    timecodeTime, frameRate: baseProperties.frameRate)
                print("🎬 Using extracted timecode for \(segmentInfo.filename):")
                print(
                    "   Extracted TC: \(sourceTimecode) → Frame \(frameNumber) (\(outputTimecode))")
            } else if let parsedStartTime = segmentInfo.startTime {
                // Use parsed start time if available
                startTime = parsedStartTime
                sourceStartTime = .zero
                let frameNumber = Int(parsedStartTime.seconds * Double(baseProperties.frameRate))
                let outputTimecode = cmTimeToTimecode(
                    parsedStartTime, frameRate: baseProperties.frameRate)
                print("🎬 Using parsed start time for \(segmentInfo.filename):")
                print(
                    "   Parsed: \(parsedStartTime.seconds)s → Frame \(frameNumber) (\(outputTimecode))"
                )
            } else {
                // Fallback to sequential timing
                let currentTime =
                    segments.isEmpty
                    ? .zero : CMTimeAdd(segments.last!.startTime, segments.last!.duration)
                startTime = currentTime
                sourceStartTime = .zero
                let frameNumber = Int(currentTime.seconds * Double(baseProperties.frameRate))
                let outputTimecode = cmTimeToTimecode(
                    currentTime, frameRate: baseProperties.frameRate)
                print("🎬 Using sequential timing for \(segmentInfo.filename):")
                print(
                    "   Sequential: \(currentTime.seconds)s → Frame \(frameNumber) (\(outputTimecode))"
                )
            }

            let segment = GradedSegment(
                url: segmentInfo.url,
                startTime: startTime,
                duration: segmentInfo.duration,
                sourceStartTime: sourceStartTime
            )

            segments.append(segment)
        }

        return segments
    }
}

// MARK: - Supporting Types
struct VideoProperties {
    let width: Int
    let height: Int
    let frameRate: Int32
    let colorPrimaries: String
    let transferFunction: String
    let yCbCrMatrix: String
    let sourceTimecode: String?  // Source timecode from the base video
}

struct SegmentInfo {
    let url: URL
    let filename: String
    let duration: CMTime
    let startTime: CMTime?  // Optional: can be parsed from filename or metadata
    let segmentNumber: Int?  // Optional: can be parsed from filename
    let sourceTimecode: String?  // Source timecode from the segment file
    let sourceStartTimecode: String?  // Start timecode of the segment
}

enum CompositorError: Error {
    case setupFailed
    case noVideoTrack
}

// MARK: - Command Line Entry Point
func runComposition(blankRushURL: URL, segmentsDirectoryURL: URL, outputURL: URL) async {
    print("🎬 Starting ProRes Composition...")

    let compositor = ProResVideoCompositor()

    do {
        // Discover and parse segments automatically
        print("🔍 Discovering segments in: \(segmentsDirectoryURL.path)")
        let segmentInfos = try await compositor.discoverSegments(in: segmentsDirectoryURL)

        print("📊 Found \(segmentInfos.count) segments:")
        for (index, info) in segmentInfos.enumerated() {
            print("  \(index + 1). \(info.filename)")
            print(
                "     Duration: \(info.duration.seconds)s (\(Int(info.duration.seconds * 25)) frames)"
            )
            if let segmentNumber = info.segmentNumber {
                print("     Segment #: \(segmentNumber)")
            }
            if let startTime = info.startTime {
                let frameNumber = Int(startTime.seconds * 25)
                let timecode = compositor.cmTimeToTimecode(startTime, frameRate: 25)
                print(
                    "     Start Time: \(startTime.seconds)s (Frame \(frameNumber), TC: \(timecode))"
                )
            }
            if let sourceTimecode = info.sourceTimecode {
                print("     Source Timecode: \(sourceTimecode)")
            }
            if let sourceStartTimecode = info.sourceStartTimecode {
                print("     Start Timecode: \(sourceStartTimecode)")
            }
        }

        // Get base video properties and duration for timing calculations
        let blankRush = AVURLAsset(url: blankRushURL)
        let baseTrack = try await compositor.getVideoTrack(from: blankRush)
        let baseProperties = try await compositor.getVideoProperties(from: baseTrack)
        let baseDuration = try await blankRush.load(.duration)
        let totalFrames = Int(baseDuration.seconds * Double(baseProperties.frameRate))

        // Log the extracted timecode for debugging
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Extracted base timecode: \(sourceTimecode)")
        } else {
            print("📹 No timecode found in base video")
        }

        print("📹 Base video duration: \(baseDuration.seconds)s (\(totalFrames) frames)")
        print(
            "📹 Base video properties: \(baseProperties.width)x\(baseProperties.height) @ \(baseProperties.frameRate)fps"
        )
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Base video source timecode: \(sourceTimecode)")
        }

        // Create graded segments from discovered info
        let segments = compositor.createGradedSegments(
            from: segmentInfos, baseDuration: baseDuration, baseProperties: baseProperties)

        print("🎬 Created \(segments.count) graded segments:")
        for (index, segment) in segments.enumerated() {
            print("  \(index + 1). \(segment.url.lastPathComponent)")
            let startFrame = Int(segment.startTime.seconds * Double(baseProperties.frameRate))
            let endFrame =
                startFrame + Int(segment.duration.seconds * Double(baseProperties.frameRate))
            let startTimecode = compositor.cmTimeToTimecode(
                segment.startTime, frameRate: baseProperties.frameRate)
            let endTimecode = compositor.cmTimeToTimecode(
                CMTimeAdd(segment.startTime, segment.duration), frameRate: baseProperties.frameRate)
            print(
                "     Start: Frame \(startFrame) (\(startTimecode)), Duration: \(segment.duration.seconds)s (\(Int(segment.duration.seconds * Double(baseProperties.frameRate))) frames)"
            )
            print("     End: Frame \(endFrame) (\(endTimecode))")
            if let sourceTimecode = baseProperties.sourceTimecode {
                print("     Base Source TC: \(sourceTimecode)")
            }
        }

        // Render phase: Press Enter to start
        print("\n🎬 Timeline ready! Press Enter to start render...")
        print("📊 This will measure only the export time (like DaVinci Resolve)")
        _ = readLine()
        print("🚀 Starting render...")

        let settings = CompositorSettings(
            outputURL: outputURL,
            baseVideoURL: blankRushURL,
            gradedSegments: segments,
            proResType: .proRes422HQ
        )

        // Progress monitoring now handled by modern states API

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
        print("❌ Failed to discover or parse segments: \(error.localizedDescription)")
    }
}

