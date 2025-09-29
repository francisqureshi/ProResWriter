//
//  printProcessFFmpeg.swift
//  ProResWriter
//
//  Created by Claude on 02/09/2025.
//  SwiftFFmpeg-based print process to avoid Premiere Pro "complex edit list" errors
//  Based on proven patterns from blankRushIntermediate.swift
//

import CoreMedia
import Foundation
import SwiftFFmpeg
import TimecodeKit

// MARK: - SwiftFFmpeg-based Data Models

// Video stream properties for caching (eliminate redundant analysis)
public struct VideoStreamProperties {
    public let width: Int
    public let height: Int
    public let frameRate: AVRational
    public let frameRateFloat: Float
    public let duration: Double
    public let timebase: AVRational
    public let timecode: String?

    public init(width: Int, height: Int, frameRate: AVRational, frameRateFloat: Float, duration: Double, timebase: AVRational, timecode: String?) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.frameRateFloat = frameRateFloat
        self.duration = duration
        self.timebase = timebase
        self.timecode = timecode
    }
}

public struct FFmpegGradedSegment {
    public let url: URL
    public let startTime: CMTime
    public let duration: CMTime
    public let sourceStartTime: CMTime
    public let isVFXShot: Bool  // VFX metadata from MediaFileInfo

    // SMPTE timecode information for precise frame calculation
    public let sourceTimecode: String?
    public let frameRate: Float?
    public let frameRateRational: AVRational?  // Exact rational for frame calculations
    public let isDropFrame: Bool?

    // Cached stream properties to eliminate redundant analysis
    public let cachedStreamProperties: VideoStreamProperties?

    public init(
        url: URL, startTime: CMTime, duration: CMTime, sourceStartTime: CMTime,
        isVFXShot: Bool = false,
        sourceTimecode: String? = nil, frameRate: Float? = nil,
        frameRateRational: AVRational? = nil, isDropFrame: Bool? = nil,
        cachedStreamProperties: VideoStreamProperties? = nil
    ) {
        self.url = url
        self.startTime = startTime
        self.duration = duration
        self.sourceStartTime = sourceStartTime
        self.isVFXShot = isVFXShot
        self.sourceTimecode = sourceTimecode
        self.frameRate = frameRate
        self.frameRateRational = frameRateRational
        self.isDropFrame = isDropFrame
        self.cachedStreamProperties = cachedStreamProperties
    }
}

public struct FFmpegCompositorSettings {
    public let outputURL: URL
    public let baseVideoURL: URL
    public let gradedSegments: [FFmpegGradedSegment]
    public let proResProfile: String  // "4" for ProRes 4444 like blank rush

    public init(
        outputURL: URL,
        baseVideoURL: URL,
        gradedSegments: [FFmpegGradedSegment],
        proResProfile: String = "4"  // ProRes 4444 default
    ) {
        self.outputURL = outputURL
        self.baseVideoURL = baseVideoURL
        self.gradedSegments = gradedSegments
        self.proResProfile = proResProfile
    }
}

// MARK: - SwiftFFmpeg ProRes Compositor

public class SwiftFFmpegProResCompositor {

    // Progress callback - reuse existing pattern from blank rush
    public var progressHandler: ((Double) -> Void)?
    public var completionHandler: ((Result<URL, Error>) -> Void)?

    // Progress tracking for timeline processing
    private var totalSegments: Int = 0
    private var completedSegments: Int = 0

    // DTS tracking for monotonicity
    private var lastOutputDTS: Int64 = 0

    public init() {
        // Initialize SwiftFFmpeg like blank rush
    }

    // MARK: - Public Interface

    public func composeVideo(with settings: FFmpegCompositorSettings) {
        Task {
            do {
                let outputURL = try await processCompositionFFmpeg(settings: settings)
                await MainActor.run {
                    completionHandler?(.success(outputURL))
                }
            } catch {
                print("❌ SwiftFFmpeg Composition error: \(error)")
                await MainActor.run {
                    completionHandler?(.failure(error))
                }
            }
        }
    }

    // MARK: - Core SwiftFFmpeg Processing (Based on Blank Rush Patterns)

