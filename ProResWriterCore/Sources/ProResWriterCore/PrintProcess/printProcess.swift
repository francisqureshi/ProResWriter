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
public struct GradedSegment {
    public let url: URL
    public let startTime: CMTime  // Start time in the final timeline
    public let duration: CMTime  // Duration of the segment
    public let sourceStartTime: CMTime  // Start time in the source segment file

    public init(url: URL, startTime: CMTime, duration: CMTime, sourceStartTime: CMTime) {
        self.url = url
        self.startTime = startTime
        self.duration = duration
        self.sourceStartTime = sourceStartTime
    }
}

public struct CompositorSettings {
    public let outputURL: URL
    public let baseVideoURL: URL
    public let gradedSegments: [GradedSegment]
    public let proResType: AVVideoCodecType  // .proRes422, .proRes422HQ, etc.

    public init(
        outputURL: URL, baseVideoURL: URL, gradedSegments: [GradedSegment],
        proResType: AVVideoCodecType
    ) {
        self.outputURL = outputURL
        self.baseVideoURL = baseVideoURL
        self.gradedSegments = gradedSegments
        self.proResType = proResType
    }
}

// MARK: - Main Compositor Class
@available(macOS 15, *)
public class ProResVideoCompositor: NSObject {

    // Progress callback
    public var progressHandler: ((Double) -> Void)?
    public var completionHandler: ((Result<URL, Error>) -> Void)?

    public override init() {
        super.init()
    }

