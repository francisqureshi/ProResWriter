//
//  importProcess.swift
//  ProResWriter
//
//  Created by francisqureshi on 15/08/2025.
//

import Foundation
import SwiftFFmpeg
import TimecodeKit

// MARK: - Media File Information
struct MediaFileInfo {
    let fileName: String
    let url: URL
    let resolution: CGSize
    let frameRate: Float
    let sourceTimecode: String?
    let reelName: String?
    let isInterlaced: Bool
    let fieldOrder: String?
    let mediaType: MediaType
}

enum MediaType {
    case gradedSegment
    case originalCameraFile
}

// MARK: - Media Analysis
class MediaAnalyzer {

    func analyzeMediaFile(at url: URL, type: MediaType) async throws -> MediaFileInfo {
        // Try to get real properties using SwiftFFmpeg
        var resolution = CGSize(width: 1920, height: 1080)  // fallback
        var frameRate: Float = 25.0  // fallback
        var sourceTimecode: String? = nil
        var reelName: String? = nil
        var isInterlaced: Bool = false  // fallback to progressive
        var fieldOrder: String? = nil

        do {
            let fmtCtx = try AVFormatContext(url: url.path)
            try fmtCtx.findStreamInfo()

            // Find video stream manually since the API seems different
            for i in 0..<fmtCtx.streamCount {
                let stream = fmtCtx.streams[Int(i)]
                let codecPar = stream.codecParameters

                // Check if this is a video stream by checking if it has width/height
                if codecPar.width > 0 && codecPar.height > 0 {
                    resolution = CGSize(
                        width: CGFloat(codecPar.width), height: CGFloat(codecPar.height))

                    // Extract frame rate using averageFramerate
                    let avgFR = stream.averageFramerate
                    if avgFR.den > 0 {
                        frameRate = Float(avgFR.num) / Float(avgFR.den)
                        print("    📊 averageFramerate: \(frameRate)fps (\(avgFR.num)/\(avgFR.den))")
                    }
                    
                    // Explore additional stream properties
                    print("    🔍 Additional stream info:")
                    
                    // frameCount
                    print("    🎞️ frameCount: \(stream.frameCount)")
                    
                    // startTime
                    print("    🚀 startTime: \(stream.startTime)")
                    
                    // duration
                    print("    ⏱️ duration: \(stream.duration)")
                    
                    // Stream metadata
                    if !stream.metadata.isEmpty {
                        print("    📋 Stream metadata:")
                        for (key, value) in stream.metadata {
                            print("      \(key): \(value)")
                        }
                    } else {
                        print("    📋 No stream metadata found")
                    }

                    // Extract timecode using same approach as ffmpeg script
                    sourceTimecode = extractTimecode(from: fmtCtx, stream: stream)
                    
                    // Extract reel name from metadata
                    reelName = extractReelName(from: fmtCtx)
                    
                    // Detect interlaced vs progressive
                    let (interlaced, order) = detectInterlacing(from: stream)
                    isInterlaced = interlaced
                    fieldOrder = order

                    break
                }
            }
        } catch {
            print("    ⚠️ FFmpeg analysis failed: \(error) - using fallback values")
        }

        
        return MediaFileInfo(
            fileName: url.lastPathComponent,
            url: url,
            resolution: resolution,
            frameRate: frameRate,
            sourceTimecode: sourceTimecode,
            reelName: reelName,
            isInterlaced: isInterlaced,
            fieldOrder: fieldOrder,
            mediaType: type
        )
    }

    private func extractTimecode(from formatContext: AVFormatContext, stream: AVStream) -> String? {
        // Method 1: Check format metadata first (like ffprobe format_tags=timecode)
        if let timecode = formatContext.metadata["timecode"] {
            print("    🎬 Found timecode in format metadata: \(timecode)")
            return timecode
        }

        // Method 2: Check stream metadata (like ffprobe stream_tags=timecode)  
        if let timecode = stream.metadata["timecode"] {
            print("    🎬 Found timecode in stream metadata: \(timecode)")
            return timecode
        }

        // Method 3: Check additional common timecode metadata keys
        let timecodeKeys = ["SMPTE_time_code", "tc", "TimeCode", "start_timecode"]
        
        // Check format level first
        for key in timecodeKeys {
            if let value = formatContext.metadata[key] {
                print("    🎬 Found timecode in format metadata (\(key)): \(value)")
                return value
            }
        }
        
        // Then check stream level
        for key in timecodeKeys {
            if let value = stream.metadata[key] {
                print("    🎬 Found timecode in stream metadata (\(key)): \(value)")
                return value
            }
        }

        print("    ⚠️ No timecode found in metadata")
        return nil
    }

    private func extractReelName(from formatContext: AVFormatContext) -> String? {
        // Common reel name metadata keys
        let reelKeys = ["reel", "reel_name", "tape_name", "source_reel", "camera_name"]

        for key in reelKeys {
            if let value = formatContext.metadata[key] {
                return value
            }
        }

        return nil
    }
    