    private func processCompositionFFmpeg(settings: FFmpegCompositorSettings) async throws -> URL {

        let totalStartTime = CFAbsoluteTimeGetCurrent()
        print("🔍 Starting SwiftFFmpeg composition process...")

        // 1. Analyze base video using SwiftFFmpeg (like blank rush)
        let analysisStartTime = CFAbsoluteTimeGetCurrent()
        print("📹 Analyzing base video with SwiftFFmpeg...")

        let baseProperties = try analyzeVideoWithFFmpeg(url: settings.baseVideoURL)

        let analysisEndTime = CFAbsoluteTimeGetCurrent()
        let analysisTime = analysisEndTime - analysisStartTime
        print("📹 SwiftFFmpeg analysis completed in: \(String(format: "%.3f", analysisTime))s")
        print(
            "✅ Base video properties: \(baseProperties.width)x\(baseProperties.height) @ \(String(format: "%.3f", baseProperties.frameRateFloat))fps"
        )

        // 2. Analyze and cache segment properties (eliminates redundant analysis)
        let segmentAnalysisStart = CFAbsoluteTimeGetCurrent()
        print("🔍 Analyzing and caching \(settings.gradedSegments.count) segment properties...")

        // Pre-analyze all segments and cache properties to eliminate duplicate analysis
        var segmentAnalysisTime: Double = 0
        var cachedSegments: [FFmpegGradedSegment] = []
        
        for (index, segment) in settings.gradedSegments.enumerated() {
            let segStartTime = CFAbsoluteTimeGetCurrent()
            let streamProperties = try analyzeVideoWithFFmpeg(url: segment.url)
            let segEndTime = CFAbsoluteTimeGetCurrent()
            segmentAnalysisTime += segEndTime - segStartTime
            
            // Create new segment with cached properties AND preserve frameRateRational
            let cachedSegment = FFmpegGradedSegment(
                url: segment.url,
                startTime: segment.startTime,
                duration: segment.duration,
                sourceStartTime: segment.sourceStartTime,
                isVFXShot: segment.isVFXShot,
                sourceTimecode: segment.sourceTimecode,
                frameRate: segment.frameRate,
                frameRateRational: segment.frameRateRational,  // MUST preserve the AVRational!
                isDropFrame: segment.isDropFrame,
                cachedStreamProperties: streamProperties
            )
            cachedSegments.append(cachedSegment)
            
            if index % 5 == 0 || index == settings.gradedSegments.count - 1 {
                print(
                    "  📊 Analyzed \(index + 1)/\(settings.gradedSegments.count) segments (\(String(format: "%.3f", segmentAnalysisTime))s total)"
                )
            }
        }

        let segmentAnalysisEnd = CFAbsoluteTimeGetCurrent()
        let totalSegmentAnalysisTime = segmentAnalysisEnd - segmentAnalysisStart
        print(
            "📊 Segment analysis completed in: \(String(format: "%.3f", totalSegmentAnalysisTime))s (avg: \(String(format: "%.3f", totalSegmentAnalysisTime / Double(settings.gradedSegments.count)))s per segment)"
        )

        // 3. Direct stream processing approach (no composition, no edit lists)
        let exportStartTime = CFAbsoluteTimeGetCurrent()
        print(
            "🚀 Using SwiftFFmpeg direct stream copying (avoiding edit lists for Premiere compatibility)..."
        )

        // Create settings with cached segments to eliminate redundant analysis
        let optimizedSettings = FFmpegCompositorSettings(
            outputURL: settings.outputURL,
            baseVideoURL: settings.baseVideoURL,
            gradedSegments: cachedSegments,
            proResProfile: settings.proResProfile
        )
        
        // Process timeline with direct stream copying (no more redundant analysis!)
        try await processTimelineDirectly(settings: optimizedSettings, baseProperties: baseProperties)

        let exportEndTime = CFAbsoluteTimeGetCurrent()
        let exportDuration = exportEndTime - exportStartTime
        print("🚀 SwiftFFmpeg export completed in: \(String(format: "%.3f", exportDuration))s")

        let totalEndTime = CFAbsoluteTimeGetCurrent()
        let totalTime = totalEndTime - totalStartTime

        // Performance breakdown
        print("\n📊 Performance Breakdown:")
        print(
            "  🔍 Base analysis: \(String(format: "%.3f", analysisTime))s (\(String(format: "%.1f", analysisTime/totalTime*100))%)"
        )
        print(
            "  📝 Segment analysis: \(String(format: "%.3f", totalSegmentAnalysisTime))s (\(String(format: "%.1f", totalSegmentAnalysisTime/totalTime*100))%)"
        )
        print(
            "  🚀 Stream copying: \(String(format: "%.3f", exportDuration))s (\(String(format: "%.1f", exportDuration/totalTime*100))%)"
        )
        print("  📊 Total: \(String(format: "%.3f", totalTime))s")

        return settings.outputURL
    }

    // MARK: - Video Analysis (Adapted from Blank Rush)

    private func analyzeVideoWithFFmpeg(url: URL) throws -> VideoStreamProperties {
        print("🔍 Opening format context for: \(url.lastPathComponent)")

        // Open input format context (like blank rush)
        let inputFormatContext = try AVFormatContext(url: url.path)
        try inputFormatContext.findStreamInfo()

        // Find video stream
        guard
            let videoStream = inputFormatContext.streams.first(where: {
                $0.codecParameters.width > 0 && $0.codecParameters.height > 0
            })
        else {
            throw FFmpegCompositorError.noVideoStream
        }

        print("✅ Found video stream at index \(videoStream.index)")
        print("   Codec: \(videoStream.codecParameters.codecId)")

        // Extract properties using blank rush patterns
        let codecParams = videoStream.codecParameters
        let width = Int(codecParams.width)
        let height = Int(codecParams.height)

        // Extract frame rate like blank rush
        let realFR = videoStream.realFramerate
        var frameRate: AVRational
        if realFR.den > 0 {
            frameRate = realFR
        } else {
            let avgFR = videoStream.averageFramerate
            if avgFR.den > 0 {
                frameRate = avgFR
            } else {
                throw FFmpegCompositorError.cannotDetermineFrameRate
            }
        }

        let frameRateFloat = Float(frameRate.num) / Float(frameRate.den)
        let duration = inputFormatContext.duration
        let durationInSeconds = Double(duration) / 1_000_000.0

        // Extract timecode like blank rush
        var timecode: String?
        if let formatTC = inputFormatContext.metadata["timecode"] {
            timecode = formatTC
            print("  📝 Found timecode in format metadata: \(formatTC)")
        } else if let streamTC = videoStream.metadata["timecode"] {
            timecode = streamTC
            print("  📝 Found timecode in stream metadata: \(streamTC)")
        }

        print("   Timebase: \(videoStream.timebase)")
        print("   Duration: \(String(format: "%.2f", durationInSeconds))s")

        return VideoStreamProperties(
            width: width,
            height: height,
            frameRate: frameRate,
            frameRateFloat: frameRateFloat,
            duration: durationInSeconds,
            timebase: videoStream.timebase,
            timecode: timecode
        )
    }

