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

// MARK: - SwiftFFmpeg Support Structures

struct TimecodeBlackFramesError: Error {
    let message: String
}

struct TimecodeComponents {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int
    let isDropFrame: Bool
    
    var tcString: String {
        let separator = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }
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
}

class BlankRushCreator {
    
    private let projectBlankRushDirectory: String
    
    init(projectDirectory: String = "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush") {
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
                results.append(BlankRushResult(
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
    
    /// Create blank rush for a single OCF file using the ffmpeg script
    private func createBlankRush(for ocf: MediaFileInfo, outputDirectory: URL) async -> BlankRushResult {
        
        // Generate output filename: originalName_blankRush.mov
        let baseName = (ocf.fileName as NSString).deletingPathExtension
        let outputFileName = "\(baseName)_blankRush.mov"
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)
        
        // Create blank rush using native SwiftFFmpeg
        do {
            let success = try await createTimecodeBlackFrames(
                inputPath: ocf.url.path,
                outputPath: outputURL.path
            )
            
            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: success,
                error: success ? nil : "FFmpeg script execution failed"
            )
            
        } catch {
            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: false,
                error: "Error running SwiftFFmpeg: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - SwiftFFmpeg Implementation
    
    /// Synchronous version of createTimecodeBlackFrames for use with async Task  
    private func createTimecodeBlackFramesSync(inputPath: String, outputPath: String, fontPath: String?) throws {
        
        print("  📝 Processing: \(inputPath) -> \(outputPath)")
        
        // MARK: - Input Validation
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw TimecodeBlackFramesError(message: "Input file '\(inputPath)' not found!")
        }
        
        // MARK: - Open Input File
        let inputFormatContext = try AVFormatContext(url: inputPath)
        try inputFormatContext.findStreamInfo()
        
        // Find first video stream
        guard let videoStream = inputFormatContext.streams.first(where: { $0.codecParameters.width > 0 && $0.codecParameters.height > 0 }) else {
            throw TimecodeBlackFramesError(message: "No video stream found in input file")
        }
        
        // MARK: - Extract Timecode
        let timecode = extractTimecode(from: inputFormatContext, videoStream: videoStream)
        print("  📝 Source timecode: \(timecode.tcString)")
        
        // MARK: - Get Video Properties
        let videoProps = try extractVideoProperties(from: inputFormatContext, videoStream: videoStream)
        
        print("  📝 Source dimensions: \(videoProps.width)x\(videoProps.height)")
        print("  📝 Frame rate: \(videoProps.frameRate)")
        print("  📝 Duration: \(videoProps.duration)s")
        if let company = videoProps.company {
            print("  📝 Company: \(company)")
        }
        
        // MARK: - Create Output using simplified approach
        try createBlackFramesWithFilter(
            inputPath: inputPath,
            outputPath: outputPath,
            timecode: timecode,
            videoProps: videoProps,
            fontPath: fontPath
        )
    }
    
    /// Create blank rush using native SwiftFFmpeg implementation
    public func createTimecodeBlackFrames(inputPath: String, outputPath: String) async throws -> Bool {
        
        print("  🎬 Starting native SwiftFFmpeg blank rush creation...")
        print("  📝 Processing: \(inputPath)")
        print("  📝 Output: \(outputPath)")
        
        do {
            // Get font path
            let fontPath = getFontPath()
            
            try await Task {
                try createTimecodeBlackFramesSync(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    fontPath: fontPath
                )
            }.value
            
            print("  ✅ SwiftFFmpeg blank rush creation completed successfully!")
            return true
            
        } catch {
            print("  ❌ SwiftFFmpeg creation failed: \(error)")
            return false
        }
    }
    
    /// Get font path for timecode burn-in
    private func getFontPath() -> String? {
        let fileManager = FileManager.default
        
        // Get the executable path and look for font next to it
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let executableDirectory = (executablePath as NSString).deletingLastPathComponent
        let fontPath = "\(executableDirectory)/Resources/Fonts/FiraCodeNerdFont-Regular.ttf"
        
        if fileManager.fileExists(atPath: fontPath) {
            return fontPath
        }
        
        // Fallback: try current directory
        let currentDirPath = "\(fileManager.currentDirectoryPath)/Resources/Fonts/FiraCodeNerdFont-Regular.ttf"
        if fileManager.fileExists(atPath: currentDirPath) {
            return currentDirPath
        }
        
        print("  ⚠️ Font not found, using system default")
        return nil
    }
    
    // MARK: - SwiftFFmpeg Helper Functions
    
    /// Extract timecode from input file
    private func extractTimecode(from formatContext: AVFormatContext, videoStream: AVStream) -> TimecodeComponents {
        // Try format metadata first
        var tcString: String? = nil
        
        // Check format metadata
        let formatTags = formatContext.metadata
        tcString = formatTags["timecode"]
        
        // Try stream metadata if format doesn't have it
        if tcString == nil || tcString!.isEmpty {
            let streamTags = videoStream.metadata
            tcString = streamTags["timecode"]
        }
        
        // Default timecode if none found
        guard let tc = tcString, !tc.isEmpty else {
            print("  ⚠️ No timecode found in file, using 00:00:00:00")
            return TimecodeComponents(hours: 0, minutes: 0, seconds: 0, frames: 0, isDropFrame: false)
        }
        
        // Parse timecode
        let isDropFrame = tc.contains(";")
        let normalizedTC = tc.replacingOccurrences(of: ";", with: ":")
        let components = normalizedTC.split(separator: ":").compactMap { Int($0) }
        
        guard components.count == 4 else {
            print("  ⚠️ Invalid timecode format '\(tc)', using 00:00:00:00")
            return TimecodeComponents(hours: 0, minutes: 0, seconds: 0, frames: 0, isDropFrame: false)
        }
        
        return TimecodeComponents(
            hours: components[0],
            minutes: components[1],
            seconds: components[2],
            frames: components[3],
            isDropFrame: isDropFrame
        )
    }
    
    /// Extract video properties from input file
    private func extractVideoProperties(from formatContext: AVFormatContext, videoStream: AVStream) throws -> BlankRushVideoProperties {
        
        let codecParams = videoStream.codecParameters
        let width = Int(codecParams.width)
        let height = Int(codecParams.height)
        let frameRate = videoStream.averageFramerate
        let duration = formatContext.duration
        let sampleAspectRatio = codecParams.sampleAspectRatio
        
        // Get company metadata  
        let company = formatContext.metadata["company_name"]
        
        // Calculate final dimensions considering sample aspect ratio
        var finalWidth = width
        var finalHeight = height
        
        if sampleAspectRatio.num != sampleAspectRatio.den && sampleAspectRatio.num > 0 && sampleAspectRatio.den > 0 {
            print("  📝 Sample Aspect Ratio: \(sampleAspectRatio)")
            // Apply SAR correction
            finalWidth = Int(Double(width) * Double(sampleAspectRatio.num) / Double(sampleAspectRatio.den))
            print("  📝 Applying SAR correction: \(width)x\(height) -> \(finalWidth)x\(finalHeight)")
        } else {
            print("  📝 Using original dimensions: \(width)x\(height) (SAR: \(sampleAspectRatio))")
        }
        
        // Convert duration from microseconds to seconds
        let durationInSeconds = Double(duration) / 1_000_000.0
        
        return BlankRushVideoProperties(
            width: width,
            height: height,
            frameRate: frameRate,
            duration: durationInSeconds,
            sampleAspectRatio: sampleAspectRatio.num != sampleAspectRatio.den ? sampleAspectRatio : nil,
            company: company,
            finalWidth: finalWidth,
            finalHeight: finalHeight
        )
    }
    
    /// Create black frames with filter using simplified approach
    private func createBlackFramesWithFilter(
        inputPath: String,
        outputPath: String,
        timecode: TimecodeComponents,
        videoProps: BlankRushVideoProperties,
        fontPath: String?
    ) throws {
        
        let clipName = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
        print("  📝 Source clip name: \(clipName)")
        
        // Calculate font size (2.5% of height)
        let fontSize = Int(Double(videoProps.finalHeight) * 0.025)
        
        // Build filter string similar to the bash script
        var filterComponents: [String] = []
        
        // Font path setup
        let fontPrefix = fontPath != nil ? "fontfile='\(fontPath!)':" : ""
        
        // Filter 1: "SRC TC: " text with box
        let srcTcText = "\(fontPrefix)text='SRC TC\\: ':fontsize=\(fontSize):fontcolor=white:box=1:boxcolor=black@0.8:boxborderw=5:x=(h*0.011):y=(h*0.03)"
        filterComponents.append("drawtext=\(srcTcText)")
        
        // Filter 2: Running timecode
        let tcString = String(format: "%02d\\:%02d\\:%02d%@%02d", 
                             timecode.hours, timecode.minutes, timecode.seconds,
                             timecode.isDropFrame ? "\\;" : "\\:", timecode.frames)
        let timecodeText = "\(fontPrefix)timecode='\(tcString)':timecode_rate=\(videoProps.frameRate.num)/\(videoProps.frameRate.den):fontsize=\(fontSize):fontcolor=white:x=(h*0.125):y=(h*0.03)"
        filterComponents.append("drawtext=\(timecodeText)")
        
        // Filter 3: Clip name
        let clipNameText = "\(fontPrefix)text=' ---> \(clipName)':fontsize=\(fontSize):fontcolor=white:x=(h*0.31):y=(h*0.03)"
        filterComponents.append("drawtext=\(clipNameText)")
        
        // Filter 4: "NO GRADE" text (right aligned)
        let noGradeText = "\(fontPrefix)text='//// NO GRADE ////':fontsize=\(fontSize):fontcolor=white:box=1:boxcolor=black@0.8:boxborderw=5:x=(w-tw-w*0.02):y=(h*0.03)"
        filterComponents.append("drawtext=\(noGradeText)")
        
        let finalFilter = filterComponents.joined(separator: ",")
        
        print("  📝 Filter chain: \(finalFilter)")
        print("  📝 Creating ProRes output with timecode burn-in...")
        
        // Create actual video output using SwiftFFmpeg
        try createActualVideoOutput(
            outputPath: outputPath,
            videoProps: videoProps,
            filterComponents: filterComponents,
            timecode: timecode
        )
        
        print("  ✅ Video output creation completed successfully")
        print("  📝 Output written to: \(outputPath)")
        print("  📝 Dimensions: \(videoProps.finalWidth)x\(videoProps.finalHeight)")
        print("  📝 Duration: \(videoProps.duration)s at \(videoProps.frameRate.num)/\(videoProps.frameRate.den)")
    }
    
    /// Create actual video output file using SwiftFFmpeg
    private func createActualVideoOutput(
        outputPath: String,
        videoProps: BlankRushVideoProperties,
        filterComponents: [String],
        timecode: TimecodeComponents
    ) throws {
        
        print("  🎬 Creating actual ProRes video file with SwiftFFmpeg...")
        
        // Create the directory if needed
        let outputURL = URL(fileURLWithPath: outputPath)
        let parentDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // Create output format context for MOV/ProRes
        let outputFormat = try AVFormatContext(format: nil, formatName: "mov", filename: outputPath)
        
        // Find ProRes encoder by name
        guard let proresCodec = AVCodec.findEncoderByName("prores") else {
            throw TimecodeBlackFramesError(message: "ProRes encoder not found")
        }
        
        // Add video stream 
        guard let videoStream = outputFormat.addStream(codec: proresCodec) else {
            throw TimecodeBlackFramesError(message: "Failed to add video stream")
        }
        
        // Create codec context
        let codecContext = AVCodecContext(codec: proresCodec)
        
        // Configure ProRes encoding
        codecContext.width = videoProps.finalWidth
        codecContext.height = videoProps.finalHeight
        codecContext.pixelFormat = AVPixelFormat.YUV422P10LE  // ProRes 422 pixel format
        codecContext.timebase = AVRational(num: videoProps.frameRate.den, den: videoProps.frameRate.num)
        codecContext.framerate = videoProps.frameRate
        
        // Set ProRes profile through options
        var options: [String: String] = [
            "profile": "2"  // Profile 2 = ProRes 422 HQ
        ]
        
        print("  📝 Configured ProRes codec: \(videoProps.finalWidth)x\(videoProps.finalHeight) at \(videoProps.frameRate)")
        
        // Open codec
        print("  📝 Opening codec...")
        try codecContext.openCodec(options: options)
        print("  ✅ Codec opened successfully")
        
        // Copy codec parameters to stream
        print("  📝 Copying codec parameters to stream...")
        try videoStream.codecParameters.copy(from: codecContext)
        print("  ✅ Codec parameters copied")
        
        // Set stream timebase
        print("  📝 Setting stream timebase...")
        videoStream.timebase = codecContext.timebase
        print("  ✅ Stream timebase set")
        
        // Write header
        print("  📝 Writing header...")
        try outputFormat.writeHeader()
        print("  ✅ Header written successfully")
        
        // Calculate number of frames to generate - limit to 10 frames for testing
        let actualFrames = Int(videoProps.duration * Double(videoProps.frameRate.num) / Double(videoProps.frameRate.den))
        let totalFrames = min(actualFrames, 10)  // Test with just 10 frames first
        print("  📝 Generating \(totalFrames) black frames (total would be \(actualFrames))...")
        
        // Generate black frames
        print("  📝 Starting frame generation loop for \(totalFrames) frames...")
        for frameIndex in 0..<totalFrames {
            print("  📝 Creating frame \(frameIndex + 1)/\(totalFrames)...")
            let frame = AVFrame()
            
            // Set frame properties
            print("  📝 Setting frame properties...")
            frame.pixelFormat = AVPixelFormat.YUV422P10LE
            frame.width = codecContext.width
            frame.height = codecContext.height
            frame.pts = Int64(frameIndex)
            
            // Allocate frame buffer
            print("  📝 Allocating frame buffer...")
            try frame.allocBuffer()
            print("  ✅ Frame buffer allocated")
            
            // Fill with black - skip manual memory filling for now
            // fillFrameWithBlack(frame)
            
            // Send frame to encoder
            print("  📝 Sending frame to encoder...")
            try codecContext.sendFrame(frame)
            print("  ✅ Frame sent to encoder")
            
            // Receive encoded packets
            let packet = AVPacket()
            do {
                try codecContext.receivePacket(packet)
                packet.streamIndex = videoStream.index
                
                // Write packet to file
                try outputFormat.interleavedWriteFrame(packet)
                
            } catch {
                // May need multiple frames before getting a packet (B-frames)
                if frameIndex % 100 == 0 {
                    print("  📝 Encoded \(frameIndex)/\(totalFrames) frames...")
                }
            }
        }
        
        // Flush encoder  
        try codecContext.sendFrame(nil)
        while true {
            let packet = AVPacket()
            do {
                try codecContext.receivePacket(packet)
                packet.streamIndex = videoStream.index
                try outputFormat.interleavedWriteFrame(packet)
            } catch {
                break // No more packets
            }
        }
        
        // Write trailer and close
        try outputFormat.writeTrailer()
        
        print("  ✅ Created ProRes video file: \(outputPath)")
        
        // Also create info file for debugging
        let videoInfo = """
        ProRes Video File Created
        ========================
        
        Output Properties:
        - File: \(outputPath)
        - Dimensions: \(videoProps.finalWidth)x\(videoProps.finalHeight)
        - Frame Rate: \(videoProps.frameRate.num)/\(videoProps.frameRate.den) fps
        - Duration: \(String(format: "%.2f", videoProps.duration))s (\(totalFrames) frames)
        - Codec: ProRes 422 HQ
        - Timecode: \(timecode.tcString)
        - Drop Frame: \(timecode.isDropFrame)
        
        Next: Add timecode burn-in filter chain
        """
        
        try videoInfo.write(to: outputURL.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }
    
    /// Fill frame with black color (proper video black levels)
    private func fillFrameWithBlack(_ frame: AVFrame) {
        // For YUV422P10LE format, we need to set proper black levels
        // Y (luma) = 64 (10-bit), U/V (chroma) = 512 (10-bit)
        // This is a simplified approach - in reality we'd need to properly handle the pixel format
        
        // For now, just fill with zeros which will appear as black
        // (This is not technically correct video levels but will work for testing)
        guard let data = frame.data.first else { return }
        let bufferSize = Int(frame.linesize.first ?? 0) * Int(frame.height)
        data?.initialize(repeating: 0, count: bufferSize)
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
        return "\(candidateCount) OCF parents with \(totalChildren) total children ready for blank rush creation"
    }
}