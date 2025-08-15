//
//  importProcess.swift
//  ProResWriter
//
//  Created by mac10 on 15/08/2025.
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
        var resolution = CGSize(width: 1920, height: 1080) // fallback
        var frameRate: Float = 25.0 // fallback
        
        do {
            let fmtCtx = try AVFormatContext(url: url.path)
            try fmtCtx.findStreamInfo()
            
            // Find video stream manually since the API seems different
            for i in 0..<fmtCtx.streamCount {
                let stream = fmtCtx.streams[Int(i)]
                let codecPar = stream.codecParameters
                
                // Check if this is a video stream by checking if it has width/height
                if codecPar.width > 0 && codecPar.height > 0 {
                    resolution = CGSize(width: CGFloat(codecPar.width), height: CGFloat(codecPar.height))
                    
                    // Try to extract frame rate using realFramerate
                    let realFR = stream.realFramerate
                    if realFR.den > 0 {
                        frameRate = Float(realFR.num) / Float(realFR.den)
                    }
                    
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
            sourceTimecode: nil, // placeholder for now
            reelName: nil, // placeholder for now
            mediaType: type
        )
    }
    
    private func extractTimecode(from formatContext: AVFormatContext) -> String? {
        // Check for timecode in metadata
        if let timecode = formatContext.metadata["timecode"] {
            return timecode
        }
        
        // Check for common timecode metadata keys
        let timecodeKeys = ["timecode", "SMPTE_time_code", "tc", "TimeCode"]
        
        for key in timecodeKeys {
            if let value = formatContext.metadata[key] {
                return value
            }
        }
        
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
    private func importMediaFiles(from directoryURL: URL, type: MediaType) async throws -> [MediaFileInfo] {
        let fileManager = FileManager.default
        
        // Get all video files from directory
        let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { isVideoFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        var mediaFiles: [MediaFileInfo] = []
        
        for url in fileURLs {
            print("  📂 Processing: \(url.lastPathComponent)")
            
            do {
                let mediaInfo = try await analyzer.analyzeMediaFile(at: url, type: type)
                mediaFiles.append(mediaInfo)
                
                // Print extracted info
                print("    Resolution: \(Int(mediaInfo.resolution.width))x\(Int(mediaInfo.resolution.height))")
                print("    Frame Rate: \(mediaInfo.frameRate)fps")
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
        
        print("✅ Imported \(mediaFiles.count) \(type == .gradedSegment ? "graded segments" : "original camera files")")
        return mediaFiles
    }
    
    // Check if file is a supported video format
    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mov", "mp4", "mxf", "avi", "mkv", "m4v", "prores"]
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
}