    // MARK: - Direct Timeline Processing (New Approach)

    private func processTimelineDirectly(
        settings: FFmpegCompositorSettings,
        baseProperties: VideoStreamProperties
    ) async throws {

        print("🎬 Processing timeline with direct stream copying...")

        // Separate VFX and regular segments using explicit metadata (from UI)
        let vfxSegments = settings.gradedSegments.filter { $0.isVFXShot }
        let regularSegments = settings.gradedSegments.filter { !$0.isVFXShot }

        // Initialize progress tracking
        totalSegments = regularSegments.count + vfxSegments.count + 1  // +1 for base video
        completedSegments = 0
        updateProgress()

        print("📊 Timeline segments: \(regularSegments.count) regular + \(vfxSegments.count) VFX")
        for (index, segment) in regularSegments.enumerated() {
            let startFrame = convertTimeToFrame(seconds: segment.startTime.seconds, frameRate: baseProperties.frameRate)
            print(
                "   Regular \(index + 1): \(segment.url.lastPathComponent) at frame \(startFrame)")
        }
        for (index, segment) in vfxSegments.enumerated() {
            let startFrame = convertTimeToFrame(seconds: segment.startTime.seconds, frameRate: baseProperties.frameRate)
            print("   VFX \(index + 1): \(segment.url.lastPathComponent) at frame \(startFrame)")
        }

        // Remove existing output file
        if FileManager.default.fileExists(atPath: settings.outputURL.path) {
            try FileManager.default.removeItem(at: settings.outputURL)
        }

        // Create output format context (like blank rush)
        let outputFormatContext = try AVFormatContext(
            format: nil, filename: settings.outputURL.path)

        // Set up timecode metadata early (from base video)
        if let timecode = baseProperties.timecode {
            outputFormatContext.metadata["timecode"] = timecode
            print("  🎬 Set timecode metadata: \(timecode)")
        }

        // Add video stream to output (using blank rush encoder setup)
        try setupOutputVideoStream(
            outputContext: outputFormatContext,
            baseProperties: baseProperties,
            settings: settings
        )

        // Open output file and write header
        if !outputFormatContext.outputFormat!.flags.contains(.noFile) {
            try outputFormatContext.openOutput(url: settings.outputURL.path, flags: .write)
        }

        try outputFormatContext.writeHeader()

        // Process timeline chronologically (base video + segments mixed in temporal order)
        try await processTimelineChronologically(
            baseURL: settings.baseVideoURL,
            regularSegments: regularSegments,
            vfxSegments: vfxSegments,
            outputContext: outputFormatContext,
            baseProperties: baseProperties
        )

        // Write trailer and close (like blank rush)
        try outputFormatContext.writeTrailer()

        print("✅ Timeline processing completed")
    }

    // MARK: - Stream Setup (Based on Blank Rush ProRes Encoding)

    private func setupOutputVideoStream(
        outputContext: AVFormatContext,
        baseProperties: VideoStreamProperties,
        settings: FFmpegCompositorSettings
    ) throws {

        let encoderSetupStart = CFAbsoluteTimeGetCurrent()
        print("🔧 Setting up ProRes VideoToolbox output stream...")

        // Find VideoToolbox ProRes encoder (like blank rush)
        guard let proresCodec = AVCodec.findEncoderByName("prores_videotoolbox") else {
            throw FFmpegCompositorError.proresEncoderNotFound
        }
        print("  🍎 Using VideoToolbox ProRes encoder (hardware acceleration)")

        // Add video stream
        guard let videoStream = outputContext.addStream() else {
            throw FFmpegCompositorError.failedToAddStream
        }

        // Create codec context with VideoToolbox settings (like blank rush)
        let codecContext = AVCodecContext(codec: proresCodec)
        codecContext.width = baseProperties.width
        codecContext.height = baseProperties.height
        // Use higher quality pixel format for ProRes 4444
        // AYUV64LE = 16-bit 4:4:4:4 with alpha (best for ProRes 4444)
        // YUV444P10LE = 10-bit 4:4:4 (high quality alternative)
        // YUV422P10LE = 10-bit 4:2:2 (better than 8-bit UYVY422)
        // SwiftFFmpeg doesn't expose all VideoToolbox formats - use best available\n        // p416le (16-bit 4:4:4) not available in SwiftFFmpeg, fall back to best option
        codecContext.pixelFormat = AVPixelFormat.UYVY422  // 8-bit 4:2:2 (limited by SwiftFFmpeg bindings)

        // Use exact timebase and framerate from base video (like blank rush)
        codecContext.timebase = AVRational(
            num: baseProperties.frameRate.den,
            den: baseProperties.frameRate.num
        )
        codecContext.framerate = baseProperties.frameRate

        // Open VideoToolbox encoder with ProRes profile and color metadata (like blank rush)
        try codecContext.openCodec(options: [
            "profile": settings.proResProfile,  // "4" for ProRes 4444
            "allow_sw": "0",  // Force hardware encoding
            "color_range": "tv",  // Broadcast legal range (16-235)
            "colorspace": "bt709",  // Standard HD color space
            "color_primaries": "bt709",  // Standard HD primaries
            "color_trc": "bt709",  // Standard HD gamma curve
        ])
        print("  🍎 VideoToolbox encoder opened with ProRes profile \(settings.proResProfile)")

        // Copy codec parameters to stream (like blank rush)
        videoStream.codecParameters.copy(from: codecContext)
        videoStream.timebase = codecContext.timebase
        videoStream.averageFramerate = baseProperties.frameRate

        print(
            "  ✅ Output video stream configured: \(baseProperties.width)x\(baseProperties.height) @ \(String(format: "%.3f", baseProperties.frameRateFloat))fps"
        )
    }

