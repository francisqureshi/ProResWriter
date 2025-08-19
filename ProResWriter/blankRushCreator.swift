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
    
    /// Create blank rush for a single OCF file
    private func createBlankRush(for ocf: MediaFileInfo, outputDirectory: URL) async -> BlankRushResult {
        
        // Generate output filename: originalName_blankRush.mov
        let baseName = (ocf.fileName as NSString).deletingPathExtension
        let outputFileName = "\(baseName)_blankRush.mov"
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)
        
        // Simple transcoding using SwiftFFmpeg
        do {
            let success = try await transcodeToProRes(
                inputPath: ocf.url.path,
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
    
    /// Simple transcoding based on remuxing.swift example
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
    
    /// Synchronous transcoding implementation
    private func transcodeToProResSync(inputPath: String, outputPath: String) throws {
        
        print("  📝 Processing: \(inputPath) -> \(outputPath)")
        
        // Input validation
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw TimecodeBlackFramesError(message: "Input file '\(inputPath)' not found!")
        }
        
        // Open input file (following remuxing.swift pattern)
        let inputFormatContext = try AVFormatContext(url: inputPath)
        try inputFormatContext.findStreamInfo()
        
        print("  📝 Input format info:")
        inputFormatContext.dumpFormat(isOutput: false)
        
        // Create output format context for MOV
        let outputFormatContext = try AVFormatContext(format: nil, filename: outputPath)
        
        print("  📝 Output format info:")
        outputFormatContext.dumpFormat(url: outputPath, isOutput: true)
        
        // Create simple stream mapping (video only for now)
        var streamMapping = [Int](repeating: -1, count: inputFormatContext.streamCount)
        var outputStreamIndex = 0
        
        for i in 0..<inputFormatContext.streamCount {
            let inputStream = inputFormatContext.streams[i]
            let inputCodecParams = inputStream.codecParameters
            
            // Only process video streams for now
            if inputCodecParams.mediaType == .video {
                streamMapping[i] = outputStreamIndex
                outputStreamIndex += 1
                
                // Add output stream
                guard let outputStream = outputFormatContext.addStream() else {
                    throw TimecodeBlackFramesError(message: "Failed to add output stream")
                }
                
                // Copy codec parameters but override to ProRes 422 Proxy for space saving
                outputStream.codecParameters.copy(from: inputCodecParams)
                
                // For now, let's just preserve the original codec tag and focus on getting basic transcoding working
                // TODO: Figure out correct ProRes 422 Proxy codec tag later
                print("  📝 Preserving original codec tag: \(String(format: "0x%08x", inputCodecParams.codecTag))")
                
                print("  📝 Added video stream: \(inputCodecParams.width)x\(inputCodecParams.height)")
            }
        }
        
        // Open output file
        if !outputFormatContext.outputFormat!.flags.contains(.noFile) {
            try outputFormatContext.openOutput(url: outputPath, flags: .write)
        }
        
        // Write header
        try outputFormatContext.writeHeader()
        
        // Process packets (following remuxing.swift pattern)
        let packet = AVPacket()
        var frameCount = 0
        let maxFrames = 10  // Limit for testing
        
        while let _ = try? inputFormatContext.readFrame(into: packet) {
            defer {
                packet.unref()
            }
            
            let inputStream = inputFormatContext.streams[packet.streamIndex]
            let outputStreamIdx = streamMapping[packet.streamIndex]
            
            if outputStreamIdx < 0 {
                continue  // Skip non-video streams
            }
            
            // Stop after max frames for testing
            frameCount += 1
            if frameCount > maxFrames {
                print("  📝 Stopping after \(maxFrames) frames for testing")
                break
            }
            
            packet.streamIndex = outputStreamIdx
            let outputStream = outputFormatContext.streams[outputStreamIdx]
            
            // Rescale timestamps (following remuxing.swift pattern)
            packet.pts = AVMath.rescale(
                packet.pts, inputStream.timebase, outputStream.timebase, 
                rounding: .nearInf, passMinMax: true
            )
            packet.dts = AVMath.rescale(
                packet.dts, inputStream.timebase, outputStream.timebase, 
                rounding: .nearInf, passMinMax: true
            )
            packet.duration = AVMath.rescale(packet.duration, inputStream.timebase, outputStream.timebase)
            packet.position = -1
            
            try outputFormatContext.interleavedWriteFrame(packet)
        }
        
        // Write trailer
        try outputFormatContext.writeTrailer()
        
        print("  ✅ Simple transcoding completed: \(outputPath)")
        print("  📝 Processed \(frameCount) frames")
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