//
//  Learning.swift
//  ProResWriter
//
//  Created by mac10 on 29/07/2025.
//

import AVFoundation
import CoreMedia
import Foundation
import TimecodeKit

func blankvideo() {
    print("🎬 Creating blank black video file...")

    // Performance timers
    let totalStartTime = CFAbsoluteTimeGetCurrent()

    // Video properties
    let width = 3840
    let height = 2160
    let frameRate: Int32 = 25
    let duration: Double = 10.0  // 10 seconds

    // Create output URL
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!
    let outputURL = documentsPath.appendingPathComponent(
        "blank_video_\(width)x\(height)_\(frameRate)fps.mov")

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
    print("✅ Asset writer created")

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

    // Create timecode track
    let timecodeWriterInput = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil)
    print("✅ Timecode input created")

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

    // Add video input to asset writer
    guard assetWriter.canAdd(videoWriterInput) else {
        print("❌ Cannot add video input to asset writer")
        return
    }
    assetWriter.add(videoWriterInput)

    // Add timecode input to asset writer
    if assetWriter.canAdd(timecodeWriterInput) {
        assetWriter.add(timecodeWriterInput)
        print("✅ Timecode input added to asset writer")

        // Associate timecode track with video track BEFORE starting session
        videoWriterInput.addTrackAssociation(
            withTrackOf: timecodeWriterInput, type: AVAssetTrack.AssociationType.timecode.rawValue)
        print("✅ Timecode track associated with video track")
    } else {
        print("⚠️ Cannot add timecode input to asset writer - continuing without timecode")
    }

    let setupEndTime = CFAbsoluteTimeGetCurrent()
    let setupTime = setupEndTime - setupStartTime
    print("📊 Setup time: \(String(format: "%.2f", setupTime))s")

    // Start writing
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)

    // Add timecode sample BEFORE video frame generation (if timecode input was added)
    if assetWriter.inputs.contains(timecodeWriterInput) {
        print("⏰ Adding timecode sample before video generation...")

        // Create timecode sample buffer
        guard
            let timecodeSampleBuffer = createTimecodeSampleBuffer(
                frameRate: frameRate, duration: duration)
        else {
            print("❌ Failed to create timecode sample buffer")
            return
        }
        print("✅ Timecode sample buffer created")

        // Append timecode sample with timeout
        // Following Apple's pattern: check isReadyForMoreMediaData before appending
        var timecodeWaitCount = 0
        while !timecodeWriterInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.001)
            timecodeWaitCount += 1
            if timecodeWaitCount > 1000 {  // 1 second timeout
                print("❌ Timeout waiting for timecode writer to be ready")
                return
            }
        }

        // Append the timecode sample buffer (same as Apple's appendSampleBuffer method)
        let timecodeSuccess = timecodeWriterInput.append(timecodeSampleBuffer)
        if !timecodeSuccess {
            print("❌ Failed to append timecode sample")
            return
        } else {
            print("✅ Timecode sample appended successfully")

            // Debug: Check if timecode sample buffer has data
            if let dataBuffer = CMSampleBufferGetDataBuffer(timecodeSampleBuffer) {
                var dataLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    dataBuffer, atOffset: 0, lengthAtOffsetOut: &dataLength, totalLengthOut: nil,
                    dataPointerOut: &dataPointer)
                if status == kCMBlockBufferNoErr, let pointer = dataPointer {
                    let frameNumber = pointer.withMemoryRebound(to: Int32.self, capacity: 1) {
                        $0.pointee
                    }
                    print("🔍 Timecode sample buffer contains frame number: \(frameNumber)")
                }
            }
        }

        timecodeWriterInput.markAsFinished()
        print("✅ Timecode track finished")
    }

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
    let batchSize = 50  // Process 50 frames at a time
    var frameIndex = 0

    print("🎬 Starting frame generation...")

    while frameIndex < totalFrames {
        // Process a batch of frames
        let endIndex = min(frameIndex + batchSize, totalFrames)

        for i in frameIndex..<endIndex {
            // Wait for writer to be ready with timeout
            var waitCount = 0
            while !videoWriterInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)  // 1ms
                waitCount += 1
                if waitCount > 1000 {  // 1 second timeout
                    print("❌ Timeout waiting for video writer to be ready")
                    return
                }
            }

            // Calculate presentation time
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))

            // Append the same black pixel buffer for each frame
            let success = pixelBufferAdaptor.append(
                blackPixelBuffer, withPresentationTime: presentationTime)
            if !success {
                print("❌ Failed to append frame \(i)")
                return
            }
        }

        frameIndex = endIndex

        // Progress update every 50 frames for better visibility
        if frameIndex % 50 == 0 || frameIndex >= totalFrames {
            let progress = Double(frameIndex) / Double(totalFrames)
            let percentage = Int(progress * 100)
            print("📹 Progress: \(percentage)% (\(frameIndex)/\(totalFrames) frames)")
        }
    }

    let generationEndTime = CFAbsoluteTimeGetCurrent()
    let generationTime = generationEndTime - generationStartTime
    print("📊 Frame generation time: \(String(format: "%.2f", generationTime))s")

    // Timecode sample already added before video generation

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
            let fileSize =
                try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64
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
                pixelData[pixelIndex] = 0  // B
                pixelData[pixelIndex + 1] = 0  // G
                pixelData[pixelIndex + 2] = 0  // R
                pixelData[pixelIndex + 3] = 255  // A
            }
        }

        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    return nil
}