    // MARK: - Base Video Copying

    private func copyBaseVideoAsFoundation(
        baseURL: URL,
        outputContext: AVFormatContext,
        baseProperties: VideoStreamProperties
    ) async throws {

        print("📹 Copying base video stream as foundation...")

        // Reset DTS tracking for new composition
        lastOutputDTS = 0

        // Open base video input (blank rush)
        let inputFormatContext = try AVFormatContext(url: baseURL.path)
        try inputFormatContext.findStreamInfo()

        guard
            let inputVideoStream = inputFormatContext.streams.first(where: {
                $0.codecParameters.width > 0 && $0.codecParameters.height > 0
            })
        else {
            throw FFmpegCompositorError.noVideoStream
        }

        guard let outputVideoStream = outputContext.streams.first else {
            throw FFmpegCompositorError.failedToAddStream
        }

        // Copy all packets from base video (complete foundation)
        var packetCount = 0
        let packet = AVPacket()

        while true {
            do {
                try inputFormatContext.readFrame(into: packet)

                // Only process video stream packets
                if packet.streamIndex == inputVideoStream.index {
                    // Update stream index for output
                    packet.streamIndex = outputVideoStream.index

                    // Rescale timing from input to output timebase
                    packet.pts = AVMath.rescale(
                        packet.pts,
                        inputVideoStream.timebase,
                        outputVideoStream.timebase,
                        rounding: .nearInf,
                        passMinMax: true
                    )
                    // For ProRes (I-frame codec), DTS can equal PTS
                    packet.dts = packet.pts
                    lastOutputDTS = packet.dts
                    packet.duration = AVMath.rescale(
                        packet.duration,
                        inputVideoStream.timebase,
                        outputVideoStream.timebase
                    )

                    // Write packet to output (direct stream copy - no re-encoding)
                    try outputContext.interleavedWriteFrame(packet)
                    packetCount += 1
                }

                packet.unref()

            } catch let error as SwiftFFmpeg.AVError where error == .eof {
                break
            }
        }

        print("✅ Base video foundation copied: \(packetCount) packets")
    }

    // MARK: - Chronological Timeline Processing

    private func processTimelineChronologically(
        baseURL: URL,
        regularSegments: [FFmpegGradedSegment],
        vfxSegments: [FFmpegGradedSegment],
        outputContext: AVFormatContext,
        baseProperties: VideoStreamProperties
    ) async throws {

        print("📹 Processing complete timeline with segment replacements...")

        // Combine all segments and sort by start time
        let allSegments = (regularSegments + vfxSegments).sorted { $0.startTime < $1.startTime }

        // Open base video (blank rush) for reading
        let baseFormatContext = try AVFormatContext(url: baseURL.path)
        try baseFormatContext.findStreamInfo()

        guard
            let baseVideoStream = baseFormatContext.streams.first(where: {
                $0.codecParameters.width > 0 && $0.codecParameters.height > 0
            })
        else {
            throw FFmpegCompositorError.noVideoStream
        }

        guard let outputVideoStream = outputContext.streams.first else {
            throw FFmpegCompositorError.failedToAddStream
        }

        // Process entire timeline frame by frame with replacements
        try await processCompleteTimeline(
            baseContext: baseFormatContext,
            baseStream: baseVideoStream,
            segments: allSegments,
            outputContext: outputContext,
            outputVideoStream: outputVideoStream,
            baseProperties: baseProperties
        )

        print("✅ Complete timeline processing finished")
    }

