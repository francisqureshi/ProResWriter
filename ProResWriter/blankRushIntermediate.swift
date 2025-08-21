//
//  blankRushCreator.swift
//  ProResWriter
//
//  Created by Claude on 17/08/2025.
//

import Foundation
import SwiftFFmpeg

// MARK: - Blank Rush Creation

struct BlankRushResult {
    let originalOCF: MediaFileInfo
    let blankRushURL: URL
    let success: Bool
    let error: String?
}

struct TimecodeBlackFramesError: Error {
    let message: String
}

struct BlankRushVideoProperties {
    let width: Int
    let height: Int
    let frameRate: AVRational
    let duration: Double
    let sampleAspectRatio: AVRational?
    let company: String?
    let finalWidth: Int
    let finalHeight: Int
    let timecode: String
    let isDropFrame: Bool  // Drop frame timecode information
}

class BlankRushIntermediate {

    private let projectBlankRushDirectory: String

    init(
        projectDirectory: String =
            // "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush"
            "/Users/fq/Movies/ProResWriter/SwiftFFmpeg_out"
    ) {
        self.projectBlankRushDirectory = projectDirectory
    }

    /// Create blank rush files for all OCF parents that have children
    func createBlankRushes(from linkingResult: LinkingResult) async -> [BlankRushResult] {
        print("🎬 Creating blank rushes for \(linkingResult.ocfParents.count) OCF parents...")

        // Ensure output directory exists
        let outputURL = URL(fileURLWithPath: projectBlankRushDirectory)
        createDirectoryIfNeeded(at: outputURL)

        var results: [BlankRushResult] = []

        // Process each OCF parent that has children
        for parent in linkingResult.ocfParents {
            if parent.hasChildren {
                print("\n📁 Processing \(parent.ocf.fileName) with \(parent.childCount) children...")

                let result = await createBlankRush(for: parent.ocf, outputDirectory: outputURL)
                results.append(result)

                if result.success {
                    print("  ✅ Created: \(result.blankRushURL.lastPathComponent)")
                } else {
                    print("  ❌ Failed: \(result.error ?? "Unknown error")")
                }
            } else {
                print("📂 Skipping \(parent.ocf.fileName) (no children)")

                // Still add to results for completeness
                results.append(
                    BlankRushResult(
                        originalOCF: parent.ocf,
                        blankRushURL: URL(fileURLWithPath: ""),
                        success: false,
                        error: "No children segments found"
                    ))
            }
        }

        let successCount = results.filter { $0.success }.count
        print("\n🎬 Blank rush creation complete: \(successCount)/\(results.count) succeeded")

        return results
    }

    /// Create blank rush for a single OCF file
    private func createBlankRush(for ocf: MediaFileInfo, outputDirectory: URL) async
        -> BlankRushResult
    {

        // Generate output filename: originalName_blankRush.mov
        let baseName = (ocf.fileName as NSString).deletingPathExtension
        let outputFileName = "\(baseName)_blankRush.mov"
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)

