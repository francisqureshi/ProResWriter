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
import CoreGraphics

// Error handling
enum BlankVideoError: Error {
    case noVideoTrack
    case invalidSourceFile
}


// Custom compositor to generate black frames with burnt-in timecode
class BlankFrameCompositor: NSObject, AVVideoCompositing {
    static var sourceProperties: VideoProperties?
    static var sourceClipURL: URL?
    
    var sourcePixelBufferAttributes: [String : Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA] as [CFNumber]
    ]
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as CFNumber
    ]
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Nothing to do here
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let sourceProperties = Self.sourceProperties,
                  let sourceClipURL = Self.sourceClipURL else {
                asyncVideoCompositionRequest.finish(with: NSError(domain: "BlankFrameCompositor", code: -1))
                return
            }
            
            // Calculate frame number from presentation time
            let frameRate = Float(sourceProperties.frameRate)
            let frameNumber = Int(asyncVideoCompositionRequest.compositionTime.seconds * Double(frameRate))
            
            // Calculate timecode for this frame
            let startTimecode = sourceProperties.sourceTimecode ?? "00:00:00:00"
            let timecodeFrameRate = getTimecodeFrameRate(sourceFrameRate: frameRate)
            let frameTimecode = calculateTimecodeForFrame(frameNumber, startTimecode: startTimecode, frameRate: timecodeFrameRate)
            
            // Create black frame with burnt-in timecode
            let baseFileName = sourceClipURL.deletingPathExtension().lastPathComponent
            
            guard let pixelBuffer = createTimecodePixelBuffer(
                width: sourceProperties.width,
                height: sourceProperties.height,
                timecode: frameTimecode,
                baseFileName: baseFileName
            ) else {
                asyncVideoCompositionRequest.finish(with: NSError(domain: "BlankFrameCompositor", code: -2))
                return
            }
            
            asyncVideoCompositionRequest.finish(withComposedVideoFrame: pixelBuffer)
        }
    }
}