    private func processCompleteTimeline(
        baseContext: AVFormatContext,
        baseStream: AVStream,
        segments: [FFmpegGradedSegment],
        outputContext: AVFormatContext,
        outputVideoStream: AVStream,
        baseProperties: VideoStreamProperties
    ) async throws {

        // Calculate total frames for the timeline
        let totalFrames = convertTimeToFrame(seconds: baseProperties.duration, frameRate: baseProperties.frameRate)

        // Use FrameOwnershipAnalyzer to resolve overlaps and VFX priority
        let analyzer = FrameOwnershipAnalyzer(
            baseProperties: baseProperties,
            segments: segments,
            totalFrames: totalFrames,
            verbose: true  // Enable for debugging
        )

        let processingPlan = try analyzer.analyze()

        // Log warnings if any
        for warning in processingPlan.overlapWarnings {
            print("⚠️ Overlap: \(warning)")
        }

        // Log statistics
        print("📊 Frame ownership analysis complete:")
        print("   Total frames: \(processingPlan.statistics.totalFrames)")
        print("   Segments: \(processingPlan.statistics.segmentCount) (\(processingPlan.statistics.vfxSegmentCount) VFX)")
        print("   Overlaps: \(processingPlan.statistics.overlapCount)")
        print("   VFX frames: \(processingPlan.statistics.vfxFrames)")
        print("   Grade frames: \(processingPlan.statistics.gradeFrames)")

        // Use the consolidated ranges from ProcessingPlan
        let streamCopyStartTime = CFAbsoluteTimeGetCurrent()
        print(
            "📹 Stream-copying \(totalFrames) frames with \(processingPlan.consolidatedRanges.count) segment insertions..."
        )

        // Process timeline with the pre-analyzed plan
        try await processTimelineWithProcessingPlan(
            baseContext: baseContext,
            baseStream: baseStream,
            processingPlan: processingPlan,
            outputContext: outputContext,
            outputVideoStream: outputVideoStream,
            baseProperties: baseProperties,
            totalFrames: totalFrames
        )

        print("✅ Stream-based timeline processing complete")

        // Overall stream copying performance summary
        let totalStreamCopyTime = CFAbsoluteTimeGetCurrent() - streamCopyStartTime
        let overallFPS = Double(totalFrames) / totalStreamCopyTime
        print(
            "📊 Stream copying summary: \(totalFrames) frames in \(String(format: "%.3f", totalStreamCopyTime))s (\(String(format: "%.1f", overallFPS)) fps overall)"
        )
    }

    private func processTimelineWithProcessingPlan(
        baseContext: AVFormatContext,
        baseStream: AVStream,
        processingPlan: ProcessingPlan,
        outputContext: AVFormatContext,
        outputVideoStream: AVStream,
        baseProperties: VideoStreamProperties,
        totalFrames: Int
    ) async throws {

        var currentFrame = 0
        var baseFramesRead = 0

        for range in processingPlan.consolidatedRanges {
            // 1. Copy base video from currentFrame to range start if there's a gap
            if currentFrame < range.startFrame {
                let framesToCopy = range.startFrame - currentFrame
                let baseCopyStart = CFAbsoluteTimeGetCurrent()
                print(
                    "🚀 Bulk copying base video: frames \(currentFrame)-\(range.startFrame-1) (\(framesToCopy) frames)"
                )

                try await copyBaseVideoFrames(
                    baseContext: baseContext,
                    baseStream: baseStream,
                    outputContext: outputContext,
                    outputVideoStream: outputVideoStream,
                    startFrame: currentFrame,
                    frameCount: framesToCopy,
                    baseFramesRead: &baseFramesRead,
                    baseProperties: baseProperties
                )

                let baseCopyEnd = CFAbsoluteTimeGetCurrent()
                let baseCopyTime = baseCopyEnd - baseCopyStart
                let baseFPS = Double(framesToCopy) / baseCopyTime
                print(
                    "✅ Base copying: \(framesToCopy) frames in \(String(format: "%.3f", baseCopyTime))s (\(String(format: "%.1f", baseFPS)) fps)"
                )

                currentFrame = range.startFrame
            }

            // 2. Copy segment frames with offset support for partial segments
            let segmentCopyStart = CFAbsoluteTimeGetCurrent()
            let segmentName = range.segment.url.lastPathComponent
            let isVFX = range.segment.isVFXShot ? " [VFX]" : ""
            print(
                "🎬 Inserting segment\(isVFX): \(segmentName) frames \(range.startFrame)-\(range.endFrame-1) (\(range.frameCount) frames, offset: \(range.segmentStartOffset))"
            )

            try await copySegmentFramesWithOffset(
                segment: range.segment,
                outputContext: outputContext,
                outputVideoStream: outputVideoStream,
                startFrame: range.startFrame,
                frameCount: range.frameCount,
                segmentStartOffset: range.segmentStartOffset,
                baseProperties: baseProperties
            )

            let segmentCopyEnd = CFAbsoluteTimeGetCurrent()
            let segmentCopyTime = segmentCopyEnd - segmentCopyStart
            let segmentFPS = Double(range.frameCount) / segmentCopyTime
            print(
                "✅ Segment copying: \(range.frameCount) frames in \(String(format: "%.3f", segmentCopyTime))s (\(String(format: "%.1f", segmentFPS)) fps)"
            )

            currentFrame = range.endFrame
        }

        // 3. Copy remaining base video to end
        if currentFrame < totalFrames {
            let remainingFrames = totalFrames - currentFrame
            let finalCopyStart = CFAbsoluteTimeGetCurrent()
            print(
                "🚀 Bulk copying final base video: frames \(currentFrame)-\(totalFrames-1) (\(remainingFrames) frames)"
            )

            try await copyBaseVideoFrames(
                baseContext: baseContext,
                baseStream: baseStream,
                outputContext: outputContext,
                outputVideoStream: outputVideoStream,
                startFrame: currentFrame,
                frameCount: remainingFrames,
                baseFramesRead: &baseFramesRead,
                baseProperties: baseProperties
            )

            let finalCopyEnd = CFAbsoluteTimeGetCurrent()
            let finalCopyTime = finalCopyEnd - finalCopyStart
            let finalFPS = Double(remainingFrames) / finalCopyTime
            print(
                "✅ Final base copying: \(remainingFrames) frames in \(String(format: "%.3f", finalCopyTime))s (\(String(format: "%.1f", finalFPS)) fps)"
            )
        }
    }

