//
//  main.swift
//  ProResWriter
//
//  Created by Francis Qureshi on 26/07/2025.
//

import Foundation

print("Hello, ProRes!")

import AVFoundation
import CoreMedia
import AppKit

// MARK: - Data Models
struct GradedSegment {
    let url: URL
    let startTime: CMTime  // Start time in the final timeline
    let duration: CMTime   // Duration of the segment
    let sourceStartTime: CMTime // Start time in the source segment file
}

struct CompositorSettings {
    let outputURL: URL
    let baseVideoURL: URL
    let gradedSegments: [GradedSegment]
    let proResType: AVVideoCodecType // .proRes422, .proRes422HQ, etc.
}

// MARK: - Main Compositor Class
class ProResVideoCompositor: NSObject {
    
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
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
                await MainActor.run {
                    completionHandler?(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Core Processing
    private func processComposition(settings: CompositorSettings) async throws -> URL {
        
        // 1. Analyze base video to get properties
        let baseAsset = AVURLAsset(url: settings.baseVideoURL)
        let baseTrack = try await getVideoTrack(from: baseAsset)
        let baseProperties = try await getVideoProperties(from: baseTrack)
        
        // 2. Setup output writer
        try setupAssetWriter(
            outputURL: settings.outputURL,
            properties: baseProperties,
            proResType: settings.proResType
        )
        
        // 3. Load and prepare graded segments
        let segmentReaders = try await prepareSegmentReaders(settings.gradedSegments)
        
        // 4. Start writing process
        guard let assetWriter = assetWriter,
              let videoWriterInput = videoWriterInput,
              let pixelBufferAdaptor = pixelBufferAdaptor else {
            throw CompositorError.setupFailed
        }
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        // 5. Process frame by frame
        try await processFrames(
            baseAsset: baseAsset,
            baseProperties: baseProperties,
            segmentReaders: segmentReaders,
            gradedSegments: settings.gradedSegments,
            videoWriterInput: videoWriterInput,
            pixelBufferAdaptor: pixelBufferAdaptor
        )
        
        // 6. Finalize
        videoWriterInput.markAsFinished()
        await assetWriter.finishWriting()
        
        return settings.outputURL
    }
    
    // MARK: - Asset Writer Setup
    private func setupAssetWriter(outputURL: URL, properties: VideoProperties, proResType: AVVideoCodecType) throws {
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Configure video settings for ProRes
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: proResType,
            AVVideoWidthKey: properties.width,
            AVVideoHeightKey: properties.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: properties.colorPrimaries,
                AVVideoTransferFunctionKey: properties.transferFunction,
                AVVideoYCbCrMatrixKey: properties.yCbCrMatrix
            ]
        ]
        
        // Create video input
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = false
        
        // Create pixel buffer adaptor
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr8,
            kCVPixelBufferWidthKey as String: properties.width,
            kCVPixelBufferHeightKey as String: properties.height
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        // Add input to writer
        guard let assetWriter = assetWriter,
              let videoWriterInput = videoWriterInput,
              assetWriter.canAdd(videoWriterInput) else {
            throw CompositorError.cannotAddInput
        }
        
        assetWriter.add(videoWriterInput)
    }
    
    // MARK: - Frame Processing
    private func processFrames(
        baseAsset: AVAsset,
        baseProperties: VideoProperties,
        segmentReaders: [URL: AVAssetReader],
        gradedSegments: [GradedSegment],
        videoWriterInput: AVAssetWriterInput,
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        
        let frameDuration = CMTime(value: 1, timescale: baseProperties.frameRate)
        let totalDuration = try await baseAsset.load(.duration)
        let totalFrames = Int(totalDuration.seconds * Double(baseProperties.frameRate))
        
        var currentTime = CMTime.zero
        var frameIndex = 0
        
        // Create base reader for fallback frames
        let baseReader = try AVAssetReader(asset: baseAsset)
        let baseOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [try await getVideoTrack(from: baseAsset)], videoSettings: nil)
        baseReader.add(baseOutput)
        baseReader.startReading()
        