// Helper function to create a timecode sample buffer
private func createTimecodeSampleBuffer(frameRate: Int32, duration: Double) -> CMSampleBuffer? {
    var sampleBuffer: CMSampleBuffer?
    var dataBuffer: CMBlockBuffer?
    var formatDescription: CMTimeCodeFormatDescription?

    // Create timecode sample data using CVSMPTETime structure
    // Following Apple's example: SMPTE time 00:00:02:00 (HH:MM:SS:FF), 25fps non-drop frame format
    var timecodeSample = CVSMPTETime()
    timecodeSample.hours = 4  // HH
    timecodeSample.minutes = 3  // MM
    timecodeSample.seconds = 2  // SS
    timecodeSample.frames = 1  // FF
    print(
        "⏰ Created CVSMPTETime: \(String(format: "%02d:%02d:%02d:%02d", timecodeSample.hours, timecodeSample.minutes, timecodeSample.seconds, timecodeSample.frames))"
    )

    // Create format description for timecode media (following Apple's example)
    // frameDuration: CMTimeMake(1, 25) for 25fps non-drop frame
    // frameQuanta: 25 for 25fps
    // flags: kCMTimeCodeFlag_24HourMax (no drop frame for 25fps)
    let tcFlags = kCMTimeCodeFlag_24HourMax
    let frameDuration = CMTime(value: 1, timescale: frameRate)

    let status = CMTimeCodeFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
        frameDuration: frameDuration,
        frameQuanta: UInt32(frameRate),
        flags: tcFlags,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )

    guard status == noErr, let formatDescription = formatDescription else {
        print("❌ Could not create timecode format description, status: \(status)")
        return nil
    }
    print("✅ Timecode format description created successfully")

    // Use Apple's utility function to convert CVSMPTETime time into frame number to write
    // Following Apple's example: frameNumber32ForTimecodeUsingFormatDescription
    // For 64-bit timecode, we'll calculate manually since we're using Int64
    var frameNumberData: Int32 =
        Int32(timecodeSample.hours) * 3600 * frameRate  // hours to frames
        + Int32(timecodeSample.minutes) * 60 * frameRate  // minutes to frames
        + Int32(timecodeSample.seconds) * frameRate  // seconds to frames
        + Int32(timecodeSample.frames)  // frames
    print(
        "⏰ Calculated frame number: \(frameNumberData) for timecode \(String(format: "%02d:%02d:%02d:%02d", timecodeSample.hours, timecodeSample.minutes, timecodeSample.seconds, timecodeSample.frames))"
    )

    // Create block buffer for timecode data (64-bit big-endian signed integer)
    let blockBufferStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: MemoryLayout<Int32>.size,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: MemoryLayout<Int32>.size,
        flags: kCMBlockBufferAssureMemoryNowFlag,
        blockBufferOut: &dataBuffer
    )

    guard blockBufferStatus == kCMBlockBufferNoErr, let dataBuffer = dataBuffer else {
        print("❌ Could not create block buffer")
        return nil
    }

    // Write frame number data to block buffer (32-bit big-endian signed integer)
    // Convert to big-endian format as required by Core Media
    var bigEndianFrameNumber = frameNumberData.bigEndian
    let replaceStatus = CMBlockBufferReplaceDataBytes(
        with: &bigEndianFrameNumber,
        blockBuffer: dataBuffer,
        offsetIntoDestination: 0,
        dataLength: MemoryLayout<Int32>.size
    )

    guard replaceStatus == kCMBlockBufferNoErr else {
        print("❌ Could not write into block buffer")
        return nil
    }

    // Create timing info for timecode sample (following Apple's example)
    // Duration of each timecode sample is from the current frame to the next frame specified along with a timecode
    // In this case the single sample will last the entire duration of the video content
    var timingInfo = CMSampleTimingInfo()
    timingInfo.duration = CMTime(seconds: duration, preferredTimescale: frameRate)
    timingInfo.decodeTimeStamp = CMTime.invalid
    timingInfo.presentationTimeStamp = .zero

    // Create sample buffer with timecode data
    // numSamples: Number of samples in the CMSampleBuffer (1 for single timecode entry)
    // numSampleTimingEntries: Number of entries in sampleTimingArray (1 for single timing)
    // numSampleSizeEntries: Number of entries in sampleSizeArray (1 for single size)
    var sizes = MemoryLayout<Int32>.size
    let sampleBufferStatus = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: dataBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDescription,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timingInfo,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sizes,
        sampleBufferOut: &sampleBuffer
    )

    guard sampleBufferStatus == noErr, let sampleBuffer = sampleBuffer else {
        print("❌ Could not create sample buffer, status: \(sampleBufferStatus)")
        return nil
    }
    print("✅ Sample buffer created successfully")

    return sampleBuffer
}