    private func copyBaseVideoFrames(
        baseContext: AVFormatContext,
        baseStream: AVStream,
        outputContext: AVFormatContext,
        outputVideoStream: AVStream,
        startFrame: Int,
        frameCount: Int,
        baseFramesRead: inout Int,
        baseProperties: VideoStreamProperties
    ) async throws {

        let packet = AVPacket()
        var framesCopied = 0
        
        // Calculate exact frame duration once for consistent timing
        let frameDuration = AVMath.rescale(
            1,  // One frame duration
            AVRational(num: baseProperties.frameRate.den, den: baseProperties.frameRate.num),
            outputVideoStream.timebase,
            rounding: .nearInf,
            passMinMax: true
        )
        
        // Calculate starting PTS for this segment
        let startPTS = Int64(startFrame) * frameDuration
        var currentPTS = startPTS

        // Skip to correct position if needed
        while baseFramesRead < startFrame {
            try baseContext.readFrame(into: packet)
            if packet.streamIndex == baseStream.index {
                baseFramesRead += 1
            }
            packet.unref()
        }

        // Bulk copy frames at passthrough speed with consistent timing
        while framesCopied < frameCount {
            try baseContext.readFrame(into: packet)

            if packet.streamIndex == baseStream.index {
                // Direct stream copy with minimal processing (FAST!)
                packet.streamIndex = outputVideoStream.index

                // Use consistent PTS increments instead of recalculating
                packet.pts = currentPTS
                packet.dts = currentPTS
                packet.duration = frameDuration

                // Direct write (passthrough speed!)
                try outputContext.interleavedWriteFrame(packet)

                framesCopied += 1
                baseFramesRead += 1
                lastOutputDTS = packet.dts
                
                // Increment PTS by exact frame duration for perfect timing
                currentPTS += frameDuration
            }

            packet.unref()
        }
    }

    private func copySegmentFramesWithOffset(
        segment: FFmpegGradedSegment,
        outputContext: AVFormatContext,
        outputVideoStream: AVStream,
        startFrame: Int,
        frameCount: Int,
        segmentStartOffset: Int,
        baseProperties: VideoStreamProperties
    ) async throws {

        // Open segment context for reading
        let segmentContext = try AVFormatContext(url: segment.url.path)

        // Use cached properties to eliminate expensive findStreamInfo() call!
        if segment.cachedStreamProperties != nil {
            print("    ⚡️ Using cached properties (skipping analysis!)")
            // Skip findStreamInfo() - we already have all the properties!
        } else {
            // Fallback: analyze if no cached properties (shouldn't happen)
            print("    ⚠️ No cached properties, analyzing segment...")
            let segmentAnalysisStart = CFAbsoluteTimeGetCurrent()
            try segmentContext.findStreamInfo()
            let segmentAnalysisEnd = CFAbsoluteTimeGetCurrent()
            let analysisTime = segmentAnalysisEnd - segmentAnalysisStart
            print("    🔍 Segment analysis: \(String(format: "%.3f", analysisTime))s")
        }

        guard
            let segmentVideoStream = segmentContext.streams.first(where: {
                $0.codecParameters.width > 0 && $0.codecParameters.height > 0
            })
        else {
            throw FFmpegCompositorError.noVideoStream
        }

        let packet = AVPacket()
        var framesSkipped = 0
        var framesCopied = 0

        // Calculate exact frame duration once for consistent timing
        let frameDuration = AVMath.rescale(
            1,  // One frame duration
            AVRational(num: baseProperties.frameRate.den, den: baseProperties.frameRate.num),
            outputVideoStream.timebase,
            rounding: .nearInf,
            passMinMax: true
        )

        // Calculate starting PTS using frame-based arithmetic for precision
        var currentPTS = Int64(startFrame) * frameDuration

        let segmentReadStart = CFAbsoluteTimeGetCurrent()

        if segmentStartOffset > 0 {
            print("🔍 Skipping \(segmentStartOffset) frames to reach offset...")
        }

        print("🚀 Bulk copying segment: \(frameCount) frames at passthrough speed")

        // Read and process segment frames
        while framesCopied < frameCount {
            do {
                try segmentContext.readFrame(into: packet)

                if packet.streamIndex == segmentVideoStream.index {
                    // Skip frames until we reach the offset
                    if framesSkipped < segmentStartOffset {
                        framesSkipped += 1
                        packet.unref()
                        continue
                    }

                    // Direct stream copy with continuous timeline (FAST!)
                    packet.streamIndex = outputVideoStream.index
                    packet.pts = currentPTS
                    packet.dts = currentPTS
                    packet.duration = frameDuration

                    // Direct write without re-encoding (passthrough!)
                    try outputContext.interleavedWriteFrame(packet)

                    framesCopied += 1
                    currentPTS += frameDuration
                    lastOutputDTS = packet.dts
                }

                packet.unref()
            } catch let error as SwiftFFmpeg.AVError where error == .eof {
                print("⚠️ Segment EOF after \(framesCopied) frames (expected \(frameCount))")
                break
            }
        }

        let segmentReadEnd = CFAbsoluteTimeGetCurrent()
        let segmentReadTime = segmentReadEnd - segmentReadStart
        let segmentReadFPS = Double(framesCopied) / segmentReadTime
        print(
            "✅ Segment passthrough: \(framesCopied) frames copied (skipped \(framesSkipped)) in \(String(format: "%.3f", segmentReadTime))s (\(String(format: "%.1f", segmentReadFPS)) fps)"
        )
    }