        // Generate black frames using MediaFileInfo metadata
        do {
            let success = try await generateBlankRushFromOCF(
                ocfFile: ocf,
                outputPath: outputURL.path
            )

            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: success,
                error: success ? nil : "ProRes transcoding failed"
            )

        } catch {
            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: false,
                error: "Error transcoding: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Black Frame Generation

    /// Generate black frames using MediaFileInfo metadata (main method)
    public func generateBlankRushFromOCF(ocfFile: MediaFileInfo, outputPath: String) async throws
        -> Bool
    {

        print("  🖤 Starting black frame generation with MediaFileInfo...")
        print("  📝 Input: \(ocfFile.fileName)")
        print("  📝 Output: \(outputPath)")
        print(
            "  🎬 Using metadata: \(ocfFile.frameRateDescription), \(ocfFile.durationInFrames ?? 0) frames"
        )

        do {
            try await Task {
                try generateBlackFramesFromMediaFileInfo(ocfFile: ocfFile, outputPath: outputPath)
            }.value

            print("  ✅ Black frame generation completed successfully!")
            return true

        } catch {
            print("  ❌ Black frame generation failed: \(error)")
            return false
        }
    }

    /// Legacy method for path-based black frame generation (for testing)
    public func generateBlackFramesToProRes(inputPath: String, outputPath: String) async throws
        -> Bool
    {

        print("  🖤 Starting black frame generation from file path...")
        print("  📝 Input (for metadata): \(inputPath)")
        print("  📝 Output: \(outputPath)")

        do {
            try await Task {
                try generateBlackFramesFromFilePath(inputPath: inputPath, outputPath: outputPath)
            }.value

            print("  ✅ Black frame generation completed successfully!")
            return true

        } catch {
            print("  ❌ Black frame generation failed: \(error)")
            return false
        }
    }

    /// Generate black frames using pre-analyzed MediaFileInfo metadata
    private func generateBlackFramesFromMediaFileInfo(ocfFile: MediaFileInfo, outputPath: String)
        throws
    {

        print("  📝 Processing with MediaFileInfo: \(ocfFile.fileName) -> \(outputPath)")

        let inputPath = ocfFile.url.path

        // Input validation
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw TimecodeBlackFramesError(message: "Input file '\(inputPath)' not found!")
        }

        // Use pre-analyzed metadata instead of re-extracting
        guard let frameRate = ocfFile.frameRate else {
            throw TimecodeBlackFramesError(message: "No frame rate available in MediaFileInfo")
        }

        // Use display resolution (SAR-corrected if available) or fall back to coded resolution
        let targetResolution = ocfFile.displayResolution ?? ocfFile.resolution
        guard let resolution = targetResolution else {
            throw TimecodeBlackFramesError(message: "No resolution available in MediaFileInfo")
        }

        // Convert float frame rate to proper AVRational for common professional rates
        let frameRateRational = convertToAVRational(frameRate: frameRate)

        let sourceProperties = BlankRushVideoProperties(
            width: Int(resolution.width),
            height: Int(resolution.height),
            frameRate: frameRateRational,
            duration: Double(ocfFile.durationInFrames ?? 0) / Double(frameRate),
            sampleAspectRatio: nil,  // Could parse from ocfFile.sampleAspectRatio if needed
            company: nil,  // Could add to MediaFileInfo if needed
            finalWidth: Int(resolution.width),
            finalHeight: Int(resolution.height),
            timecode: ocfFile.sourceTimecode ?? "00:00:00:00",
            isDropFrame: ocfFile.isDropFrame ?? false
        )

        print(
            "  📝 Using pre-analyzed properties: \(sourceProperties.width)x\(sourceProperties.height) at \(sourceProperties.frameRate)"
        )
        print(
            "  📝 Duration: \(String(format: "%.2f", sourceProperties.duration))s, \(ocfFile.durationInFrames ?? 0) frames"
        )
        print("  📝 Timecode: \(sourceProperties.timecode)")

        // Generate synthetic black frames with metadata from source
        try generateBlackFramesToProRes(
            outputPath: outputPath,
            properties: sourceProperties
        )

        print("  ✅ Black frame generation with MediaFileInfo completed: \(outputPath)")
    }

    /// Generate black frames by extracting metadata from file path (legacy method)
    private func generateBlackFramesFromFilePath(inputPath: String, outputPath: String) throws {

        print("  📝 Processing from file path: \(inputPath) -> \(outputPath)")

        // Input validation
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw TimecodeBlackFramesError(message: "Input file '\(inputPath)' not found!")
        }

        // Extract metadata from source file
        let sourceProperties = try extractSourceProperties(from: inputPath)
        print(
            "  📝 Extracted properties: \(sourceProperties.width)x\(sourceProperties.height) at \(sourceProperties.frameRate)"
        )
        print("  📝 Duration: \(String(format: "%.2f", sourceProperties.duration))s")
        print("  📝 Timecode: \(sourceProperties.timecode)")

        // Generate black frames
        try generateBlackFramesToProRes(
            outputPath: outputPath,
            properties: sourceProperties
        )

        print("  ✅ Black frame generation from file path completed: \(outputPath)")
    }

    /// Convert frame rate float to AVRational for professional rates
    private func convertToAVRational(frameRate: Float) -> AVRational {
        if abs(frameRate - 23.976025) < 0.001 {
            return AVRational(num: 24000, den: 1001)
        } else if abs(frameRate - 29.97) < 0.001 {
            return AVRational(num: 30000, den: 1001)
        } else if abs(frameRate - 59.94006) < 0.001 {
            return AVRational(num: 60000, den: 1001)
        } else if abs(frameRate - 24.0) < 0.001 {
            return AVRational(num: 24, den: 1)
        } else if abs(frameRate - 25.0) < 0.001 {
            return AVRational(num: 25, den: 1)
        } else if abs(frameRate - 30.0) < 0.001 {
            return AVRational(num: 30, den: 1)
        } else {
            // Fallback for unusual frame rates
            return AVRational(num: Int32(frameRate * 1000), den: 1000)
        }
    }

    /// Extract properties from source file without decoding video content
    private func extractSourceProperties(from inputPath: String) throws -> BlankRushVideoProperties
    {

        let inputFormatContext = try AVFormatContext(url: inputPath)
        try inputFormatContext.findStreamInfo()

        // Find first video stream
        guard
            let videoStream = inputFormatContext.streams.first(where: {
                $0.codecParameters.width > 0 && $0.codecParameters.height > 0
            })
        else {
            throw TimecodeBlackFramesError(message: "No video stream found in input file")
        }

        let codecParams = videoStream.codecParameters
        let width = Int(codecParams.width)
        let height = Int(codecParams.height)

        // Extract frame rate (reusing our existing logic)
        let realFR = videoStream.realFramerate
        var frameRate: AVRational
        if realFR.den > 0 {
            frameRate = realFR
            print(
                "  📊 Using realFramerate: \(Float(realFR.num) / Float(realFR.den))fps (\(realFR.num)/\(realFR.den))"
            )
        } else {
            let avgFR = videoStream.averageFramerate
            if avgFR.den > 0 {
                frameRate = avgFR
                print(
                    "  📊 Using averageFramerate (fallback): \(Float(avgFR.num) / Float(avgFR.den))fps (\(avgFR.num)/\(avgFR.den))"
                )
            } else {
                throw TimecodeBlackFramesError(message: "Cannot determine frame rate from file")
            }
        }

        let duration = inputFormatContext.duration
        let durationInSeconds = Double(duration) / 1_000_000.0

        // Extract timecode
        var timecode = "00:00:00:00"
        var isDropFrame = false

        if let formatTC = inputFormatContext.metadata["timecode"] {
            timecode = formatTC
            print("  📝 Found timecode in format metadata: \(timecode)")
        } else if let streamTC = videoStream.metadata["timecode"] {
            timecode = streamTC
            print("  📝 Found timecode in stream metadata: \(timecode)")
        } else {
            print("  ⚠️ No timecode found, using default: \(timecode)")
        }

        // Detect drop frame from timecode format and frame rate
        isDropFrame = detectDropFrameFromTimecode(timecode: timecode, frameRate: frameRate)
        let dropFrameInfo = isDropFrame ? " (drop frame)" : " (non-drop frame)"
        print("  🎬 Timecode analysis: \(timecode)\(dropFrameInfo)")

        // Calculate final dimensions (simplified for now)
        let finalWidth = width
        let finalHeight = height

        return BlankRushVideoProperties(
            width: width,
            height: height,
            frameRate: frameRate,
            duration: durationInSeconds,
            sampleAspectRatio: nil,  // Simplified for now
            company: inputFormatContext.metadata["company_name"],
            finalWidth: finalWidth,
            finalHeight: finalHeight,
            timecode: timecode,
            isDropFrame: isDropFrame
        )
    }

    /// Generate black video with timecode burn-in using VideoToolbox ProRes encoder
    private func generateBlackFramesToProRes(
        outputPath: String, properties: BlankRushVideoProperties
    ) throws {

        print(
            "  🖤 Generating black video with VideoToolbox ProRes: \(properties.finalWidth)x\(properties.finalHeight)"
        )

        // Create output format context
        let outputFormatContext = try AVFormatContext(format: nil, filename: outputPath)

        // Set timecode metadata early (before adding streams) - from straightTranscodeToProRes
        let timecodeForOutput: String
        if properties.isDropFrame {
            if properties.timecode.contains(";") {
                timecodeForOutput = properties.timecode
                print(
                    "  🎬 Early timecode setup - preserving drop frame format: \(timecodeForOutput)")
            } else {
                if let lastColonRange = properties.timecode.range(of: ":", options: .backwards) {
                    timecodeForOutput = properties.timecode.replacingCharacters(
                        in: lastColonRange, with: ";")
                } else {
                    timecodeForOutput = properties.timecode
                }
            }
        } else {
            timecodeForOutput = properties.timecode
        }
        outputFormatContext.metadata["timecode"] = timecodeForOutput
        print("  🎬 Set early timecode metadata: \(timecodeForOutput)")

        // Find VideoToolbox ProRes encoder (like straightTranscodeToProRes)
        guard let proresCodec = AVCodec.findEncoderByName("prores_videotoolbox") else {
            throw TimecodeBlackFramesError(message: "ProRes VideoToolbox encoder not found")
        }
        print("  🍎 Using VideoToolbox ProRes encoder (hardware acceleration)")

        // Add video stream
        guard let videoStream = outputFormatContext.addStream() else {
            throw TimecodeBlackFramesError(message: "Failed to add video stream")
        }

        // Create and configure codec context with VideoToolbox settings
        let codecContext = AVCodecContext(codec: proresCodec)
        codecContext.width = properties.finalWidth
        codecContext.height = properties.finalHeight
        codecContext.pixelFormat = AVPixelFormat.UYVY422  // VideoToolbox compatible

        // Use exact timebase and framerate from source file (from straightTranscodeToProRes)
        codecContext.timebase = AVRational(
            num: properties.frameRate.den, den: properties.frameRate.num)
        codecContext.framerate = properties.frameRate

        print(
            "  🔧 Source frame rate: \(properties.frameRate) = \(Float(properties.frameRate.num) / Float(properties.frameRate.den))fps"
        )
        print("  🔧 Using timebase: \(codecContext.timebase) for exact source timing match")

        // Open VideoToolbox encoder with ProRes 422 Proxy profile and color metadata
        try codecContext.openCodec(options: [
            "profile": "0",  // ProRes 422 Proxy (more compatible)
            "allow_sw": "0",  // Force hardware encoding
            "color_range": "tv",  // Broadcast legal range (16-235) for DaVinci Resolve compatibility
            "colorspace": "bt709",  // Standard HD color space
            "color_primaries": "bt709",  // Standard HD primaries
            "color_trc": "bt709",  // Standard HD gamma curve
        ])
        print("  🍎 VideoToolbox encoder opened with ProRes 422 Proxy profile")

        // Copy codec parameters to stream
        videoStream.codecParameters.copy(from: codecContext)
        videoStream.timebase = codecContext.timebase

        // CRITICAL: Force the output stream framerate to match source exactly (from straightTranscodeToProRes)
        videoStream.averageFramerate = properties.frameRate
        print(
            "  🔧 Forced output stream framerate to: \(properties.frameRate) = \(Float(properties.frameRate.num)/Float(properties.frameRate.den))fps"
        )

        // Create filter graph for black video generation
        let (filterGraph, buffersinkCtx) = try createBlackVideoFilterGraph(properties: properties)

        // Open output file and write header
        if !outputFormatContext.outputFormat!.flags.contains(.noFile) {
            try outputFormatContext.openOutput(url: outputPath, flags: .write)
        }

        // Timecode metadata was already set earlier
        let dropFrameInfo = properties.isDropFrame ? " (drop frame)" : " (non-drop frame)"
        print(
            "  🎬 Timecode metadata ready: \(outputFormatContext.metadata["timecode"] ?? "none")\(dropFrameInfo)"
        )

        try outputFormatContext.writeHeader()

        // Generate frames through filter pipeline with proper counting
        // Calculate total frames - when using MediaFileInfo, duration is calculated from exact frame count
        let exactFrameCount =
            properties.duration * Double(properties.frameRate.num)
            / Double(properties.frameRate.den)
        let totalFrames = Int(round(exactFrameCount))  // Round to nearest integer for exact frame count
        print(
            "  📝 Generating \(totalFrames) frames through filter graph (exact: \(String(format: "%.3f", exactFrameCount)))"
        )

        var frameCount = 0
        var encodedPacketCount = 0

        for frameIndex in 0..<totalFrames {
            let filterFrame = AVFrame()

            do {
                // Pull frame from filter graph
                try buffersinkCtx.getFrame(filterFrame)
                frameCount += 1

                // Set proper PTS for filter frame (like straightTranscodeToProRes)
                filterFrame.pts = Int64(frameIndex)

                if frameCount <= 5 || frameCount % 50 == 0 || frameCount > totalFrames - 5 {
                    print("  📦 Generated filter frame \(frameCount): PTS=\(filterFrame.pts)")
                }

                // Send to encoder
                try codecContext.sendFrame(filterFrame)

                // Receive encoded packets with proper timing rescaling (from straightTranscodeToProRes)
                while true {
                    let packet = AVPacket()
                    do {
                        try codecContext.receivePacket(packet)
                        encodedPacketCount += 1
                        packet.streamIndex = videoStream.index

                        // Store original timing for debugging
                        let originalPTS = packet.pts
                        let originalDTS = packet.dts

                        // CRITICAL: Rescale packet timing to output stream timebase
                        packet.pts = AVMath.rescale(
                            packet.pts, codecContext.timebase, videoStream.timebase,
                            rounding: .nearInf, passMinMax: true)
                        packet.dts = AVMath.rescale(
                            packet.dts, codecContext.timebase, videoStream.timebase,
                            rounding: .nearInf, passMinMax: true)
                        packet.duration = AVMath.rescale(
                            packet.duration, codecContext.timebase, videoStream.timebase)

                        if encodedPacketCount <= 5 || encodedPacketCount % 50 == 0
                            || frameCount > totalFrames - 5
                        {
                            print(
                                "  📦 Encoded packet \(encodedPacketCount): orig PTS=\(originalPTS) → \(packet.pts), DTS=\(originalDTS) → \(packet.dts)"
                            )
                        }

                        try outputFormatContext.interleavedWriteFrame(packet)
                    } catch let err as AVError where err == .tryAgain || err == .eof {
                        break
                    }
                }

                filterFrame.unref()

            } catch let error as AVError where error == .eof {
                print("  📝 Filter graph EOF at frame \(frameIndex)")
                break
            } catch {
                print("  ⚠️ Filter graph error at frame \(frameIndex): \(error)")
                break
            }
        }

        // Flush encoder with proper timing (from straightTranscodeToProRes)
        print("  🔄 Force flushing encoder to ensure all frames are written")
        try codecContext.sendFrame(nil as AVFrame?)
        while true {
            let packet = AVPacket()
            do {
                try codecContext.receivePacket(packet)
                encodedPacketCount += 1
                packet.streamIndex = videoStream.index

                // Store original timing for debugging
                let originalPTS = packet.pts
                let originalDTS = packet.dts

                // Rescale flush packets too
                packet.pts = AVMath.rescale(
                    packet.pts, codecContext.timebase, videoStream.timebase,
                    rounding: .nearInf, passMinMax: true)
                packet.dts = AVMath.rescale(
                    packet.dts, codecContext.timebase, videoStream.timebase,
                    rounding: .nearInf, passMinMax: true)
                packet.duration = AVMath.rescale(
                    packet.duration, codecContext.timebase, videoStream.timebase)

                print(
                    "  📦 Final flush packet \(encodedPacketCount): orig PTS=\(originalPTS) → \(packet.pts), DTS=\(originalDTS) → \(packet.dts)"
                )

                try outputFormatContext.interleavedWriteFrame(packet)
                print("  ✅ Successfully wrote final flush packet \(encodedPacketCount)")
            } catch let error as AVError where error.code == -541_478_725 {
                print(
                    "  🏁 Encoder/container EOF reached (frame \(frameCount), packet \(encodedPacketCount))"
                )
                print("  ℹ️  This is likely expected - encoder finished after processing all frames")
                break
            } catch {
                print("  ⚠️ Unexpected error writing final flush packet: \(error)")
                break
            }
        }

        print(
            "  📈 Final stats: \(frameCount) frames generated, \(encodedPacketCount) packets encoded"
        )

        // Write trailer
        try outputFormatContext.writeTrailer()

        print("  ✅ Generated black frames through VideoToolbox ProRes pipeline")
    }

    /// Create filter graph for black video generation (equivalent to ffmpeg color filter)
    private func createBlackVideoFilterGraph(properties: BlankRushVideoProperties) throws -> (
        AVFilterGraph, AVFilterContext
    ) {

        print("  🔧 Creating filter graph for black video generation")

        let filterGraph = AVFilterGraph()

        // Create color filter source (equivalent to -f lavfi -i "color=black:...")
        guard let colorFilter = AVFilter(name: "color") else {
            throw TimecodeBlackFramesError(message: "Color filter not found")
        }

        let colorArgs =
            "color=black:size=\(properties.finalWidth)x\(properties.finalHeight):duration=\(properties.duration):rate=\(properties.frameRate.num)/\(properties.frameRate.den)"
        print("  🔧 Color filter args: \(colorArgs)")

        let colorCtx = try filterGraph.addFilter(colorFilter, name: "color_src", args: colorArgs)

        // Create buffer sink
        guard let buffersink = AVFilter(name: "buffersink") else {
            throw TimecodeBlackFramesError(message: "Buffersink filter not found")
        }

        // Add DrawText filter for timecode burn-in
        guard let drawtextFilter = AVFilter(name: "drawtext") else {
            throw TimecodeBlackFramesError(message: "DrawText filter not found")
        }

        // Create running timecode with metadata display (inspired by ffmpegScripts/timecode_black_frames_relative.sh)
        let frameRateFloat = Float(properties.frameRate.num) / Float(properties.frameRate.den)

        // Convert timecode to proper format for FFmpeg drawtext - simpler escaping for SwiftFFmpeg
        let timecodeString: String
        let timecodeRate: String

        if properties.isDropFrame {
            // For drop-frame, preserve semicolon separator
            timecodeString =
                properties.timecode.contains(";")
                ? properties.timecode
                : properties.timecode.replacingOccurrences(
                    of: ":", with: ";", options: .backwards,
                    range: properties.timecode.range(of: ":", options: .backwards))
            timecodeRate = "\(properties.frameRate.num)/\(properties.frameRate.den)"
        } else {
            // For non-drop-frame, use colon separator as-is
            timecodeString = properties.timecode
            timecodeRate = "\(properties.frameRate.num)/\(properties.frameRate.den)"
        }

        let drawtextArgs =
            "timecode='\(timecodeString)':timecode_rate=\(timecodeRate):fontcolor=white:fontsize=64:x=50:y=150"
        print("  🔧 DrawText args: \(drawtextArgs)")

        let drawtextCtx = try filterGraph.addFilter(
            drawtextFilter, name: "drawtext", args: drawtextArgs)

        // Add format filter to convert to VideoToolbox-compatible pixel format
        guard let formatFilter = AVFilter(name: "format") else {
            throw TimecodeBlackFramesError(message: "Format filter not found")
        }

        let formatArgs = "pix_fmts=uyvy422"  // Force UYVY422 for VideoToolbox
        let formatCtx = try filterGraph.addFilter(formatFilter, name: "format", args: formatArgs)

        let buffersinkCtx = try filterGraph.addFilter(buffersink, name: "out", args: nil)

        // Set pixel formats for sink to match VideoToolbox encoder
        let pixFmts = [AVPixelFormat.UYVY422]  // Match VideoToolbox encoder format
        try buffersinkCtx.set(pixFmts.map({ $0.rawValue }), forKey: "pix_fmts")

        // Link filters: color -> drawtext -> format -> buffersink
        try colorCtx.link(dst: drawtextCtx)
        try drawtextCtx.link(dst: formatCtx)
        try formatCtx.link(dst: buffersinkCtx)

        // Configure filter graph
        try filterGraph.configure()

        print("  ✅ Filter graph created and configured")
        return (filterGraph, buffersinkCtx)
    }

    /// Detect drop frame from timecode format and frame rate (similar to importProcess.swift)
    private func detectDropFrameFromTimecode(timecode: String, frameRate: AVRational) -> Bool {
        let hasDropFrameSeparator = timecode.contains(";")
        let frameRateFloat = Float(frameRate.num) / Float(frameRate.den)

        // Common drop frame rates
        let commonDropFrameRates: [Float] = [29.97, 59.94]
        let isDropFrameRate = commonDropFrameRates.contains { abs(frameRateFloat - $0) < 0.01 }

        if hasDropFrameSeparator {
            if isDropFrameRate {
                print("  🎬 Drop frame detected: ';' separator with \(frameRateFloat)fps")
                return true
            } else {
                print(
                    "  ⚠️ Drop frame separator ';' found but frame rate \(frameRateFloat)fps is unusual for drop frame"
                )
                return true  // Trust the separator
            }
        } else {
            if isDropFrameRate {
                print(
                    "  ⚠️ Drop frame rate \(frameRateFloat)fps detected but using non-drop frame separator ':'"
                )
                return false  // Trust the separator format
            } else {
                print("  🎬 Non-drop frame detected: ':' separator with \(frameRateFloat)fps")
                return false
            }
        }
    }

    /// Create directory if it doesn't exist
    private func createDirectoryIfNeeded(at url: URL) {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                print("📁 Created output directory: \(url.path)")
            } catch {
                print("❌ Failed to create directory: \(error)")
            }
        }
    }
}

// MARK: - Convenience Extensions

extension LinkingResult {

    /// Get only OCF parents that have children (useful for blank rush creation)
    var parentsWithChildren: [OCFParent] {
        return ocfParents.filter { $0.hasChildren }
    }

    /// Summary of blank rush creation candidates
    var blankRushSummary: String {
        let candidateCount = parentsWithChildren.count
        let totalChildren = parentsWithChildren.reduce(0) { $0 + $1.childCount }
        return
            "\(candidateCount) OCF parents with \(totalChildren) total children ready for blank rush creation"
    }
}
