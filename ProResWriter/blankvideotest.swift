//
//  Learning.swift
//  ProResWriter
//
//  Created by mac10 on 29/07/2025.
//

import Foundation
import AVFoundation
import CoreMedia
import TimecodeKit

func blankvideo() {
    print("🎬 Creating blank black video file...")
    
    // Video properties
    let width = 1920
    let height = 1080
    let frameRate: Int32 = 25
    let duration: Double = 10.0 // 10 seconds
    
    // Create output URL
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let outputURL = documentsPath.appendingPathComponent("blank_video_1920x1080_25fps.mov")
    
    print("📹 Creating video: \(width)x\(height) @ \(frameRate)fps for \(duration)s")
    print("📁 Output: \(outputURL.path)")
    
    // Remove existing file if it exists
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    // Create asset writer
    guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
        print("❌ Failed to create asset writer")
        return
    }
    
    // Use  ProRes settings with 709  color primaries
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.proRes422,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ]
    
    // Create video input
    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoWriterInput.expectsMediaDataInRealTime = false
    
    // Create pixel buffer adaptor
    let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ]
    
    let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoWriterInput,
        sourcePixelBufferAttributes: pixelBufferAttributes
    )
    
    // Add input to writer
    guard assetWriter.canAdd(videoWriterInput) else {
        print("❌ Cannot add video input to asset writer")
        return
    }
    assetWriter.add(videoWriterInput)
    
    // Start writing
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    
    // Calculate frame duration
    let frameDuration = CMTime(value: 1, timescale: frameRate)
    let totalFrames = Int(duration * Double(frameRate))
    
    print("📊 Generating \(totalFrames) frames...")
    
    // Generate frames
    for frameIndex in 0..<totalFrames {
        // Wait for writer to be ready
        while !videoWriterInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.001) // 1ms
        }
        
        // Create black pixel buffer
        guard let pixelBuffer = createBlackPixelBuffer(width: width, height: height) else {
            print("❌ Failed to create pixel buffer for frame \(frameIndex)")
            continue
        }
        
        // Calculate presentation time
        let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
        
        // Append frame
        let success = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        if !success {
            print("❌ Failed to append frame \(frameIndex)")
        }
        
        // Progress update every 25 frames (1 second at 25fps)
        if frameIndex % 25 == 0 {
            let progress = Double(frameIndex) / Double(totalFrames)
            let percentage = Int(progress * 100)
            print("📹 Progress: \(percentage)% (\(frameIndex)/\(totalFrames) frames)")
        }
    }
    
    // Finish writing and wait for completion
    videoWriterInput.markAsFinished()
    
    // Use semaphore to wait for completion
    let semaphore = DispatchSemaphore(value: 0)
    
    assetWriter.finishWriting {
        print("✅ Blank video creation completed!")
        print("📁 Output file: \(outputURL.path)")
        
        // Verify file was created
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let fileSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64
            print("📊 File size: \(fileSize ?? 0) bytes")
            
            if let fileSize = fileSize, fileSize > 0 {
                print("✅ Video file created successfully!")
                print("📊 File size: \(fileSize) bytes")
            } else {
                print("❌ Video file may be corrupted (zero size)")
            }
        } else {
            print("❌ Output file was not created")
        }
        
        semaphore.signal()
    }
    
    // Wait for completion
    semaphore.wait()
    print("🎬 Blank video creation process finished!")
}

// Helper function to create a black pixel buffer
private func createBlackPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ]
    
    let result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    
    if result == kCVReturnSuccess, let buffer = pixelBuffer {
        CVPixelBufferLockBaseAddress(buffer, [])
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        // Fill with black pixels (BGRA: 0, 0, 0, 255)
        if let baseAddress = baseAddress {
            let pixelData = baseAddress.assumingMemoryBound(to: UInt8.self)
            for i in 0..<(bytesPerRow * height / 4) {
                let pixelIndex = i * 4
                pixelData[pixelIndex] = 0      // B
                pixelData[pixelIndex + 1] = 0  // G
                pixelData[pixelIndex + 2] = 0  // R
                pixelData[pixelIndex + 3] = 255 // A
            }
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
    
    return nil
}
