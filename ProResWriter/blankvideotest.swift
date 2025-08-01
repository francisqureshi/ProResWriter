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

// Error handling
enum BlankVideoError: Error {
    case noVideoTrack
    case invalidSourceFile
}

func blankvideo() async {
    do {
        print("🎬 Creating blank video from source clip...")

        // Performance timers
        let totalStartTime = CFAbsoluteTimeGetCurrent()

        // Source clip path (update this to your base clip)
        let sourceClipURL = URL(
            fileURLWithPath:
                "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRiush/COS AW25_4K_4444_24FPS_LR001_LOG.mov"
        )

        print("📹 Analyzing source clip: \(sourceClipURL.lastPathComponent)")

        // Load and analyze source clip
        let sourceAsset = AVURLAsset(url: sourceClipURL)
        let sourceVideoTrack = try await getVideoTrack(from: sourceAsset)
        let sourceProperties = try await getVideoProperties(from: sourceVideoTrack)
        let sourceDuration = try await sourceAsset.load(.duration)

        print(
            "✅ Source clip properties: \(sourceProperties.width)x\(sourceProperties.height) @ \(sourceProperties.frameRate)fps"
        )
        print("📹 Source duration: \(sourceDuration.seconds)s")
        if let sourceTimecode = sourceProperties.sourceTimecode {
            print("⏰ Source timecode: \(sourceTimecode)")
        }

        // Use source properties for blank video
        let width = sourceProperties.width
        let height = sourceProperties.height
        let frameRate = sourceProperties.frameRate
        let duration = sourceDuration.seconds

        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let outputURL = documentsPath.appendingPathComponent(
            "blank_copy_\(sourceClipURL.deletingPathExtension().lastPathComponent).mov")

        print(
            "📹 Creating blank copy: \(width)x\(height) @ \(frameRate)fps for \(String(format: "%.2f", duration))s"
        )
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

        // Use ProRes settings matching source color properties
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: sourceProperties.colorPrimaries,
                AVVideoTransferFunctionKey: sourceProperties.transferFunction,
                AVVideoYCbCrMatrixKey: sourceProperties.yCbCrMatrix,
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
                withTrackOf: timecodeWriterInput,
                type: AVAssetTrack.AssociationType.timecode.rawValue)
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

        // Copy existing timecode track from source asset (if available)
        if assetWriter.inputs.contains(timecodeWriterInput) {
            print("⏰ Looking for existing timecode track in source asset...")

            // Check if source asset has timecode tracks
            let sourceTimecodeTracks = try await sourceAsset.loadTracks(withMediaType: .timecode)
            print("🔍 Source asset has \(sourceTimecodeTracks.count) timecode tracks")

            if let sourceTimecodeTrack = sourceTimecodeTracks.first {
                print("✅ Found existing timecode track in source asset - copying samples...")

                // Get all sample buffers from the source timecode track
                let reader = try AVAssetReader(asset: sourceAsset)
                let readerOutput = AVAssetReaderTrackOutput(
                    track: sourceTimecodeTrack, outputSettings: nil)
                reader.add(readerOutput)
                reader.startReading()

                while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                    // Wait for writer to be ready
                    var timecodeWaitCount = 0
                    var writerReady = false

                    while !timecodeWriterInput.isReadyForMoreMediaData && timecodeWaitCount < 1000 {
                        try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                        timecodeWaitCount += 1
                    }

                    writerReady = timecodeWriterInput.isReadyForMoreMediaData

                    if !writerReady {
                        print("❌ Timeout waiting for timecode writer to be ready")
                        break
                    }

                    // Append the sample buffer only if writer is ready
                    if !timecodeWriterInput.append(sampleBuffer) {
                        print("❌ Failed to append timecode sample")
                        break
                    }
                }

                print("✅ Timecode track copied from source asset")
            } else {
                print("⚠️ No existing timecode track found in source asset - skipping timecode")
            }

            timecodeWriterInput.markAsFinished()
            print("✅ Timecode track finished")
        }

        // Calculate frame duration
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        let totalFrames = Int(duration * Double(frameRate))

        print("📊 Generating \(totalFrames) frames with burnt-in timecode...")

        // We'll create timecode pixel buffers dynamically for each frame
        let startTimecode = sourceProperties.sourceTimecode ?? "01:00:00:00"
        print("✅ Using start timecode: \(startTimecode)")

        // Generation timer
        let generationStartTime = CFAbsoluteTimeGetCurrent()

        // Generate frames with reliable readiness checking
        let batchSize = 50  // Process 50 frames at a time
        var frameIndex = 0

        print("🎬 Starting frame generation...")
        print("📹 Frame Generation Progress:")

        // Use concurrent tasks for frame generation and progress monitoring
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Generate frames
            group.addTask {
                while frameIndex < totalFrames {
                    // Process a batch of frames
                    let endIndex = min(frameIndex + batchSize, totalFrames)

                    for i in frameIndex..<endIndex {
                        // Wait for writer to be ready with timeout
                        var waitCount = 0
                        while !videoWriterInput.isReadyForMoreMediaData {
                            try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                            waitCount += 1
                            if waitCount > 1000 {  // 1 second timeout
                                print("❌ Timeout waiting for video writer to be ready")
                                return
                            }
                        }

                        // Calculate presentation time
                        let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))

                        // Calculate timecode for this frame
                        let frameTimecode = calculateTimecodeForFrame(
                            i, startTimecode: startTimecode, frameRate: frameRate)

                        // Create pixel buffer with burnt-in timecode
                        guard
                            let timecodePixelBuffer = createTimecodePixelBuffer(
                                width: width,
                                height: height,
                                timecode: frameTimecode
                            )
                        else {
                            print("❌ Failed to create timecode pixel buffer for frame \(i)")
                            return
                        }

                        // Append the timecode frame
                        let success = pixelBufferAdaptor.append(
                            timecodePixelBuffer, withPresentationTime: presentationTime)
                        if !success {
                            print("❌ Failed to append frame \(i)")
                            return
                        }
                    }

                    frameIndex = endIndex
                }
            }

            // Task 2: Monitor progress with animated progress bar and FPS counter
            group.addTask {
                var lastFrameCount = 0
                var lastTime = generationStartTime
                var displayFPS = 0.0
                var updateCounter = 0

                while !Task.isCancelled && frameIndex < totalFrames {
                    let currentTime = CFAbsoluteTimeGetCurrent()
                    let progress = Double(frameIndex) / Double(totalFrames)
                    let percentage = Int(progress * 100)
                    let progressBar = String(repeating: "█", count: percentage / 2)
                    let emptyBar = String(repeating: "░", count: 50 - (percentage / 2))

                    // Calculate FPS every 5 updates (500ms) for smoother display
                    updateCounter += 1
                    if updateCounter >= 5 {
                        let timeDelta = currentTime - lastTime
                        let framesDelta = frameIndex - lastFrameCount

                        if timeDelta > 0 && framesDelta > 0 {
                            displayFPS = Double(framesDelta) / timeDelta
                        }

                        // Reset for next calculation
                        lastFrameCount = frameIndex
                        lastTime = currentTime
                        updateCounter = 0
                    }

                    print(
                        "\r📹 [\(progressBar)\(emptyBar)] \(percentage)% (\(frameIndex)/\(totalFrames) frames) | \(String(format: "%.0f", displayFPS)) fps",
                        terminator: "")
                    fflush(stdout)

                    // Break if generation is complete
                    if frameIndex >= totalFrames {
                        break
                    }

                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                }
            }

            // Wait for frame generation to complete first, then cancel progress monitoring
            await group.next()
            group.cancelAll()
        }

        print("")  // New line after progress bar

        let generationEndTime = CFAbsoluteTimeGetCurrent()
        let generationTime = generationEndTime - generationStartTime
        print("📊 Frame generation time: \(String(format: "%.2f", generationTime))s")

        // Timecode sample already added before video generation

        // Finish writing and wait for completion
        videoWriterInput.markAsFinished()

        // Export timer
        let exportStartTime = CFAbsoluteTimeGetCurrent()

        // Finish writing and wait for completion (async)
        await withCheckedContinuation { continuation in
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
                        try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size]
                        as? Int64
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

                continuation.resume()
            }
        }
        print("🎬 Blank video creation process finished!")

    } catch {
        print("❌ Error creating blank video: \(error.localizedDescription)")
    }
}

