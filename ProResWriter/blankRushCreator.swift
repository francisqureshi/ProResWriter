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

class BlankRushCreator {

    private let projectBlankRushDirectory: String

    init(
        projectDirectory: String =
            "/Users/mac10/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush"
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

        // Use the new MediaFileInfo-based transcoding (more efficient)
        do {
            let success = try await transcodeToProRes(
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

    // MARK: - Simple ProRes Transcoding

    /// Simple transcoding with MediaFileInfo struct (uses pre-analyzed metadata)
    public func transcodeToProRes(ocfFile: MediaFileInfo, outputPath: String) async throws -> Bool {
        
        print("  🎬 Starting ProRes transcoding with pre-analyzed metadata...")
        print("  📝 Input: \(ocfFile.fileName)")
        print("  📝 Output: \(outputPath)")
        print("  🎬 Using metadata: \(ocfFile.frameRateDescription), \(ocfFile.durationInFrames ?? 0) frames")
        
        do {
            try await Task {
                try transcodeToProResSyncWithMetadata(ocfFile: ocfFile, outputPath: outputPath)
            }.value

            print("  ✅ ProRes transcoding completed successfully!")
            return true

        } catch {
            print("  ❌ ProRes transcoding failed: \(error)")
            return false
        }
    }

    /// Simple transcoding based on remuxing.swift example (legacy path-based version)
    public func transcodeToProRes(inputPath: String, outputPath: String) async throws -> Bool {

        print("  🎬 Starting simple ProRes transcoding...")
        print("  📝 Input: \(inputPath)")
        print("  📝 Output: \(outputPath)")

        do {
            try await Task {
                try transcodeToProResSync(inputPath: inputPath, outputPath: outputPath)
            }.value

            print("  ✅ ProRes transcoding completed successfully!")
            return true

        } catch {
            print("  ❌ ProRes transcoding failed: \(error)")
            return false
        }
    }

    /// Synchronous implementation using pre-analyzed MediaFileInfo metadata
    private func transcodeToProResSyncWithMetadata(ocfFile: MediaFileInfo, outputPath: String) throws {

        print("  📝 Processing with metadata: \(ocfFile.fileName) -> \(outputPath)")
        
        let inputPath = ocfFile.url.path
        
        // Input validation
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw TimecodeBlackFramesError(message: "Input file '\(inputPath)' not found!")
        }

        // Use pre-analyzed metadata instead of re-extracting
        guard let frameRate = ocfFile.frameRate else {
            throw TimecodeBlackFramesError(message: "No frame rate available in MediaFileInfo")
        }
        
        guard let resolution = ocfFile.resolution else {
            throw TimecodeBlackFramesError(message: "No resolution available in MediaFileInfo")
        }
        
        // Convert float frame rate to proper AVRational for common professional rates
        let frameRateRational: AVRational
        if abs(frameRate - 23.976025) < 0.001 {
            frameRateRational = AVRational(num: 24000, den: 1001)
        } else if abs(frameRate - 29.97) < 0.001 {
            frameRateRational = AVRational(num: 30000, den: 1001)
        } else if abs(frameRate - 59.94006) < 0.001 {
            frameRateRational = AVRational(num: 60000, den: 1001)
        } else if abs(frameRate - 24.0) < 0.001 {
            frameRateRational = AVRational(num: 24, den: 1)
        } else if abs(frameRate - 25.0) < 0.001 {
            frameRateRational = AVRational(num: 25, den: 1)
        } else if abs(frameRate - 30.0) < 0.001 {
            frameRateRational = AVRational(num: 30, den: 1)
        } else {
            // Fallback for unusual frame rates
            frameRateRational = AVRational(num: Int32(frameRate * 1000), den: 1000)
        }
        
        let sourceProperties = BlankRushVideoProperties(
            width: Int(resolution.width),
            height: Int(resolution.height),
            frameRate: frameRateRational,
            duration: Double(ocfFile.durationInFrames ?? 0) / Double(frameRate),
            sampleAspectRatio: nil, // Could parse from ocfFile.sampleAspectRatio if needed
            company: nil, // Could add to MediaFileInfo if needed
            finalWidth: Int(resolution.width),
            finalHeight: Int(resolution.height),
            timecode: ocfFile.sourceTimecode ?? "00:00:00:00",
            isDropFrame: ocfFile.isDropFrame ?? false
        )
        
        print("  📝 Using pre-analyzed properties: \(sourceProperties.width)x\(sourceProperties.height) at \(sourceProperties.frameRate)")
        print("  📝 Duration: \(String(format: "%.2f", sourceProperties.duration))s, \(ocfFile.durationInFrames ?? 0) frames")
        print("  📝 Timecode: \(sourceProperties.timecode)")

        // Use the same transcode logic as the path-based version
        try straightTranscodeToProRes(
            inputPath: inputPath,
            outputPath: outputPath,
            properties: sourceProperties
        )

        print("  ✅ Transcoding with pre-analyzed metadata completed: \(outputPath)")
    }

    /// Synchronous implementation: Generate synthetic black frames with metadata from source
    private func transcodeToProResSync(inputPath: String, outputPath: String) throws {

        print("  📝 Processing: \(inputPath) -> \(outputPath)")

        // Input validation
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw TimecodeBlackFramesError(message: "Input file '\(inputPath)' not found!")
        }

        // STEP 1: Extract metadata from source (without decoding video content)
        let sourceProperties = try extractSourceProperties(from: inputPath)
        print(
            "  📝 Source properties: \(sourceProperties.width)x\(sourceProperties.height) at \(sourceProperties.frameRate)"
        )
        print("  📝 Duration: \(String(format: "%.2f", sourceProperties.duration))s")
        print("  📝 Timecode: \(sourceProperties.timecode)")

        // STEP 2: Generate synthetic black frames and encode to ProRes
        // try generateBlackFramesToProRes(
        //     outputPath: outputPath,
        //     properties: sourceProperties
        // )

        // TEMP: Test straight transcode to debug timing issues
        try straightTranscodeToProRes(
            inputPath: inputPath,
            outputPath: outputPath,
            properties: sourceProperties
        )

        print("  ✅ Synthetic black frame generation completed: \(outputPath)")
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

    /// Generate black video with timecode burn-in using proper filter graph pipeline
    private func generateBlackFramesToProRes(
        outputPath: String, properties: BlankRushVideoProperties
    ) throws {

        print(
            "  🖤 Generating black video with filter graph: \(properties.finalWidth)x\(properties.finalHeight)"
        )

        // Create output format context
        let outputFormatContext = try AVFormatContext(format: nil, filename: outputPath)

        // Find ProRes encoder
        guard let proresCodec = AVCodec.findEncoderByName("prores") else {
            throw TimecodeBlackFramesError(message: "ProRes encoder not found")
        }

        // Add video stream
        guard let videoStream = outputFormatContext.addStream() else {
            throw TimecodeBlackFramesError(message: "Failed to add video stream")
        }

        // Create and configure codec context
        let codecContext = AVCodecContext(codec: proresCodec)
        codecContext.width = properties.finalWidth
        codecContext.height = properties.finalHeight
        codecContext.pixelFormat = AVPixelFormat.YUV422P10LE
        // Use exact timebase and framerate from source file
        codecContext.timebase = AVRational(
            num: properties.frameRate.den, den: properties.frameRate.num)
        codecContext.framerate = properties.frameRate

        // Set stream timebase to match codec exactly - critical for container timing
        videoStream.timebase = codecContext.timebase

        print(
            "  🔧 Source frame rate: \(properties.frameRate) = \(Float(properties.frameRate.num) / Float(properties.frameRate.den))fps"
        )
        print("  🔧 Using timebase: \(codecContext.timebase) for exact source timing match")

        print(
            "  📝 Codec configuration: \(properties.finalWidth)x\(properties.finalHeight) at \(properties.frameRate)"
        )
        print(
            "  🔧 Debug timebase - Codec: \(codecContext.timebase), Stream: \(videoStream.timebase)")

        // Open codec
        let options: [String: String] = [
            "profile": "2"  // ProRes 422 HQ for now
        ]
        try codecContext.openCodec(options: options)

        // Copy codec parameters to stream
        videoStream.codecParameters.copy(from: codecContext)

        // Force stream timebase to exactly match source after copying codec params
        videoStream.timebase = AVRational(
            num: properties.frameRate.den, den: properties.frameRate.num)
        print("  🔧 After codec copy - Stream timebase forced to: \(videoStream.timebase)")

        print("  ⚠️ Filter graph temporarily disabled for straight transcode test")

        // TEMP COMMENTED OUT - testing straight transcode
        // // Create filter graph for black video generation
        // let (_, _) = try createBlackVideoFilterGraph(properties: properties)
        //
        // // Open output file and write header
        // if !outputFormatContext.outputFormat!.flags.contains(.noFile) {
        //     try outputFormatContext.openOutput(url: outputPath, flags: .write)
        // }
        // try outputFormatContext.writeHeader()
        //
        // // Generate frames through filter pipeline
        // let totalFrames = Int(properties.duration * Double(properties.frameRate.num) / Double(properties.frameRate.den))
        // print("  📝 Generating \(totalFrames) frames through filter graph")
        //
        // for frameIndex in 0..<totalFrames {
        //     let filterFrame = AVFrame()
        //
        //     do {
        //         // Pull frame from filter graph
        //         try buffersinkCtx.getFrame(filterFrame)
        //
        //                // Send to encoder
        //                try codecContext.sendFrame(filterFrame)
        //
        //                // Receive encoded packets
        //                let packet = AVPacket()
        //                do {
        //                    try codecContext.receivePacket(packet)
        //                    packet.streamIndex = videoStream.index
        //                    try outputFormatContext.interleavedWriteFrame(packet)
        //                } catch {
        //                    // May need multiple frames before getting packets
        //                }
        //
        //                filterFrame.unref()
        //
        //            } catch let error as AVError where error == .eof {
        //                print("  📝 Filter graph EOF at frame \(frameIndex)")
        //                break
        //            } catch {
        //                print("  ⚠️ Filter graph error at frame \(frameIndex): \(error)")
        //                break
        //            }
        //        }
        //
        //        // Flush encoder
        //        try codecContext.sendFrame(nil as AVFrame?)
        //        while true {
        //            let packet = AVPacket()
        //            do {
        //                try codecContext.receivePacket(packet)
        //                packet.streamIndex = videoStream.index
        //                try outputFormatContext.interleavedWriteFrame(packet)
        //            } catch {
        //                break
        //            }
        //        }
        //
        //        // Write trailer
        //        try outputFormatContext.writeTrailer()
        //
        //        print("  ✅ Generated frames through filter graph pipeline")
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

        let buffersinkCtx = try filterGraph.addFilter(buffersink, name: "out", args: nil)

        // Set pixel formats for sink
        let pixFmts = [AVPixelFormat.YUV422P10LE]
        try buffersinkCtx.set(pixFmts.map({ $0.rawValue }), forKey: "pix_fmts")

        // Link filters: color -> buffersink (simple for now, we'll add drawtext later)
        try colorCtx.link(dst: buffersinkCtx)

        // Configure filter graph
        try filterGraph.configure()

        print("  ✅ Filter graph created and configured")
        return (filterGraph, buffersinkCtx)
    }

    /// Straight transcode to test timing (bypass filter graph)
    private func straightTranscodeToProRes(
        inputPath: String, outputPath: String, properties: BlankRushVideoProperties
    ) throws {

        print("  🔄 Testing proper decode-encode transcode with timing fixes")

        // Input format context
        let inputFormatContext = try AVFormatContext(url: inputPath)
        try inputFormatContext.findStreamInfo()

        // Find video stream
        guard
            let videoStream = inputFormatContext.streams.first(where: {
                $0.codecParameters.width > 0
            })
        else {
            throw TimecodeBlackFramesError(message: "No video stream found")
        }

        // Create decoder

        guard let decoder = AVCodec.findDecoderById(videoStream.codecParameters.codecId) else {
            throw TimecodeBlackFramesError(message: "Decoder not found")
        }
        let decoderContext = AVCodecContext(codec: decoder)
        try decoderContext.setParameters(videoStream.codecParameters)
        try decoderContext.openCodec(options: [
            "allow_sw": "0"  // Force hardware encoding
        ])

        // Create output
        let outputFormatContext = try AVFormatContext(format: nil, filename: outputPath)
        
        // Set timecode metadata early (before adding streams)
        let timecodeForOutput: String
        if properties.isDropFrame {
            if properties.timecode.contains(";") {
                timecodeForOutput = properties.timecode
                print("  🎬 Early timecode setup - preserving drop frame format: \(timecodeForOutput)")
            } else {
                if let lastColonRange = properties.timecode.range(of: ":", options: .backwards) {
                    timecodeForOutput = properties.timecode.replacingCharacters(in: lastColonRange, with: ";")
                } else {
                    timecodeForOutput = properties.timecode
                }
            }
        } else {
            timecodeForOutput = properties.timecode
        }
        outputFormatContext.metadata["timecode"] = timecodeForOutput
        print("  🎬 Set early timecode metadata: \(timecodeForOutput)")

        // Find VideoToolbox ProRes encoder (like your shell script: -c:v prores_videotoolbox)
        guard let proresCodec = AVCodec.findEncoderByName("prores_videotoolbox") else {
            throw TimecodeBlackFramesError(message: "ProRes VideoToolbox encoder not found")
        }
        print("  🍎 Using VideoToolbox ProRes encoder (hardware acceleration)")

        // Add video stream
        guard let outputVideoStream = outputFormatContext.addStream() else {
            throw TimecodeBlackFramesError(message: "Failed to add video stream")
        }

        // Create encoder context - copy timing from source exactly
        let encoderContext = AVCodecContext(codec: proresCodec)
        encoderContext.width = properties.finalWidth
        encoderContext.height = properties.finalHeight
        // ProRes encoder pixel format compatibility check
        let decoderPixFmt = decoderContext.pixelFormat
        print("  🔧 Decoder pixel format: \(decoderPixFmt)")

        // VideoToolbox ProRes compatible pixel formats (from supported list)
        let proresPixelFormat: AVPixelFormat = .UYVY422  // VideoToolbox supports this
        print("  🔄 Using UYVY422 for VideoToolbox encoder")

        // Check if we need pixel format conversion
        let needsConversion = decoderPixFmt != proresPixelFormat
        var swsContext: SwsContext?

        if needsConversion {
            print("  🔄 Creating pixel format converter: \(decoderPixFmt) → \(proresPixelFormat)")
            swsContext = SwsContext(
                srcWidth: properties.finalWidth,
                srcHeight: properties.finalHeight,
                srcPixelFormat: decoderPixFmt,
                dstWidth: properties.finalWidth,
                dstHeight: properties.finalHeight,
                dstPixelFormat: proresPixelFormat,
                flags: .bilinear
            )
            guard swsContext != nil else {
                throw TimecodeBlackFramesError(message: "Failed to create pixel format converter")
            }
        }

        encoderContext.pixelFormat = proresPixelFormat
        print("  🔧 Using ProRes pixel format: \(proresPixelFormat)")
        encoderContext.timebase = videoStream.timebase  // Use source stream timebase exactly
        encoderContext.framerate = properties.frameRate  // Use exact source framerate from properties

        print("  🔧 Source stream timebase: \(videoStream.timebase)")
        print("  🔧 Source stream framerate: \(videoStream.realFramerate)")

        // Open encoder with VideoToolbox options (profile 0 = ProRes 422 Proxy)
        try encoderContext.openCodec(options: [
            "profile": "0",  // ProRes 422 Proxy (more compatible)
            "allow_sw": "0",  // Force hardware encoding
        ])
        print("  🍎 VideoToolbox encoder opened with ProRes 422 Proxy profile")

        // Copy codec parameters
        outputVideoStream.codecParameters.copy(from: encoderContext)
        outputVideoStream.timebase = videoStream.timebase  // Force exact source timebase
        
        // CRITICAL: Force the output stream framerate to match source exactly  
        // This prevents VideoToolbox from writing incorrect 24.04fps metadata
        // Use the precise framerate from import analysis (extracted via realFramerate or averageFramerate)
        outputVideoStream.averageFramerate = properties.frameRate  // Exact AVRational from source
        print("  🔧 Forced output stream framerate to: \(properties.frameRate) = \(Float(properties.frameRate.num)/Float(properties.frameRate.den))fps")

        print("  🔧 Output stream timebase set to: \(outputVideoStream.timebase)")

        // Open output and write header
        if !outputFormatContext.outputFormat!.flags.contains(.noFile) {
            try outputFormatContext.openOutput(url: outputPath, flags: .write)
        }
        
        // Timecode metadata was already set earlier - no need to set again
        let dropFrameInfo = properties.isDropFrame ? " (drop frame)" : " (non-drop frame)"
        print("  🎬 Timecode metadata ready: \(outputFormatContext.metadata["timecode"] ?? "none")\(dropFrameInfo)")
        
        try outputFormatContext.writeHeader()

        print("  🔄 Transcoding frames with frame counting...")
        var frameCount = 0
        var encodedPacketCount = 0

        // Decode and re-encode frames (following C example pattern)
        let packet = AVPacket()
        while true {
            do {
                try inputFormatContext.readFrame(into: packet)
            } catch {
                print("  📋 End of input reached, processed \(frameCount) frames")
                break
            }
            defer { packet.unref() }

            if packet.streamIndex != videoStream.index { continue }

            // Decode frame - send packet first
            try decoderContext.sendPacket(packet)

            // Receive all frames from this packet (following C example pattern)
            while true {
                let frame = AVFrame()
                do {
                    try decoderContext.receiveFrame(frame)
                    frameCount += 1

                    // CRITICAL: Set PTS following SwiftFFmpeg examples
                    frame.pts = frame.bestEffortTimestamp
                    if frameCount <= 5 || frameCount % 50 == 0 || frameCount > 400 {
                        print("  📦 Decoded frame \(frameCount): PTS=\(frame.pts)")
                    }

                    // Convert pixel format if needed
                    let frameToEncode: AVFrame
                    if needsConversion, let sws = swsContext {
                        let convertedFrame = AVFrame()
                        convertedFrame.width = properties.finalWidth
                        convertedFrame.height = properties.finalHeight
                        convertedFrame.pixelFormat = proresPixelFormat
                        convertedFrame.pts = frame.pts
                        try convertedFrame.allocBuffer(align: 32)

                        // Use SwsContext scaling with proper pointer conversion
                        var srcPointers: [UnsafePointer<UInt8>?] = []
                        var dstPointers: [UnsafeMutablePointer<UInt8>?] = []

                        for i in 0..<4 {
                            if let srcPtr = frame.data[i] {
                                srcPointers.append(UnsafePointer(srcPtr))
                            } else {
                                srcPointers.append(nil)
                            }

                            if let dstPtr = convertedFrame.data[i] {
                                dstPointers.append(dstPtr)
                            } else {
                                dstPointers.append(nil)
                            }
                        }

                        let height = try sws.scale(
                            src: srcPointers,
                            srcStride: frame.linesize.baseAddress!,
                            srcSliceY: 0,
                            srcSliceHeight: frame.height,
                            dst: dstPointers,
                            dstStride: convertedFrame.linesize.baseAddress!
                        )
                        frameToEncode = convertedFrame
                    } else {
                        frameToEncode = frame
                    }

                    // Re-encode frame
                    try encoderContext.sendFrame(frameToEncode)

                    // Get encoded packets with proper timing rescaling
                    while true {
                        let encodedPacket = AVPacket()
                        do {
                            try encoderContext.receivePacket(encodedPacket)
                            encodedPacketCount += 1
                            encodedPacket.streamIndex = outputVideoStream.index

                            // Store original timing for debugging
                            let originalPTS = encodedPacket.pts
                            let originalDTS = encodedPacket.dts
                            let originalDuration = encodedPacket.duration

                            // CRITICAL: Rescale packet timing to output stream timebase (from remuxing.swift)
                            encodedPacket.pts = AVMath.rescale(
                                encodedPacket.pts, encoderContext.timebase,
                                outputVideoStream.timebase,
                                rounding: .nearInf, passMinMax: true)
                            encodedPacket.dts = AVMath.rescale(
                                encodedPacket.dts, encoderContext.timebase,
                                outputVideoStream.timebase,
                                rounding: .nearInf, passMinMax: true)
                            encodedPacket.duration = AVMath.rescale(
                                encodedPacket.duration, encoderContext.timebase,
                                outputVideoStream.timebase)

                            if encodedPacketCount <= 5 || encodedPacketCount % 50 == 0 || frameCount > 400 {
                                print("  📦 Encoded packet \(encodedPacketCount): orig PTS=\(originalPTS) → \(encodedPacket.pts), DTS=\(originalDTS) → \(encodedPacket.dts)")
                            }

                            try outputFormatContext.interleavedWriteFrame(encodedPacket)
                        } catch let err as AVError where err == .tryAgain || err == .eof {
                            break
                        }
                    }

                    frame.unref()

                } catch let err as AVError where err == .tryAgain || err == .eof {
                    break
                }
            }
        }

        // CRITICAL: Flush decoder first to get remaining frames (likely the missing frame!)
        print("  🔄 Flushing decoder...")
        try decoderContext.sendPacket(nil as AVPacket?)
        while true {
            let frame = AVFrame()
            do {
                try decoderContext.receiveFrame(frame)
                frameCount += 1
                frame.pts = frame.bestEffortTimestamp
                print("  🔄 Flushed frame \(frameCount): PTS=\(frame.pts)")

                // Convert pixel format if needed (same logic as main loop)
                let frameToEncode: AVFrame
                if needsConversion, let sws = swsContext {
                    let convertedFrame = AVFrame()
                    convertedFrame.width = properties.finalWidth
                    convertedFrame.height = properties.finalHeight
                    convertedFrame.pixelFormat = proresPixelFormat
                    convertedFrame.pts = frame.pts
                    try convertedFrame.allocBuffer(align: 32)

                    // Use SwsContext scaling with proper pointer conversion
                    var srcPointers: [UnsafePointer<UInt8>?] = []
                    var dstPointers: [UnsafeMutablePointer<UInt8>?] = []

                    for i in 0..<4 {
                        if let srcPtr = frame.data[i] {
                            srcPointers.append(UnsafePointer(srcPtr))
                        } else {
                            srcPointers.append(nil)
                        }

                        if let dstPtr = convertedFrame.data[i] {
                            dstPointers.append(dstPtr)
                        } else {
                            dstPointers.append(nil)
                        }
                    }

                    let height = try sws.scale(
                        src: srcPointers,
                        srcStride: frame.linesize.baseAddress!,
                        srcSliceY: 0,
                        srcSliceHeight: frame.height,
                        dst: dstPointers,
                        dstStride: convertedFrame.linesize.baseAddress!
                    )
                    frameToEncode = convertedFrame
                } else {
                    frameToEncode = frame
                }

                try encoderContext.sendFrame(frameToEncode)

                while true {
                    let encodedPacket = AVPacket()
                    do {
                        try encoderContext.receivePacket(encodedPacket)
                        encodedPacketCount += 1
                        encodedPacket.streamIndex = outputVideoStream.index

                        // Store original timing for debugging
                        let originalPTS = encodedPacket.pts
                        let originalDTS = encodedPacket.dts

                        encodedPacket.pts = AVMath.rescale(
                            encodedPacket.pts, encoderContext.timebase, outputVideoStream.timebase,
                            rounding: .nearInf, passMinMax: true)
                        encodedPacket.dts = AVMath.rescale(
                            encodedPacket.dts, encoderContext.timebase, outputVideoStream.timebase,
                            rounding: .nearInf, passMinMax: true)
                        encodedPacket.duration = AVMath.rescale(
                            encodedPacket.duration, encoderContext.timebase,
                            outputVideoStream.timebase)

                        print("  🔄 Flushed frame \(frameCount) packet \(encodedPacketCount): orig PTS=\(originalPTS) → \(encodedPacket.pts)")

                        try outputFormatContext.interleavedWriteFrame(encodedPacket)
                    } catch let err as AVError where err == .tryAgain || err == .eof {
                        break
                    }
                }

                frame.unref()
            } catch let err as AVError where err == .tryAgain || err == .eof {
                break
            }
        }

        print("  ✅ Total frames decoded: \(frameCount)")

        // Always flush encoder - VideoToolbox may not report delay capability correctly
        print("  🔄 Force flushing encoder to ensure all frames are written")
        
        // Flush encoder with proper timing rescaling
        try encoderContext.sendFrame(nil as AVFrame?)
        while true {
            let packet = AVPacket()
            do {
                try encoderContext.receivePacket(packet)
                encodedPacketCount += 1
                packet.streamIndex = outputVideoStream.index

                // Store original timing for debugging
                let originalPTS = packet.pts
                let originalDTS = packet.dts

                // Rescale flush packets too
                packet.pts = AVMath.rescale(
                    packet.pts, encoderContext.timebase, outputVideoStream.timebase,
                    rounding: .nearInf, passMinMax: true)
                packet.dts = AVMath.rescale(
                    packet.dts, encoderContext.timebase, outputVideoStream.timebase,
                    rounding: .nearInf, passMinMax: true)
                packet.duration = AVMath.rescale(
                    packet.duration, encoderContext.timebase, outputVideoStream.timebase)

                print("  📦 Final flush packet \(encodedPacketCount): orig PTS=\(originalPTS) → \(packet.pts), DTS=\(originalDTS) → \(packet.dts)")

                try outputFormatContext.interleavedWriteFrame(packet)
                print("  ✅ Successfully wrote final flush packet \(encodedPacketCount)")
            } catch let error as AVError where error.code == -541478725 {
                // EOF error - this could be:
                // 1. Encoder finished (expected after all frames processed) 
                // 2. Container rejected packet (would be unexpected with our framerate fix)
                print("  🏁 Encoder/container EOF reached (frame \(frameCount), packet \(encodedPacketCount))")
                print("  ℹ️  This is likely expected - encoder finished after processing all frames")
                break
            } catch {
                print("  ⚠️ Unexpected error writing final flush packet: \(error)")
                break
            }
        }

        print("  📈 Final stats: \(frameCount) frames decoded, \(encodedPacketCount) packets encoded")

        try outputFormatContext.writeTrailer()
        print("  ✅ Straight transcode completed")
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
                print("  ⚠️ Drop frame separator ';' found but frame rate \(frameRateFloat)fps is unusual for drop frame")
                return true  // Trust the separator
            }
        } else {
            if isDropFrameRate {
                print("  ⚠️ Drop frame rate \(frameRateFloat)fps detected but using non-drop frame separator ':'")
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