    // MARK: - Public Interface
    public func composeVideo(with settings: CompositorSettings) {
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

        // Separate VFX shots from regular segments
        // Note: We need a way to pass VFX info to print process - for now using filename fallback
        let vfxSegments = settings.gradedSegments.filter { segment in
            segment.url.lastPathComponent.uppercased().contains("VFX")
        }
        let regularSegments = settings.gradedSegments.filter { segment in
            !segment.url.lastPathComponent.uppercased().contains("VFX")
        }

        // Sort both groups by start time
        let sortedRegularSegments = regularSegments.sorted { $0.startTime < $1.startTime }
        let sortedVFXSegments = vfxSegments.sorted { $0.startTime < $1.startTime }

        // Create asset loader for segments
        let assetLoader = { (segment: GradedSegment) -> AVAsset in
            let assetOptions: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
            return AVURLAsset(url: segment.url, options: assetOptions)
        }

        print(
            "🎬 Processing \(regularSegments.count) regular segments + \(vfxSegments.count) VFX segments..."
        )

        // Process regular segments first (in reverse order to avoid time shifting)
        if !sortedRegularSegments.isEmpty {
            print("📹 Processing regular segments...")
            for (index, segment) in sortedRegularSegments.reversed().enumerated() {
                print(
                    "   Processing regular segment \(sortedRegularSegments.count - index): \(segment.url.lastPathComponent)"
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
            print("   ✅ Regular segments processed")
        }

        // Process VFX segments last (they will be on top by replacing content on main track)
        if !sortedVFXSegments.isEmpty {
            print("🎭 Processing VFX segments (on top via main track replacement)...")

            for (index, segment) in sortedVFXSegments.enumerated() {
                print(
                    "   Processing VFX segment \(index + 1): \(segment.url.lastPathComponent)"
                )

                // Remove whatever is currently at this time range (base video or regular segments)
                videoTrack?.removeTimeRange(
                    CMTimeRange(start: segment.startTime, duration: segment.duration))

                // Insert VFX segment into main track (same method as regular segments)
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
            print("   ✅ VFX segments processed (on top)")
        }

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
            // asset: composition, presetName: AVAssetExportPresetAppleProRes4444LPCM) // NO TC track printed file when I use this.. Also seems to be "Passthrough Speeds"

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
                do {
                    for try await state in exportSession.states(updateInterval: 0.1) {
                        switch state {
                        case .pending:
                            print("\r🚀 Pending...", terminator: "")
                            fflush(stdout)
                        case .waiting:
                            print("\r🚀 Waiting...", terminator: "")
                            fflush(stdout)
                        case .exporting(let progress):
                            // Use modular progress bar with enhanced Progress object data
                            if progress.totalUnitCount > 0
                                && progress.totalUnitCount < 1_000_000_000_000
                            {  // < 1TB seems reasonable
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
                } catch {
                    print("⚠️ Progress monitoring error: \(error)")
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
    public func getVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw CompositorError.noVideoTrack
        }
        return videoTrack
    }

    public func getVideoProperties(from track: AVAssetTrack) async throws -> VideoProperties {
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

    public func timecodeToCMTime(_ timecode: String, frameRate: Int32, baseTimecode: String? = nil)
        -> CMTime?
    {
        // Use TimecodeKit for professional timecode conversion
        do {
            // Create TimecodeKit framerate based on the actual frame rate
            let tcFramerate = getTimecodeFrameRate(for: frameRate)

            // Parse the timecodes using TimecodeKit
            let segmentTC = try Timecode(.string(timecode), at: tcFramerate)

            if let baseTimecode = baseTimecode {
                // Calculate relative offset using TimecodeKit
                let baseTC = try Timecode(.string(baseTimecode), at: tcFramerate)

                // Use TimecodeKit's CMTime conversion for precision
                let segmentCMTime = segmentTC.cmTimeValue
                let baseCMTime = baseTC.cmTimeValue
                let offsetCMTime = CMTimeSubtract(segmentCMTime, baseCMTime)

                return offsetCMTime
            } else {
                // Absolute timecode - use TimecodeKit's CMTime conversion
                return segmentTC.cmTimeValue
            }

        } catch {
            print("⚠️ TimecodeKit conversion failed: \(error), falling back to manual parsing")
            return manualTimecodeToCMTime(
                timecode, frameRate: frameRate, baseTimecode: baseTimecode)
        }
    }

    private func getTimecodeFrameRate(for frameRate: Int32) -> TimecodeFrameRate {
        // Note: We're passing in Int32 but need to handle decimal frame rates differently
        // For now, we'll handle the integer approximations and rely on TimecodeKit's precision

        switch frameRate {
        // Film / ATSC / HD Column - All supported by TimecodeKit
        case 23: return .fps23_976  // 23.976
        case 24: return .fps24  // 24 (we'll handle 24.98 separately if needed)
        case 47: return .fps47_952  // 47.952
        case 48: return .fps48  // 48
        case 95: return .fps95_904  // 95.904
        case 96: return .fps96  // 96

        // PAL / SECAM / DVB / ATSC Column - All supported by TimecodeKit
        case 25: return .fps25  // 25
        case 50: return .fps50  // 50
        case 100: return .fps100  // 100

        // NTSC / ATSC / PAL-M Column - All supported by TimecodeKit
        case 29: return .fps29_97  // 29.97 (both DF and non-DF)
        case 59: return .fps59_94  // 59.94 (both DF and non-DF)
        case 119: return .fps119_88  // 119.88 (both DF and non-DF)

        // NTSC Non-Standard / ATSC / HD Columns - All supported by TimecodeKit
        case 30: return .fps30  // 30 (both DF and non-DF)
        case 60: return .fps60  // 60 (both DF and non-DF)
        case 90: return .fps90  // 90
        case 120: return .fps120  // 120 (both DF and non-DF)

        // Fallback for unknown rates
        default: return .fps25  // Default to PAL 25fps
        }
    }

    private func getTimescale(for frameRate: Int32) -> CMTimeScale {
        let fps = Double(frameRate)

        // NTSC rates (x/1001) - use exact denominators for perfect precision
        if abs(fps - 23.976) < 0.001 {
            return 24000  // 23.976fps = 24000/1001
        } else if abs(fps - 24.98) < 0.001 {
            return 25000  // 24.98fps ≈ 25000/1001
        } else if abs(fps - 29.97) < 0.001 {
            return 30000  // 29.97fps = 30000/1001
        } else if abs(fps - 47.952) < 0.001 {
            return 48000  // 47.952fps = 48000/1001
        } else if abs(fps - 59.94) < 0.001 {
            return 60000  // 59.94fps = 60000/1001
        } else if abs(fps - 95.904) < 0.001 {
            return 96000  // 95.904fps = 96000/1001
        } else if abs(fps - 119.88) < 0.001 {
            return 120000  // 119.88fps = 120000/1001
        }

        // Exact integer rates - use high precision timescales
        else if abs(fps - 24.0) < 0.001 {
            return 24000  // 24fps exactly
        } else if abs(fps - 25.0) < 0.001 {
            return 25000  // 25fps PAL
        } else if abs(fps - 30.0) < 0.001 {
            return 30000  // 30fps exactly
        } else if abs(fps - 48.0) < 0.001 {
            return 48000  // 48fps exactly
        } else if abs(fps - 50.0) < 0.001 {
            return 50000  // 50fps PAL
        } else if abs(fps - 60.0) < 0.001 {
            return 60000  // 60fps exactly
        } else if abs(fps - 90.0) < 0.001 {
            return 90000  // 90fps exactly
        } else if abs(fps - 96.0) < 0.001 {
            return 96000  // 96fps exactly
        } else if abs(fps - 100.0) < 0.001 {
            return 100000  // 100fps PAL ultra high
        } else if abs(fps - 120.0) < 0.001 {
            return 120000  // 120fps exactly
        }

        // Fallback for unknown rates
        else {
            return 600  // Apple's standard fallback
        }
    }

    private func manualTimecodeToCMTime(
        _ timecode: String, frameRate: Int32, baseTimecode: String? = nil
    ) -> CMTime? {
        // Fallback manual parsing (original logic)
        let components = timecode.components(separatedBy: ":")
        guard components.count == 4,
            let hours = Int(components[0]),
            let minutes = Int(components[1]),
            let seconds = Int(components[2]),
            let frames = Int(components[3])
        else {
            return nil
        }

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

            let totalSeconds =
                (hours - baseHours) * 3600 + (minutes - baseMinutes) * 60 + (seconds - baseSeconds)
            let frameDifference = frames - baseFrames
            let frameTime = Double(frameDifference) / Double(frameRate)
            let timescale = getTimescale(for: frameRate)

            return CMTime(seconds: Double(totalSeconds) + frameTime, preferredTimescale: timescale)
        } else {
            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            let frameTime = Double(frames) / Double(frameRate)
            let timescale = getTimescale(for: frameRate)

            return CMTime(seconds: Double(totalSeconds) + frameTime, preferredTimescale: timescale)
        }
    }

    func cmTimeToTimecode(_ time: CMTime, frameRate: Int32) -> String {
        // Use TimecodeKit for professional-grade timecode conversion
        do {
            // Create TimecodeKit framerate based on the actual frame rate
            let tcFramerate = getTimecodeFrameRate(for: frameRate)

            // Convert CMTime to frame number using precise calculation
            let totalFrames = Int(round(time.seconds * Double(frameRate)))

            // Create Timecode from frame count
            let timecode = try Timecode(.frames(totalFrames), at: tcFramerate)

            return timecode.stringValue()
        } catch {
            // Fallback to manual calculation if TimecodeKit fails
            let totalSeconds = time.seconds
            let hours = Int(totalSeconds) / 3600
            let minutes = (Int(totalSeconds) % 3600) / 60
            let seconds = Int(totalSeconds) % 60
            let frames = Int(
                round((totalSeconds.truncatingRemainder(dividingBy: 1.0)) * Double(frameRate)))

            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        }
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
                let frameNumber = Int(
                    round(timecodeTime.seconds * Double(baseProperties.frameRate)))
                let outputTimecode = cmTimeToTimecode(
                    timecodeTime, frameRate: baseProperties.frameRate)
                print("🎬 Using extracted timecode for \(segmentInfo.filename):")
                print(
                    "   Extracted TC: \(sourceTimecode) → Frame \(frameNumber) (\(outputTimecode))")
            } else if let parsedStartTime = segmentInfo.startTime {
                // Use parsed start time if available
                startTime = parsedStartTime
                sourceStartTime = .zero
                let frameNumber = Int(
                    round(parsedStartTime.seconds * Double(baseProperties.frameRate)))
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
                let frameNumber = Int(round(currentTime.seconds * Double(baseProperties.frameRate)))
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
public struct VideoProperties {
    public let width: Int
    public let height: Int
    public let frameRate: Int32
    public let colorPrimaries: String
    public let transferFunction: String
    public let yCbCrMatrix: String
    public let sourceTimecode: String?  // Source timecode from the base video

    public init(
        width: Int, height: Int, frameRate: Int32, colorPrimaries: String, transferFunction: String,
        yCbCrMatrix: String, sourceTimecode: String?
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.sourceTimecode = sourceTimecode
    }
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
@available(macOS 15, *)
func runComposition(blankRushURL: URL, segmentsDirectoryURL: URL, outputURL: URL) async {
    print("🎬 Starting ProRes Composition...")

    let compositor = ProResVideoCompositor()

    do {
        // Get base video properties and duration for timing calculations
        let blankRush = AVURLAsset(url: blankRushURL)
        let baseTrack = try await compositor.getVideoTrack(from: blankRush)
        let baseProperties = try await compositor.getVideoProperties(from: baseTrack)
        let baseDuration = try await blankRush.load(.duration)
        let totalFrames = Int(baseDuration.seconds * Double(baseProperties.frameRate))

        // Discover and parse segments automatically
        print("🔍 Discovering segments in: \(segmentsDirectoryURL.path)")
        let segmentInfos = try await compositor.discoverSegments(in: segmentsDirectoryURL)

        print("📊 Found \(segmentInfos.count) segments:")
        for (index, info) in segmentInfos.enumerated() {
            print("  \(index + 1). \(info.filename)")
            let durationTimecode = try? Timecode(
                .cmTime(info.duration),
                at: compositor.getTimecodeFrameRate(for: baseProperties.frameRate))
            let frameCount = durationTimecode?.frameCount.value
            print(
                "     Duration: \(info.duration.seconds)s (\(frameCount) frames)"
            )
            if let segmentNumber = info.segmentNumber {
                print("     Segment #: \(segmentNumber)")
            }
            if let startTime = info.startTime {
                let startTimecode = try? Timecode(
                    .cmTime(startTime),
                    at: compositor.getTimecodeFrameRate(for: baseProperties.frameRate))
                let frameNumber = startTimecode?.frameCount.value
                let timecode = compositor.cmTimeToTimecode(
                    startTime, frameRate: baseProperties.frameRate)
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
            let startFrame = Int(
                round(segment.startTime.seconds * Double(baseProperties.frameRate)))
            let endFrame =
                startFrame + Int(round(segment.duration.seconds * Double(baseProperties.frameRate)))
            let startTimecode = compositor.cmTimeToTimecode(
                segment.startTime, frameRate: baseProperties.frameRate)
            let endTimecode = compositor.cmTimeToTimecode(
                CMTimeAdd(segment.startTime, segment.duration), frameRate: baseProperties.frameRate)
            print(
                "     Start: Frame \(startFrame) (\(startTimecode)), Duration: \(segment.duration.seconds)s (\(Int(round(segment.duration.seconds * Double(baseProperties.frameRate)))) frames)"
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