        while frameIndex < totalFrames {
            
            // Wait for writer to be ready
            while !videoWriterInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            
            // Determine which segment (if any) should be active at this time
            let activeSegment = findActiveSegment(at: currentTime, in: gradedSegments)
            
            var pixelBuffer: CVPixelBuffer?
            
            if let segment = activeSegment {
                // Use graded segment frame
                pixelBuffer = try await getFrameFromSegment(
                    segment: segment,
                    atTime: currentTime,
                    from: segmentReaders
                )
            }
            
            // Fallback to base video frame if no graded segment available
            if pixelBuffer == nil {
                pixelBuffer = getNextFrameFromReader(baseOutput)
            }
            
            // Create blank frame if still no pixel buffer
            if pixelBuffer == nil {
                pixelBuffer = createBlankFrame(properties: baseProperties)
            }
            
            // Append frame
            if let buffer = pixelBuffer {
                let success = pixelBufferAdaptor.append(buffer, withPresentationTime: currentTime)
                if !success {
                    throw CompositorError.failedToAppendFrame
                }
            }
            
            // Update progress
            let progress = Double(frameIndex) / Double(totalFrames)
            await MainActor.run {
                progressHandler?(progress)
            }
            
            currentTime = CMTimeAdd(currentTime, frameDuration)
            frameIndex += 1
        }
    }
    
    // MARK: - Helper Methods
    private func getVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw CompositorError.noVideoTrack
        }
        return videoTrack
    }
    
    private func getVideoProperties(from track: AVAssetTrack) async throws -> VideoProperties {
        let naturalSize = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let formatDescriptions = try await track.load(.formatDescriptions)
        
        var colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        var transferFunction = AVVideoTransferFunction_ITU_R_709_2
        var yCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        
        // Extract color information if available
        if let formatDescription = formatDescriptions.first {
            let extensions = CMFormatDescriptionGetExtensions(formatDescription)
            if let colorProperties = extensions?[kCMFormatDescriptionExtension_ColorPrimaries] {
                colorPrimaries = colorProperties as! String
            }
            if let transferProperties = extensions?[kCMFormatDescriptionExtension_TransferFunction] {
                transferFunction = transferProperties as! String
            }
            if let matrixProperties = extensions?[kCMFormatDescriptionExtension_YCbCrMatrix] {
                yCbCrMatrix = matrixProperties as! String
            }
        }
        
        return VideoProperties(
            width: Int(naturalSize.width),
            height: Int(naturalSize.height),
            frameRate: Int32(nominalFrameRate),
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            yCbCrMatrix: yCbCrMatrix
        )
    }
    
    private func prepareSegmentReaders(_ segments: [GradedSegment]) async throws -> [URL: AVAssetReader] {
        var readers: [URL: AVAssetReader] = [:]
        
        for segment in segments {
            if readers[segment.url] == nil {
                let asset = AVURLAsset(url: segment.url)
                let reader = try AVAssetReader(asset: asset)
                
                let videoTrack = try await getVideoTrack(from: asset)
                let output = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: nil)
                
                reader.add(output)
                readers[segment.url] = reader
            }
        }
        
        return readers
    }
    
    private func findActiveSegment(at time: CMTime, in segments: [GradedSegment]) -> GradedSegment? {
        return segments.first { segment in
            let endTime = CMTimeAdd(segment.startTime, segment.duration)
            return time >= segment.startTime && time < endTime
        }
    }
    
    private func getFrameFromSegment(
        segment: GradedSegment,
        atTime time: CMTime,
        from readers: [URL: AVAssetReader]
    ) async throws -> CVPixelBuffer? {
        guard let reader = readers[segment.url] else { return nil }
        
        if reader.status == .unknown {
            reader.startReading()
        }
        
        // This is simplified - in practice you'd need more sophisticated frame seeking
        guard let output = reader.outputs.first as? AVAssetReaderVideoCompositionOutput else {
            return nil
        }
        
        return getNextFrameFromReader(output)
    }
    
    private func getNextFrameFromReader(_ output: AVAssetReaderVideoCompositionOutput) -> CVPixelBuffer? {
        guard let sampleBuffer = output.copyNextSampleBuffer() else { return nil }
        return CMSampleBufferGetImageBuffer(sampleBuffer)
    }
    
    private func createBlankFrame(properties: VideoProperties) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr8,
            kCVPixelBufferWidthKey as String: properties.width,
            kCVPixelBufferHeightKey as String: properties.height
        ]
        
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            properties.width,
            properties.height,
            kCVPixelFormatType_422YpCbCr8,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        if result == kCVReturnSuccess, let buffer = pixelBuffer {
            // Fill with black (or whatever background color you want)
            CVPixelBufferLockBaseAddress(buffer, [])
            let baseAddress = CVPixelBufferGetBaseAddress(buffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            
            memset(baseAddress, 0, bytesPerRow * height)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            
            return buffer
        }
        
        return nil
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
}

enum CompositorError: Error {
    case setupFailed
    case noVideoTrack
    case cannotAddInput
    case failedToAppendFrame
    case invalidSegment
}

// MARK: - Usage Example
class VideoCompositorViewController: NSViewController {
    
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var statusLabel: NSTextField!
    
    private let compositor = ProResVideoCompositor()
    
    func startComposition() {
        // Define your graded segments
        let segments = [
            GradedSegment(
                url: URL(fileURLWithPath: "/Users/fq/Desktop/PRWriter/mm/Burberry Outerwear-Social_5K_XQ_25FPS_LR001_LOG_G0          S01.mov"),
                startTime: CMTime(seconds: 10, preferredTimescale: 600),  // Start at 10 seconds
                duration: CMTime(seconds: 5, preferredTimescale: 600),    // 5 seconds long
                sourceStartTime: .zero
            ),
            GradedSegment(
                url: URL(fileURLWithPath: "/Users/fq/Desktop/PRWriter/mm/Burberry Outerwear-Social_5K_XQ_25FPS_LR001_LOG_G0          S02.mov"),
                startTime: CMTime(seconds: 30, preferredTimescale: 600),  // Start at 30 seconds
                duration: CMTime(seconds: 8, preferredTimescale: 600),    // 8 seconds long
                sourceStartTime: .zero
            )
        ]
        
        let settings = CompositorSettings(
            outputURL: URL(fileURLWithPath: "/Users/fq/Desktop/PRWriter/out/BB_output.mov"),
            baseVideoURL: URL(fileURLWithPath: "/Users/fq/Desktop/PRWriter/src/Burberry Outerwear-Social_5K_XQ_25FPS_LR001_LOG_SOURCE.mov"),
            gradedSegments: segments,
            proResType: .proRes422HQ
        )
        
        // Setup callbacks
        compositor.progressHandler = { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressIndicator.doubleValue = progress * 100
                self?.statusLabel.stringValue = "Processing: \(Int(progress * 100))%"
            }
        }
        
        compositor.completionHandler = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let outputURL):
                    self?.statusLabel.stringValue = "Complete: \(outputURL.lastPathComponent)"
                case .failure(let error):
                    self?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                }
            }
        }
        
        // Start the composition
        compositor.composeVideo(with: settings)
    }
}