// Cache for loaded fonts to avoid repeated loading
private var loadedFonts: [CGFloat: CTFont] = [:]

// Helper function to load Fira Code font from app bundle
private func loadFiraCodeFont(size: CGFloat) -> CTFont {
    // Return cached font if already loaded
    if let cachedFont = loadedFonts[size] {
        return cachedFont
    }

    // Try to load from bundle
    if let fontPath = Bundle.main.path(
        forResource: "FiraCodeNerdFont-Regular", ofType: "ttf", inDirectory: "Fonts"),
        let fontData = NSData(contentsOfFile: fontPath),
        let dataProvider = CGDataProvider(data: fontData),
        let cgFont = CGFont(dataProvider)
    {

        // Register the font (only once)
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(cgFont, &error)

        // Create CTFont from registered font
        if let fontName = cgFont.postScriptName {
            let font = CTFontCreateWithName(fontName, size, nil)
            loadedFonts[size] = font

            // // Only print success message once
            // if loadedFonts.count == 1 {
            //     print("✅ Fira Code Nerd Font loaded successfully")
            // }
            return font
        }
    }

    // Fallback to Monaco
    let font = CTFontCreateWithName("Monaco" as CFString, size, nil)
    loadedFonts[size] = font

    // Only print fallback message once
    if loadedFonts.count == 1 {
        print("⚠️ Using Monaco fallback font")
    }
    return font
}

