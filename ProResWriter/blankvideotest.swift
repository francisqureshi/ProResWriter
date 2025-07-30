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
    
    // Performance timers
    let totalStartTime = CFAbsoluteTimeGetCurrent()
    
    // Video properties
    let width = 1920
    let height = 1080
    let frameRate: Int32 = 25
    let duration: Double = 1200.0 // 10 seconds
    
    // Create output URL
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let outputURL = documentsPath.appendingPathComponent("blank_video_1920x1080_25fps.mov")
    
    print("📹 Creating video: \(width)x\(height) @ \(frameRate)fps for \(duration)s")
    print("📁 Output: \(outputURL.path)")
    
    // Remove existing file if it exists
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    // Setup timer
    let setupStartTime = CFAbsoluteTimeGetCurrent()
    
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
    
    let setupEndTime = CFAbsoluteTimeGetCurrent()
    let setupTime = setupEndTime - setupStartTime
    print("📊 Setup time: \(String(format: "%.2f", setupTime))s")
    
    // Start writing
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    
    // Calculate frame duration
    let frameDuration = CMTime(value: 1, timescale: frameRate)
    let totalFrames = Int(duration * Double(frameRate))
    
    print("📊 Generating \(totalFrames) frames...")
    
    // Create one black pixel buffer to reuse for all frames
    guard let blackPixelBuffer = createBlackPixelBuffer(width: width, height: height) else {
        print("❌ Failed to create black pixel buffer")
        return
    }
    print("✅ Created reusable black pixel buffer")
    
    // Generation timer
    let generationStartTime = CFAbsoluteTimeGetCurrent()
    
    // Generate frames with reliable readiness checking
    let batchSize = 50 // Process 50 frames at a time
    var frameIndex = 0
    
    while frameIndex < totalFrames {
        // Process a batch of frames
        let endIndex = min(frameIndex + batchSize, totalFrames)
        
        for i in frameIndex..<endIndex {
            // Wait for writer to be ready with efficient sleep
            while !videoWriterInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.0005) // 0.5ms - balanced for speed and reliability
            }
            
            // Calculate presentation time
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            
            // Append the same black pixel buffer for each frame
            let success = pixelBufferAdaptor.append(blackPixelBuffer, withPresentationTime: presentationTime)
            if !success {
                print("❌ Failed to append frame \(i)")
            }
        }
        
        frameIndex = endIndex
        
        // Progress update every 1000 frames (40 seconds at 25fps) for better performance
        if frameIndex % 1000 == 0 || frameIndex >= totalFrames {
            let progress = Double(frameIndex) / Double(totalFrames)
            let percentage = Int(progress * 100)
            print("📹 Progress: \(percentage)% (\(frameIndex)/\(totalFrames) frames)")
        }
    }
    
    let generationEndTime = CFAbsoluteTimeGetCurrent()
    let generationTime = generationEndTime - generationStartTime
    print("📊 Frame generation time: \(String(format: "%.2f", generationTime))s")
    
    // Finish writing and wait for completion
    videoWriterInput.markAsFinished()
    
    // Export timer
    let exportStartTime = CFAbsoluteTimeGetCurrent()
    
    // Use semaphore to wait for completion
    let semaphore = DispatchSemaphore(value: 0)
    
    assetWriter.finishWriting {
        let exportEndTime = CFAbsoluteTimeGetCurrent()
        let exportTime = exportEndTime - exportStartTime
        let totalTime = exportEndTime - totalStartTime
        
        print("✅ Blank video creation completed!")
        print("📁 Output file: \(outputURL.path)")
        
        // Performance analysis
        print("📊 Performance Analysis:")
        print("   Setup time: \(String(format: "%.2f", setupTime))s")
        print("   Generation time: \(String(format: "%.2f", generationTime))s")
        print("   Export time: \(String(format: "%.2f", exportTime))s")
        print("   Total time: \(String(format: "%.2f", totalTime))s")
        
        // Calculate percentages
        let setupPercentage = (setupTime / totalTime) * 100
        let generationPercentage = (generationTime / totalTime) * 100
        let exportPercentage = (exportTime / totalTime) * 100
        
        print("📊 Time breakdown:")
        print("   Setup: \(String(format: "%.1f", setupPercentage))%")
        print("   Generation: \(String(format: "%.1f", generationPercentage))%")
        print("   Export: \(String(format: "%.1f", exportPercentage))%")
        
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