    private func writePacketToOutput(
        packet: AVPacket,
        outputContext: AVFormatContext,
        outputStream: AVStream,
        frameIndex: Int,
        sourceStream: AVStream,
        baseProperties: VideoStreamProperties
    ) async throws {

        // Update stream index for output
        packet.streamIndex = outputStream.index

        // Calculate frame-accurate PTS for output timeline
        let outputPTS = convertFramesToPTS(
            frame: frameIndex, frameRate: baseProperties.frameRate, timebase: outputStream.timebase)

        packet.pts = outputPTS
        packet.dts = outputPTS

        // Set duration for one frame in output timebase
        packet.duration = AVMath.rescale(
            1,  // One frame duration
            AVRational(num: 1, den: Int32(baseProperties.frameRateFloat)),
            outputStream.timebase,
            rounding: .nearInf,
            passMinMax: true
        )

        // Write packet to output
        try outputContext.interleavedWriteFrame(packet)

        lastOutputDTS = packet.dts
    }

    // MARK: - Segment Application

    private func applySegmentToTimeline(
        segment: FFmpegGradedSegment,
        outputContext: AVFormatContext,
        baseProperties: VideoStreamProperties,
        isVFX: Bool = false
    ) async throws {

        let segmentType = isVFX ? "VFX" : "regular"
        let startFrame = convertTimeToFrame(seconds: segment.startTime.seconds, frameRate: baseProperties.frameRate)
        let endFrame =
            startFrame + convertTimeToFrame(seconds: segment.duration.seconds, frameRate: baseProperties.frameRate)
        print("🎬 Applying \(segmentType) segment: \(segment.url.lastPathComponent)")
        print("   Timeline position: frame \(startFrame) - \(endFrame)")

        // Open segment input file
        let segmentFormatContext = try AVFormatContext(url: segment.url.path)
        try segmentFormatContext.findStreamInfo()

        guard
            let segmentVideoStream = segmentFormatContext.streams.first(where: {
                $0.codecParameters.width > 0 && $0.codecParameters.height > 0
            })
        else {
            throw FFmpegCompositorError.noVideoStream
        }

        guard let outputVideoStream = outputContext.streams.first else {
            throw FFmpegCompositorError.failedToAddStream
        }

        // Calculate precise timing for replacement
        let startPTS = convertFramesToPTS(
            frame: startFrame, frameRate: baseProperties.frameRate,
            timebase: outputVideoStream.timebase)
        let segmentStartPTS = convertTimeToPTS(
            time: segment.sourceStartTime, timebase: segmentVideoStream.timebase)
        let durationPTS = convertTimeToPTS(
            time: segment.duration, timebase: segmentVideoStream.timebase)

        print(
            "   Segment timing: start PTS \(startPTS), segment source \(segmentStartPTS), duration \(durationPTS)"
        )

        // Read and copy packets from segment within specified range
        var replacedPacketCount = 0
        let packet = AVPacket()
        var currentSegmentPTS = segmentStartPTS

        // Seek to segment start position if needed
        if segmentStartPTS > 0 {
            try segmentFormatContext.seekFrame(
                to: segmentStartPTS, streamIndex: segmentVideoStream.index, flags: .backward)
        }

        while currentSegmentPTS < segmentStartPTS + durationPTS {
            do {
                try segmentFormatContext.readFrame(into: packet)

                // Only process video stream packets within our time range
                if packet.streamIndex == segmentVideoStream.index && packet.pts >= segmentStartPTS
                    && packet.pts < segmentStartPTS + durationPTS
                {

                    // Update stream index for output
                    packet.streamIndex = outputVideoStream.index

                    // Calculate new PTS for timeline position (frame-accurate)
                    let relativePacketPTS = packet.pts - segmentStartPTS
                    let outputPTS =
                        startPTS
                        + AVMath.rescale(
                            relativePacketPTS,
                            segmentVideoStream.timebase,
                            outputVideoStream.timebase,
                            rounding: .nearInf,
                            passMinMax: true
                        )

                    // Set PTS and DTS (ProRes I-frame codec allows DTS = PTS)
                    packet.pts = outputPTS
                    packet.dts = outputPTS
                    lastOutputDTS = packet.dts

                    packet.duration = AVMath.rescale(
                        packet.duration,
                        segmentVideoStream.timebase,
                        outputVideoStream.timebase
                    )

                    // Write replacement packet to timeline (direct stream copy)
                    try outputContext.interleavedWriteFrame(packet)
                    replacedPacketCount += 1
                    currentSegmentPTS = packet.pts
                }

                packet.unref()

            } catch let error as SwiftFFmpeg.AVError where error == .eof {
                break
            }
        }

        print("  ✅ Segment applied: \(replacedPacketCount) packets replaced in timeline")
    }