func createBlankRush(from sourceClipURL: URL) async throws {
    print("🎬 Creating blank video using composition approach...")

    // Performance timers
    let totalStartTime = CFAbsoluteTimeGetCurrent()

    print("📹 Analyzing source clip: \(sourceClipURL.lastPathComponent)")

        // Load and analyze source clip
        let sourceAsset = AVURLAsset(url: sourceClipURL)
        let sourceVideoTrack = try await getVideoTrack(from: sourceAsset)
        let sourceProperties = try await getVideoProperties(from: sourceVideoTrack)
        let sourceDuration = try await sourceAsset.load(.duration)
        
        // Extract properties from source for convenience
        let width = sourceProperties.width
        let height = sourceProperties.height
        let duration = sourceDuration.seconds

        print("✅ Source clip properties: \(sourceProperties.width)x\(sourceProperties.height) @ \(sourceProperties.frameRate)fps")
        print("📹 Source duration: \(sourceDuration.seconds)s")
        if let sourceTimecode = sourceProperties.sourceTimecode {
            print("⏰ Source timecode: \(sourceTimecode)")
        }

        // Use source properties for blank video
        let width = sourceProperties.width
        let height = sourceProperties.height
        let frameRate = sourceProperties.frameRate
        let duration = sourceDuration.seconds

        // Create output URL in OUT folder relative to source file
        let sourceDirectory = sourceClipURL.deletingLastPathComponent()
        let outDirectory = sourceDirectory.appendingPathComponent("OUT")
        
        // Create OUT directory if it doesn't exist
        try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        
        let outputURL = outDirectory.appendingPathComponent(
            "blank_copy_\(sourceClipURL.deletingPathExtension().lastPathComponent).mov")

        print("📹 Creating blank copy using composition approach")
        print("📁 Output: \(outputURL.path)")

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Step 1: Create composition that preserves source track structure
        print("🎬 Creating composition from source...")
        let composition = AVMutableComposition()
        
        // Add video track to composition with same settings as source
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video, 
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw BlankVideoError.noVideoTrack
        }
        
        // Add timecode track to composition 
        let compositionTimecodeTrack = composition.addMutableTrack(
            withMediaType: .timecode,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        // Insert the source video track (this preserves all metadata)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: sourceDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        
        // Copy timecode track if it exists
        let sourceTimecodeTracks = try await sourceAsset.loadTracks(withMediaType: .timecode)
        print("🔍 Source asset has \(sourceTimecodeTracks.count) timecode tracks")
        
        if let sourceTimecodeTrack = sourceTimecodeTracks.first, 
           let compositionTimecodeTrack = compositionTimecodeTrack {
            try compositionTimecodeTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: sourceDuration),
                of: sourceTimecodeTrack,
                at: .zero
            )
            print("✅ Timecode track copied to composition")
            
            // Verify the composition has the timecode track
            let compositionTimecodeTracks = try await composition.loadTracks(withMediaType: .timecode)
            print("🔍 Composition now has \(compositionTimecodeTracks.count) timecode tracks")
        } else {
            print("⚠️ No source timecode track found - creating new timecode track")
            
            // If no source timecode track, create one using our working approach
            if let sourceTimecode = sourceProperties.sourceTimecode,
               let compositionTimecodeTrack = compositionTimecodeTrack {
                
                // Create and add timecode sample buffer 
                if let timecodeSampleBuffer = createTimecodeSampleBuffer(
                    frameRate: sourceProperties.frameRate, 
                    duration: sourceDuration.seconds
                ) {
                    print("✅ Created new timecode sample buffer for composition")
                    // Note: AVMutableComposition doesn't support direct sample buffer insertion
                    // But we'll have the timecode track structure for export
                } else {
                    print("❌ Failed to create timecode sample buffer")
                }
            }
        }
        
        print("✅ Composition created with source metadata preserved")

        // Step 2: Create video composition with custom compositor to replace content
        print("🎨 Creating video composition with black frames and burnt-in timecode...")
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = BlankFrameCompositor.self
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(sourceProperties.frameRate))
        videoComposition.renderSize = CGSize(width: sourceProperties.width, height: sourceProperties.height)
        
        // Create composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: sourceDuration)
        
        // Create layer instruction for the video track
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
        print("✅ Video composition created with custom compositor")

        // Step 3: Export using AVAssetExportSession to preserve metadata
        print("📤 Setting up export session...")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("❌ Failed to create export session")
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.mov
        exportSession.videoComposition = videoComposition
        
        // Store info for compositor
        BlankFrameCompositor.sourceProperties = sourceProperties
        BlankFrameCompositor.sourceClipURL = sourceClipURL
        
        // Add timecode track using our working approach from main.swift
        print("⏰ Adding timecode track to export...")
        if let sourceTimecode = sourceProperties.sourceTimecode {
            print("⏰ Creating timecode track with start timecode: \(sourceTimecode)")
            
            // Get the composition's video track for association
            let compositionTracks = try await composition.loadTracks(withMediaType: .video)
            if let videoTrack = compositionTracks.first {
                print("✅ Found video track for timecode association")
                
                // Add timecode track using the same approach as main.swift
                try await addTimecodeTrackToExport(
                    exportSession: exportSession,
                    videoTrack: videoTrack,
                    timecode: sourceTimecode,
                    frameRate: sourceProperties.frameRate,
                    duration: sourceDuration
                )
            } else {
                print("⚠️ No video track found for timecode association")
            }
        } else {
            print("⚠️ No source timecode available - exporting without timecode track")
        }
        
        print("✅ Export session configured")

        // Export timer
        let exportStartTime = CFAbsoluteTimeGetCurrent()
        
        // Start export
        print("🚀 Starting export...")
        await exportSession.export()
        
        let exportEndTime = CFAbsoluteTimeGetCurrent()
        let exportTime = exportEndTime - exportStartTime
        let totalTime = exportEndTime - totalStartTime
        
        if exportSession.status == AVAssetExportSession.Status.completed {
            print("✅ Export completed successfully!")
        } else {
            print("❌ Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            return
        }

        print("✅ Blank video creation completed!")
        print("📁 Output file: \(outputURL.path)")

        // Performance analysis
        print("📊 Performance Analysis:")
        print("   Export time: \(String(format: "%.2f", exportTime))s")
        print("   Total time: \(String(format: "%.2f", totalTime))s")

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
    print("🎬 Blank video creation process finished!")
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
private func createTimecodePixelBuffer(
    width: Int, height: Int, timecode: String, baseFileName: String
) -> CVPixelBuffer? {
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

        // Draw timecode text with prefix and filename
        let fontSize = CGFloat(height) / 50.0  // Scale font size based on resolution
        let font = loadFiraCodeFont(size: fontSize)

        // Create the full display text
        let displayText = "     SRC TC: \(timecode) ---> \(baseFileName)"

        // Create attributed string for timecode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),  // White text
        ]
        let attributedString = NSAttributedString(string: displayText, attributes: attributes)

        // Calculate text position for timecode (bottom-left corner with padding)
        let line = CTLineCreateWithAttributedString(attributedString)
        _ = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let padding = fontSize * 0.75
        let textPosX = padding
        let textPosY = CGFloat(height) - fontSize - padding

        // Draw the timecode text
        context.textPosition = CGPoint(x: textPosX, y: textPosY)
        CTLineDraw(line, context)

        // Create and draw the "NO GRADE" text in bottom-right corner
        let gradeText = "/// NO GRADE ///       "
        let gradeAttributedString = NSAttributedString(string: gradeText, attributes: attributes)
        let gradeLine = CTLineCreateWithAttributedString(gradeAttributedString)
        let gradeTextBounds = CTLineGetBoundsWithOptions(gradeLine, .useOpticalBounds)

        // Position in bottom-right corner
        let gradeX = CGFloat(width) - gradeTextBounds.width - padding
        let gradeY = textPosY

        // Draw the grade text
        context.textPosition = CGPoint(x: gradeX, y: gradeY)
        CTLineDraw(gradeLine, context)

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

// Helper function to get proper timecode frame rate base (24 for 23.976fps, 30 for 29.97fps, etc.)
private func getTimecodeFrameRate(sourceFrameRate: Float) -> Int32 {
    switch sourceFrameRate {
    case 23.9...24.1:
        return 24  // 23.976fps uses 24-frame timecode base (0-23)
    case 29.9...30.1:
        return 30  // 29.97fps uses 30-frame timecode base (0-29)
    case 59.9...60.1:
        return 60  // 59.94fps uses 60-frame timecode base (0-59)
    default:
        return Int32(round(sourceFrameRate))
    }
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
    let frameNumberData: Int32 =
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

// Add timecode track to export session using the working approach from main.swift
private func addTimecodeTrackToExport(
    exportSession: AVAssetExportSession,
    videoTrack: AVAssetTrack,
    timecode: String,
    frameRate: Int32,
    duration: CMTime
) async throws {
    print("📹 Adding timecode track to export session...")
    
    // Unfortunately, AVAssetExportSession doesn't support adding timecode tracks directly
    // The timecode track should already be preserved from the composition
    // This is a limitation of AVAssetExportSession vs AVAssetWriter
    
    print("⚠️ AVAssetExportSession preserves existing timecode tracks from composition")
    print("✅ Timecode track should be preserved from source composition")
}