    private func detectInterlacing(from stream: AVStream) -> (Bool, String?) {
        // Method 1: Check codec parameters for field order
        let codecPar = stream.codecParameters
        
        // Check for field order in codec parameters - this is the most reliable
        if codecPar.fieldOrder.rawValue != 0 { // AV_FIELD_UNKNOWN = 0
            let fieldOrderName = getFieldOrderName(codecPar.fieldOrder)
            let isInterlaced = fieldOrderName != "progressive"
            
            print("    🎬 Field order from codec: \(fieldOrderName) (interlaced: \(isInterlaced))")
            return (isInterlaced, fieldOrderName)
        }
        
        // Method 2: Check metadata for interlacing hints
        let interlacedKeys = ["field_order", "interlaced", "scan_type", "progressive"]
        
        for key in interlacedKeys {
            if let value = stream.metadata[key] {
                print("    🎬 Found scan info in stream metadata (\(key)): \(value)")
                
                let isInterlaced = determineInterlacingFromMetadata(key: key, value: value)
                return (isInterlaced, value)
            }
        }
        
        // Method 3: Heuristic based on frame rate and resolution
        let frameRate = stream.averageFramerate  // Note: different capitalization in SwiftFFmpeg
        if frameRate.den > 0 {
            let fps = Float(frameRate.num) / Float(frameRate.den)
            let height = codecPar.height
            
            // Common interlaced formats
            if height == 480 && (abs(fps - 29.97) < 0.1 || abs(fps - 59.94) < 0.1) {
                print("    🎬 NTSC SD detected - likely interlaced")
                return (true, "ntsc_interlaced")
            } else if height == 576 && abs(fps - 25.0) < 0.1 {
                print("    🎬 PAL SD detected - likely interlaced")
                return (true, "pal_interlaced")
            } else if height >= 720 {
                print("    🎬 HD/4K detected - likely progressive")
                return (false, "progressive")
            }
        }
        
        print("    🎬 No interlacing info found - assuming progressive")
        return (false, "progressive")
    }
    
    private func getFieldOrderName(_ fieldOrder: AVFieldOrder) -> String {
        // Use numeric values instead of constants for compatibility
        switch fieldOrder.rawValue {
        case 1: // Progressive
            return "progressive"
        case 2: // Top field first
            return "top_field_first"
        case 3: // Bottom field first
            return "bottom_field_first"
        case 4: // Top then bottom
            return "top_bottom"
        case 5: // Bottom then top
            return "bottom_top"
        default:
            return "unknown"
        }
    }
    
    private func determineInterlacingFromMetadata(key: String, value: String) -> Bool {
        let lowerValue = value.lowercased()
        
        switch key {
        case "progressive":
            return lowerValue == "0" || lowerValue == "false"
        case "interlaced":
            return lowerValue == "1" || lowerValue == "true"
        case "scan_type":
            return lowerValue.contains("interlac")
        case "field_order":
            return !lowerValue.contains("prog")
        default:
            return false
        }
    }
}

enum MediaAnalysisError: Error {
    case noVideoTrack
    case unsupportedFormat
    case fileNotFound
}

// MARK: - Import Process
class ImportProcess {
    private let analyzer = MediaAnalyzer()

    // Import graded segments from a directory
    func importGradedSegments(from directoryURL: URL) async throws -> [MediaFileInfo] {
        print("🎬 Importing graded segments from: \(directoryURL.path)")
        return try await importMediaFiles(from: directoryURL, type: .gradedSegment)
    }

    // Import original camera files from a directory
    func importOriginalCameraFiles(from directoryURL: URL) async throws -> [MediaFileInfo] {
        print("📹 Importing original camera files from: \(directoryURL.path)")
        return try await importMediaFiles(from: directoryURL, type: .originalCameraFile)
    }

    // Generic function to import media files
    private func importMediaFiles(from directoryURL: URL, type: MediaType) async throws
        -> [MediaFileInfo]
    {
        let fileManager = FileManager.default

        // Get all video files from directory
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil
        )
        .filter { isVideoFile($0) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var mediaFiles: [MediaFileInfo] = []

        for url in fileURLs {
            print("  📂 Processing: \(url.lastPathComponent)")

            do {
                let mediaInfo = try await analyzer.analyzeMediaFile(at: url, type: type)
                mediaFiles.append(mediaInfo)

                // Print extracted info
                print(
                    "    Resolution: \(Int(mediaInfo.resolution.width))x\(Int(mediaInfo.resolution.height))"
                )
                print("    Frame Rate: \(mediaInfo.frameRate)fps")
                print("    Scan Type: \(mediaInfo.isInterlaced ? "Interlaced" : "Progressive")")
                if let fieldOrder = mediaInfo.fieldOrder {
                    print("    Field Order: \(fieldOrder)")
                }
                if let timecode = mediaInfo.sourceTimecode {
                    print("    Source Timecode: \(timecode)")
                }
                if let reel = mediaInfo.reelName {
                    print("    Reel Name: \(reel)")
                }

            } catch {
                print("    ⚠️ Failed to analyze: \(error)")
            }
        }

        print(
            "✅ Imported \(mediaFiles.count) \(type == .gradedSegment ? "graded segments" : "original camera files")"
        )
        return mediaFiles
    }

    // Check if file is a supported video format
    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mov", "mp4", "mxf", "avi", "mkv", "m4v", "prores"]
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
}