    // MARK: - Timing Utilities

    private func convertFramesToPTS(frame: Int, frameRate: AVRational, timebase: AVRational)
        -> Int64
    {
        // Convert frame number to PTS using precise rational arithmetic
        let frameTime = Double(frame) / (Double(frameRate.num) / Double(frameRate.den))
        return Int64(frameTime * Double(timebase.den) / Double(timebase.num))
    }

    private func convertTimeToPTS(time: CMTime, timebase: AVRational) -> Int64 {
        // Convert CMTime to PTS using timebase
        return Int64(time.seconds * Double(timebase.den) / Double(timebase.num))
    }
    
    private func convertTimeToFrame(seconds: Double, frameRate: AVRational) -> Int {
        // Convert time to frame using precise rational arithmetic
        let fps = Double(frameRate.num) / Double(frameRate.den)
        return Int(round(seconds * fps))
    }
    
    private func calculateEndTimecode(
        startTC: String,
        durationSeconds: Double,
        frameRate: Float,
        isDropFrame: Bool
    ) -> String? {
        // Use SMPTE to calculate end timecode from start + duration
        let smpte = SMPTE(fps: Double(frameRate), dropFrame: isDropFrame)
        
        do {
            let startFrames = try smpte.getFrames(tc: startTC)
            let durationFrames = Int(round(durationSeconds * Double(frameRate)))
            let endFrames = startFrames + durationFrames - 1  // -1 because end is inclusive
            return try smpte.getTC(frames: endFrames)
        } catch {
            print("⚠️ Failed to calculate end timecode: \(error)")
            return nil
        }
    }

    // MARK: - Progress Updates

    private func updateProgress() {
        guard totalSegments > 0 else { return }
        let progress = Double(completedSegments) / Double(totalSegments)
        progressHandler?(progress)
    }
}

// MARK: - FFmpeg-specific Errors

enum FFmpegCompositorError: Error {
    case noVideoStream
    case cannotDetermineFrameRate
    case proresEncoderNotFound
    case failedToAddStream
    case streamProcessingFailed
    case segmentProcessingFailed
}

// MARK: - Conversion Bridge from AVFoundation Models

extension FFmpegGradedSegment {
    /// Convert from existing AVFoundation GradedSegment with VFX metadata from MediaFileInfo
    public static func from(gradedSegment: GradedSegment, mediaFileInfo: MediaFileInfo)
        -> FFmpegGradedSegment
    {
        return FFmpegGradedSegment(
            url: gradedSegment.url,
            startTime: gradedSegment.startTime,
            duration: gradedSegment.duration,
            sourceStartTime: gradedSegment.sourceStartTime,
            isVFXShot: mediaFileInfo.isVFXShot ?? false,
            sourceTimecode: mediaFileInfo.sourceTimecode,
            frameRate: mediaFileInfo.frameRateFloat,
            frameRateRational: mediaFileInfo.frameRate,  // Pass the exact AVRational
            isDropFrame: mediaFileInfo.isDropFrame
        )
    }
}

extension FFmpegCompositorSettings {
    /// Convert from existing AVFoundation CompositorSettings with MediaFileInfo for VFX metadata
    public init(from settings: CompositorSettings, mediaFiles: [MediaFileInfo]) {
        // Create lookup dictionary for VFX metadata
        let vfxLookup = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.fileName, $0) })

        // Convert graded segments with VFX metadata
        let ffmpegSegments = settings.gradedSegments.compactMap {
            gradedSegment -> FFmpegGradedSegment? in
            let fileName = gradedSegment.url.lastPathComponent
            guard let mediaFileInfo = vfxLookup[fileName] else {
                // Without MediaFileInfo, we can't get frame rate data - this should never happen
                // in production since all segments should have been analyzed during import
                print("❌ Error: No MediaFileInfo found for segment \(fileName)")
                print("   This segment is missing critical frame rate data from import stage")
                // We cannot proceed without frame rate data
                return nil
            }

            return FFmpegGradedSegment.from(
                gradedSegment: gradedSegment, mediaFileInfo: mediaFileInfo)
        }

        // Convert ProRes type to profile string (like blank rush)
        let profileString: String
        switch settings.proResType {
        case .proRes422:
            profileString = "2"
        case .proRes422HQ:
            profileString = "3"
        case .proRes4444:
            profileString = "4"  // ProRes 4444 (highest quality)
        case .proRes422LT:
            profileString = "1"
        case .proRes422Proxy:
            profileString = "0"
        default:
            profileString = "3"  // Default to 422 HQ
        }

        self.init(
            outputURL: settings.outputURL,
            baseVideoURL: settings.baseVideoURL,
            gradedSegments: ffmpegSegments,
            proResProfile: profileString
        )
    }
}

// MARK: - Utility Extensions

extension CMTime {
    /// Convert to frame number using frame rate
    func toFrameNumber(frameRate: Float) -> Int {
        return Int(self.seconds * Double(frameRate))
    }
}