// Helper function to create a pixel buffer with burnt-in timecode
private func createTimecodePixelBuffer(width: Int, height: Int, timecode: String) -> CVPixelBuffer?
{
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
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

        // Create CGContext for drawing
        guard
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }

        // Fill with black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw timecode text
        let fontSize = CGFloat(width) / 25.0  // Scale font size based on resolution
        let font = loadFiraCodeFont(size: fontSize)

        // Create attributed string for timecode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),  // White text
        ]
        let attributedString = NSAttributedString(string: timecode, attributes: attributes)

        // Calculate text position (bottom-right corner with padding)
        let line = CTLineCreateWithAttributedString(attributedString)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let padding = fontSize * 0.5
        let x = CGFloat(width) - textBounds.width - padding
        let y = padding

        // Draw the text
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)

        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    return nil
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
                pixelData[pixelIndex] = 79  // B
                pixelData[pixelIndex + 1] = 17  // G
                pixelData[pixelIndex + 2] = 38  // R
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

// Helper function to calculate timecode for a specific frame
private func calculateTimecodeForFrame(_ frameNumber: Int, startTimecode: String, frameRate: Int32)
    -> String
{
    // Parse the start timecode
    let components = startTimecode.components(separatedBy: ":")
    guard components.count == 4,
        let startHours = Int(components[0]),
        let startMinutes = Int(components[1]),
        let startSeconds = Int(components[2]),
        let startFrames = Int(components[3])
    else {
        return "00:00:00:00"
    }

    // Convert start timecode to total frames
    let startTotalFrames =
        startHours * 3600 * Int(frameRate) + startMinutes * 60 * Int(frameRate) + startSeconds
        * Int(frameRate) + startFrames

    // Add current frame number
    let currentTotalFrames = startTotalFrames + frameNumber

    // Convert back to timecode
    let hours = currentTotalFrames / (3600 * Int(frameRate))
    let remainingAfterHours = currentTotalFrames % (3600 * Int(frameRate))
    let minutes = remainingAfterHours / (60 * Int(frameRate))
    let remainingAfterMinutes = remainingAfterHours % (60 * Int(frameRate))
    let seconds = remainingAfterMinutes / Int(frameRate)
    let frames = remainingAfterMinutes % Int(frameRate)

    return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
}

// Helper functions for video analysis
private func getVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = tracks.first else {
        throw BlankVideoError.noVideoTrack
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
        if let extensionsDict = extensions as? [String: Any] {
            if let colorProps = extensionsDict[
                kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
            {
                colorPrimaries = colorProps
            }
            if let transferProps = extensionsDict[
                kCMFormatDescriptionExtension_TransferFunction as String] as? String
            {
                transferFunction = transferProps
            }
            if let matrixProps = extensionsDict[kCMFormatDescriptionExtension_YCbCrMatrix as String]
                as? String
            {
                yCbCrMatrix = matrixProps
            }
        }
    }

    // Extract timecode using TimecodeKit
    var sourceTimecode: String? = nil
    do {
        let asset = track.asset!
        print("🔍 Extracting timecode using TimecodeKit...")

        // Get frame rate first for TimecodeKit
        let detectedFrameRate = try await asset.timecodeFrameRate()
        print("    📹 Auto-detected frame rate: \(detectedFrameRate)")

        // Extract start timecode
        if let startTimecode = try await asset.startTimecode() {
            sourceTimecode = startTimecode.stringValue()
            print("    ✅ Found start timecode: \(sourceTimecode!)")
        } else {
            print("    ⚠️ No start timecode found")
        }

    } catch {
        print("    ⚠️ Could not extract timecode: \(error.localizedDescription)")
        sourceTimecode = nil
    }

    return VideoProperties(
        width: Int(naturalSize.width),
        height: Int(naturalSize.height),
        frameRate: Int32(nominalFrameRate),
        colorPrimaries: colorPrimaries,
        transferFunction: transferFunction,
        yCbCrMatrix: yCbCrMatrix,
        sourceTimecode: sourceTimecode
    )
}
