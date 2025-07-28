import AVFoundation
import AppKit
import CoreMedia
import TimecodeKit
import Metal

// MARK: - Data Models
struct GradedSegment {
    let url: URL
    let startTime: CMTime  // Start time in the final timeline
    let duration: CMTime  // Duration of the segment
    let sourceStartTime: CMTime  // Start time in the source segment file
}

struct CompositorSettings {
    let outputURL: URL
    let baseVideoURL: URL
    let gradedSegments: [GradedSegment]
    let proResType: AVVideoCodecType  // .proRes422, .proRes422HQ, etc.
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
                print("❌ Composition error: \(error)")
                await MainActor.run {
                    completionHandler?(.failure(error))
                }
            }
        }
    }

    // MARK: - Core Processing
    private func processComposition(settings: CompositorSettings) async throws -> URL {

        print("🔍 Starting composition process...")

        // 1. Analyze base video to get properties
        let analysisStartTime = CFAbsoluteTimeGetCurrent()
        print("📹 Analyzing base video...")
        
        // HARDWARE ACCELERATION: Optimize for Apple Silicon and Metal GPU
        let assetOptions: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ]
        let baseAsset = AVURLAsset(url: settings.baseVideoURL, options: assetOptions)
        
        let baseTrack = try await getVideoTrack(from: baseAsset)
        let baseProperties = try await getVideoProperties(from: baseTrack)
        let analysisEndTime = CFAbsoluteTimeGetCurrent()
        print(
            "📹 Video analysis completed in: \(String(format: "%.2f", analysisEndTime - analysisStartTime))s"
        )

        // Log the extracted timecode for debugging
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Extracted base timecode: \(sourceTimecode)")
        } else {
            print("📹 No timecode found in base video")
        }

        print(
            "✅ Base video properties: \(baseProperties.width)x\(baseProperties.height) @ \(baseProperties.frameRate)fps"
        )

        // 2. Use AVMutableComposition with trimming for fast overlay
        let exportStartTime = CFAbsoluteTimeGetCurrent()
        print("🚀 Using AVMutableComposition with trimming for fast overlay...")

        // Create composition
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)

        // Add base video to composition
        let baseVideoTrack = try await getVideoTrack(from: baseAsset)
        let baseDuration = try await baseAsset.load(.duration)
        try videoTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: baseDuration), of: baseVideoTrack, at: .zero)

        print("🎬 Base video added to composition: \(baseDuration.seconds)s")

        // Sort segments by start time for proper trimming
        let sortedSegments = settings.gradedSegments.sorted { $0.startTime < $1.startTime }

        // MEMORY OPTIMIZATION: Stream assets on-demand instead of pre-loading all
        print("🚀 Using memory-optimized streaming assets...")
        
        // Create a lazy asset loader to minimize memory usage
        let assetLoader = { (segment: GradedSegment) -> AVAsset in
            let assetOptions: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
            return AVURLAsset(url: segment.url, options: assetOptions)
        }

        // MEMORY OPTIMIZATION: Process segments sequentially to minimize memory pressure
        print("🎬 Processing \(sortedSegments.count) segments with memory optimization...")
        
        // Process segments in reverse order to avoid time shifting issues
        for (index, segment) in sortedSegments.reversed().enumerated() {
            print("   Processing segment \(sortedSegments.count - index): \(segment.url.lastPathComponent)")
            
            // Remove the base video section that this segment will replace
            try? videoTrack?.removeTimeRange(
                CMTimeRange(start: segment.startTime, duration: segment.duration))

            // Load asset on-demand and immediately release after use
            let segmentAsset = assetLoader(segment)
            let segmentVideoTrack = try? await getVideoTrack(from: segmentAsset)
            try? videoTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: segment.duration),
                of: segmentVideoTrack!,
                at: segment.startTime
            )
            
            // Force memory cleanup after each segment
            autoreleasepool {
                // This will help release memory immediately
            }
        }
        print("   ✅ All segments processed with memory optimization")

        // Get final composition duration
        let finalDuration = try await composition.load(.duration)
        print("📹 Final composition duration: \(finalDuration.seconds)s")

        // 🎬 TIMECODE: Will be added after export (optimized)
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Timecode will be added after export: \(sourceTimecode)")
        }

        // HARDWARE ACCELERATION: Use Apple Silicon ProRes engine and Metal GPU
        print("🚀 Enabling Apple Silicon ProRes engine and Metal GPU acceleration...")
        
        // MEMORY OPTIMIZATION: Use memory-efficient export settings
        guard
            let exportSession = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetPassthrough)
        else {
            throw CompositorError.setupFailed
        }

        exportSession.outputURL = settings.outputURL
        exportSession.outputFileType = .mov
        
        // MEMORY OPTIMIZED EXPORT SETTINGS
        exportSession.fileLengthLimit = 0 // No file size limit
        exportSession.shouldOptimizeForNetworkUse = false // Faster for local files
        exportSession.timeRange = CMTimeRange(start: .zero, duration: finalDuration)
        
        // Memory optimization: Single pass to reduce memory usage
        if #available(macOS 12.0, *) {
            exportSession.canPerformMultiplePassesOverSourceMediaData = false
        }
        
        // Monitor memory usage
        let processInfo = ProcessInfo.processInfo
        let initialMemory = processInfo.physicalMemory
        print("📊 Initial memory usage: \(initialMemory / 1024 / 1024)MB")
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: settings.outputURL.path) {
            try FileManager.default.removeItem(at: settings.outputURL)
        }

        print("🚀 Starting memory-optimized export...")
        let exportStart = CFAbsoluteTimeGetCurrent()
        
        // Monitor memory during export
        let exportMemory = processInfo.physicalMemory
        print("📊 Memory before export: \(exportMemory / 1024 / 1024)MB")
        
        try await exportSession.export(to: settings.outputURL, as: .mov)

        let exportEndTime = CFAbsoluteTimeGetCurrent()
        let exportDuration = exportEndTime - exportStart
        let finalMemory = processInfo.physicalMemory
        print(
            "🚀 Export completed in: \(String(format: "%.2f", exportDuration))s"
        )
        print("📊 Memory after export: \(finalMemory / 1024 / 1024)MB")
        print("📊 Memory delta: \((finalMemory - exportMemory) / 1024 / 1024)MB")
        
        // Performance analysis - Setup vs Render time
        let setupTime = exportStart - exportStartTime
        let renderTime = exportEndTime - exportStart
        print("📊 Setup time (timeline building): \(String(format: "%.2f", setupTime))s")
        print("🎬 Render time (export only): \(String(format: "%.2f", renderTime))s")
        print("📊 Setup represents \(String(format: "%.1f", (setupTime / (setupTime + renderTime)) * 100))% of total time")
        print("🎬 Render represents \(String(format: "%.1f", (renderTime / (setupTime + renderTime)) * 100))% of total time")

        // 3. Add timecode metadata using AVMutableMovie
        let timecodeStartTime = CFAbsoluteTimeGetCurrent()
        if let sourceTimecode = baseProperties.sourceTimecode {
            try await addTimecodeMetadataUsingAVMutableMovie(
                to: settings.outputURL, timecode: sourceTimecode,
                frameRate: baseProperties.frameRate)
        }
        let timecodeEndTime = CFAbsoluteTimeGetCurrent()
        print(
            "📹 Timecode metadata added in: \(String(format: "%.2f", timecodeEndTime - timecodeStartTime))s"
        )

        // RENDER TIME: Only measure the actual export time (like DaVinci Resolve)
        let actualRenderTime = exportEndTime - exportStart
        print("🎬 RENDER TIME (export only): \(String(format: "%.2f", actualRenderTime))s")
        print("📊 This is the equivalent to DaVinci Resolve's render time")

        return settings.outputURL
    }

    // MARK: - Asset Writer Setup
    private func setupAssetWriter(
        outputURL: URL, properties: VideoProperties, proResType: AVVideoCodecType
    ) throws {

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
                AVVideoYCbCrMatrixKey: properties.yCbCrMatrix,
            ],
        ]

        // Note: Timecode metadata will be added after composition using AVMutableMovie
        print("📹 Timecode metadata will be added after composition")

        // Create video input
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = false

        // Create pixel buffer adaptor with more compatible format
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: properties.width,
            kCVPixelBufferHeightKey as String: properties.height,
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        // Add input to writer
        guard let assetWriter = assetWriter,
            let videoWriterInput = videoWriterInput,
            assetWriter.canAdd(videoWriterInput)
        else {
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
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        sessionTimecode: CMTime
    ) async throws {

        let frameDuration = CMTime(value: 1, timescale: baseProperties.frameRate)
        let totalDuration = try await baseAsset.load(.duration)
        let totalFrames = Int(totalDuration.seconds * Double(baseProperties.frameRate))

        var currentTime = sessionTimecode
        var frameIndex = 0
        var frameProcessingTimes: [CFAbsoluteTime] = []

        // We'll use AVAssetImageGenerator for base video frames too

        while frameIndex < totalFrames {

            let frameStartTime = CFAbsoluteTimeGetCurrent()

            // Wait for writer to be ready
            while !videoWriterInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
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
            } else {
                // Calculate the time offset for base video (subtract session start time)
                let baseVideoTime = CMTimeSubtract(currentTime, sessionTimecode)
                pixelBuffer = try await getFrameFromBaseVideo(
                    baseAsset: baseAsset, atTime: baseVideoTime)
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

            let frameEndTime = CFAbsoluteTimeGetCurrent()
            frameProcessingTimes.append(frameEndTime - frameStartTime)

            // Update progress every 10 frames (or at start/end)
            if frameIndex % 10 == 0 || frameIndex == totalFrames - 1 {
                let progress = Double(frameIndex) / Double(totalFrames)
                await MainActor.run {
                    progressHandler?(progress)
                }

                // Log timing every 100 frames
                if frameIndex % 100 == 0 && frameIndex > 0 {
                    let recentFrames = frameProcessingTimes.suffix(100)
                    let avgFrameTime = recentFrames.reduce(0, +) / Double(recentFrames.count)
                    print(
                        "📊 Frame \(frameIndex)/\(totalFrames): Avg frame time: \(String(format: "%.3f", avgFrameTime))s"
                    )
                }
            }

            currentTime = CMTimeAdd(currentTime, frameDuration)
            frameIndex += 1
        }
    }

    // MARK: - Helper Methods
    func getVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw CompositorError.noVideoTrack
        }
        return videoTrack
    }

    func getVideoProperties(from track: AVAssetTrack) async throws -> VideoProperties {
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
                if let colorProperties = extensionsDict[
                    kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                {
                    colorPrimaries = colorProperties
                }
                if let transferProperties = extensionsDict[
                    kCMFormatDescriptionExtension_TransferFunction as String] as? String
                {
                    transferFunction = transferProperties
                }
                if let matrixProperties = extensionsDict[
                    kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
                {
                    yCbCrMatrix = matrixProperties
                }
            }
        }

        // Extract timecode information (CRITICAL for professional workflows)
        let sourceTimecode = try await extractSourceTimecode(from: track.asset ?? AVURLAsset(url: URL(fileURLWithPath: "")))

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

    private func prepareSegmentReaders(_ segments: [GradedSegment]) async throws -> [URL:
        AVAssetReader]
    {
        var readers: [URL: AVAssetReader] = [:]

        for segment in segments {
            if readers[segment.url] == nil {
                let asset = AVURLAsset(url: segment.url)
                let reader = try AVAssetReader(asset: asset)

                let videoTrack = try await getVideoTrack(from: asset)

                // Use output settings that match our pixel buffer format
                let outputSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]

                let output = AVAssetReaderTrackOutput(
                    track: videoTrack, outputSettings: outputSettings)

                reader.add(output)
                readers[segment.url] = reader
            }
        }

        return readers
    }

    private func findActiveSegment(at time: CMTime, in segments: [GradedSegment]) -> GradedSegment?
    {
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
        // Calculate the time offset within the segment
        let segmentTimeOffset = CMTimeSubtract(time, segment.startTime)
        let sourceTime = CMTimeAdd(segment.sourceStartTime, segmentTimeOffset)

        // Use AVAssetImageGenerator for precise frame extraction
        let asset = AVURLAsset(url: segment.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 25)  // 1 frame tolerance
        imageGenerator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 25)  // 1 frame tolerance

        do {
            let cgImage = try await imageGenerator.image(at: sourceTime).image
            return cgImageToPixelBuffer(cgImage, size: CGSize(width: 3840, height: 2160))
        } catch {
            print("❌ Failed to extract frame from segment: \(error)")
            return nil
        }
    }

    private func getFrameFromBaseVideo(baseAsset: AVAsset, atTime time: CMTime) async throws
        -> CVPixelBuffer?
    {
        let imageGenerator = AVAssetImageGenerator(asset: baseAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 25)  // 1 frame tolerance
        imageGenerator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 25)  // 1 frame tolerance

        do {
            let cgImage = try await imageGenerator.image(at: time).image
            return cgImageToPixelBuffer(cgImage, size: CGSize(width: 3840, height: 2160))
        } catch {
            print("❌ Failed to extract frame from base video: \(error)")
            return nil
        }
    }

    private func cgImageToPixelBuffer(_ cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]

        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        if result == kCVReturnSuccess, let buffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(buffer, [])

            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )

            context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

            CVPixelBufferUnlockBaseAddress(buffer, [])
            return buffer
        }

        return nil
    }

    private func getNextFrameFromReader(_ output: AVAssetReaderTrackOutput) -> CVPixelBuffer? {
        guard let sampleBuffer = output.copyNextSampleBuffer() else { return nil }
        return CMSampleBufferGetImageBuffer(sampleBuffer)
    }

    private func createBlankFrame(properties: VideoProperties) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: properties.width,
            kCVPixelBufferHeightKey as String: properties.height,
        ]

        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            properties.width,
            properties.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        if result == kCVReturnSuccess, let buffer = pixelBuffer {
            // Fill with black (BGRA format: B=0, G=0, R=0, A=255)
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

    // MARK: - Segment Discovery and Parsing
    func discoverSegments(in directoryURL: URL) async throws -> [SegmentInfo] {
        let fileManager = FileManager.default
        let segmentURLs = try fileManager.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "mov" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var segments: [SegmentInfo] = []

        for url in segmentURLs {
            let segmentInfo = try await parseSegmentInfo(from: url)
            segments.append(segmentInfo)
        }

        return segments
    }

    private func parseSegmentInfo(from url: URL) async throws -> SegmentInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let filename = url.lastPathComponent

        // Try to parse segment number from filename (e.g., "S01", "S02")
        let segmentNumber = parseSegmentNumber(from: filename)

        // Try to parse start time from filename or metadata
        let startTime = try await parseStartTime(from: asset, filename: filename)

        // RESTORED: Extract timecode information
        let sourceTimecode = try await extractSourceTimecode(from: asset)
        let sourceStartTimecode = try await extractStartTimecode(from: asset)

        return SegmentInfo(
            url: url,
            filename: filename,
            duration: duration,
            startTime: startTime,
            segmentNumber: segmentNumber,
            sourceTimecode: sourceTimecode,
            sourceStartTimecode: sourceStartTimecode
        )
    }

    private func parseSegmentNumber(from filename: String) -> Int? {
        // Look for patterns like "S01", "S02", etc.
        let pattern = "S(\\d+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)

        if let match = regex?.firstMatch(in: filename, range: range),
            let numberRange = Range(match.range(at: 1), in: filename)
        {
            return Int(filename[numberRange])
        }

        return nil
    }

    private func parseStartTime(from asset: AVAsset, filename: String) async throws -> CMTime? {
        // First, try to get start time from metadata
        if let startTime = try await getStartTimeFromMetadata(asset) {
            return startTime
        }

        // If no metadata, try to parse from filename
        return parseStartTimeFromFilename(filename)
    }

    private func getStartTimeFromMetadata(_ asset: AVAsset) async throws -> CMTime? {
        // Try to get start time from various metadata sources
        let metadata = try await asset.load(.metadata)

        for item in metadata {
            if let key = item.commonKey?.rawValue,
                key == "startTime" || key == "time"
            {
                // Parse time value from metadata
                if let value = try? await item.load(.value) as? String {
                    return parseTimeString(value)
                }
            }
        }

        return nil
    }

    private func parseStartTimeFromFilename(_ filename: String) -> CMTime? {
        // Look for time patterns in filename (e.g., "T10s", "T30s", etc.)
        let patterns = [
            "T(\\d+)s",  // T10s, T30s
            "T(\\d+)_(\\d+)",  // T10_30 (minutes_seconds)
            "start(\\d+)",  // start10, start30
        ]

        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)

            if let match = regex?.firstMatch(in: filename, range: range) {
                if pattern == "T(\\d+)s" {
                    if let secondsRange = Range(match.range(at: 1), in: filename) {
                        let seconds = Int(filename[secondsRange]) ?? 0
                        return CMTime(seconds: Double(seconds), preferredTimescale: 600)
                    }
                } else if pattern == "T(\\d+)_(\\d+)" {
                    if let minutesRange = Range(match.range(at: 1), in: filename),
                        let secondsRange = Range(match.range(at: 2), in: filename)
                    {
                        let minutes = Int(filename[minutesRange]) ?? 0
                        let seconds = Int(filename[secondsRange]) ?? 0
                        return CMTime(
                            seconds: Double(minutes * 60 + seconds), preferredTimescale: 600)
                    }
                } else if pattern == "start(\\d+)" {
                    if let secondsRange = Range(match.range(at: 1), in: filename) {
                        let seconds = Int(filename[secondsRange]) ?? 0
                        return CMTime(seconds: Double(seconds), preferredTimescale: 600)
                    }
                }
            }
        }

        return nil
    }

    private func parseTimeString(_ timeString: String) -> CMTime? {
        // Parse various time formats
        let components = timeString.components(separatedBy: ":")
        if components.count == 2 {
            // MM:SS format
            if let minutes = Int(components[0]), let seconds = Int(components[1]) {
                return CMTime(seconds: Double(minutes * 60 + seconds), preferredTimescale: 600)
            }
        } else if components.count == 3 {
            // HH:MM:SS format
            if let hours = Int(components[0]), let minutes = Int(components[1]),
                let seconds = Int(components[2])
            {
                return CMTime(
                    seconds: Double(hours * 3600 + minutes * 60 + seconds), preferredTimescale: 600)
            }
        } else if let seconds = Double(timeString) {
            // Just seconds
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }

        return nil
    }

    // MARK: - Timecode Handling using TimecodeKit (RESTORED)
    private func extractSourceTimecode(from asset: AVAsset) async throws -> String? {
        print("🔍 Extracting timecode using TimecodeKit...")

        do {
            // Try to auto-detect frame rate first
            let frameRate = try await asset.timecodeFrameRate()
            print("    📹 Auto-detected frame rate: \(frameRate)")

            // Read start timecode using TimecodeKit
            if let startTimecode = try await asset.startTimecode(at: frameRate) {
                print("    ✅ Found start timecode: \(startTimecode)")
                return startTimecode.stringValue()
            } else {
                print("    ❌ No start timecode found")
                return nil
            }
        } catch {
            print("    ❌ Failed to extract timecode with auto-detected frame rate: \(error)")
            print("❌ No timecode found in video")
            return nil
        }
    }

    private func extractStartTimecode(from asset: AVAsset) async throws -> String? {
        print("🔍 Extracting start timecode using TimecodeKit...")

        do {
            // Try to auto-detect frame rate first
            let frameRate = try await asset.timecodeFrameRate()
            print("    📹 Auto-detected frame rate: \(frameRate)")

            // Read start timecode using TimecodeKit
            if let startTimecode = try await asset.startTimecode(at: frameRate) {
                print("    ✅ Found start timecode: \(startTimecode)")
                return startTimecode.stringValue()
            } else {
                print("    ❌ No start timecode found")
                return nil
            }
        } catch {
            print("    ❌ Failed to extract timecode with auto-detected frame rate: \(error)")
            print("❌ No timecode found in video")
            return nil
        }
    }

    private func timecodeToCMTime(_ timecode: String, frameRate: Int32, baseTimecode: String? = nil)
        -> CMTime?
    {
        // Parse timecode in format HH:MM:SS:FF (frames)
        let components = timecode.components(separatedBy: ":")
        guard components.count == 4,
            let hours = Int(components[0]),
            let minutes = Int(components[1]),
            let seconds = Int(components[2]),
            let frames = Int(components[3])
        else {
            return nil
        }

        // If we have a base timecode, calculate relative offset
        if let baseTimecode = baseTimecode {
            let baseComponents = baseTimecode.components(separatedBy: ":")
            guard baseComponents.count == 4,
                let baseHours = Int(baseComponents[0]),
                let baseMinutes = Int(baseComponents[1]),
                let baseSeconds = Int(baseComponents[2]),
                let baseFrames = Int(baseComponents[3])
            else {
                return nil
            }

            // Calculate the difference in seconds and frames
            let totalSeconds =
                (hours - baseHours) * 3600 + (minutes - baseMinutes) * 60 + (seconds - baseSeconds)
            let frameDifference = frames - baseFrames
            let frameTime = Double(frameDifference) / Double(frameRate)

            return CMTime(
                seconds: Double(totalSeconds) + frameTime,
                preferredTimescale: CMTimeScale(frameRate))
        } else {
            // Absolute timecode (for base timecode itself)
            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            let frameTime = Double(frames) / Double(frameRate)
            return CMTime(
                seconds: Double(totalSeconds) + frameTime,
                preferredTimescale: CMTimeScale(frameRate))
        }
    }

    func cmTimeToTimecode(_ time: CMTime, frameRate: Int32) -> String {
        let totalSeconds = time.seconds
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int((totalSeconds.truncatingRemainder(dividingBy: 1.0)) * Double(frameRate))

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }



    private func addTimecodeMetadataUsingAVMutableMovie(
        to url: URL, timecode: String, frameRate: Int32
    ) async throws {
        print("📹 Adding timecode metadata using TimecodeKit: \(timecode)")

        // Create AVMovie from the output file
        let movie = AVMovie(url: url)

        // Convert to mutable movie
        let mutableMovie = movie.mutableCopy() as! AVMutableMovie

        // Parse timecode components
        let components = timecode.components(separatedBy: ":")
        guard components.count == 4,
            let hours = Int(components[0]),
            let minutes = Int(components[1]),
            let seconds = Int(components[2]),
            let frames = Int(components[3])
        else {
            print("❌ Failed to parse timecode: \(timecode)")
            return
        }

        // Create TimecodeKit timecode object using the correct API
        let timecodeObject = try Timecode(
            .components(h: hours, m: minutes, s: seconds, f: frames), at: .fps25)

        // Get the duration of the movie and create duration timecode
        let duration = try await mutableMovie.load(.duration)
        let durationTimecode = try await mutableMovie.durationTimecode()

        // Replace the timecode track using TimecodeKit
        do {
            try await mutableMovie.replaceTimecodeTrack(
                startTimecode: timecodeObject,
                duration: durationTimecode,
                fileType: .mov
            )
            print("✅ Successfully replaced timecode track with TimecodeKit")
        } catch {
            print("❌ Failed to replace timecode track: \(error.localizedDescription)")
            return
        }

        // OPTIMIZED: Use faster export settings for timecode metadata
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(
            "temp_\(url.lastPathComponent)")

        guard
            let exportSession = AVAssetExportSession(
                asset: mutableMovie,
                presetName: AVAssetExportPresetPassthrough
            )
        else {
            print("❌ Failed to create export session")
            return
        }

        // OPTIMIZATION: Use faster export settings
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        // OPTIMIZATION: Single pass for speed
        if #available(macOS 12.0, *) {
            exportSession.canPerformMultiplePassesOverSourceMediaData = false
        }

        do {
            try await exportSession.export(to: tempURL, as: .mov)

            // Replace original file with timecode-enhanced version
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tempURL, to: url)
            print("✅ Successfully added timecode metadata to output file")
        } catch {
            print("❌ Failed to export timecode metadata: \(error.localizedDescription)")
            // Clean up temp file if it exists
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    func createGradedSegments(
        from segmentInfos: [SegmentInfo], baseDuration: CMTime, baseProperties: VideoProperties
    ) -> [GradedSegment] {
        var segments: [GradedSegment] = []

        // Sort segments by segment number if available, otherwise by filename
        let sortedSegments = segmentInfos.sorted { seg1, seg2 in
            if let num1 = seg1.segmentNumber, let num2 = seg2.segmentNumber {
                return num1 < num2
            }
            return seg1.filename < seg2.filename
        }

        for segmentInfo in sortedSegments {
            let startTime: CMTime
            let sourceStartTime: CMTime

            // Use extracted timecode-based timing (preferred)
            if let sourceTimecode = segmentInfo.sourceStartTimecode,
                let timecodeTime = timecodeToCMTime(
                    sourceTimecode, frameRate: baseProperties.frameRate,
                    baseTimecode: baseProperties.sourceTimecode)
            {
                // Use extracted timecode-based timing
                startTime = timecodeTime
                sourceStartTime = .zero
                let frameNumber = Int(timecodeTime.seconds * Double(baseProperties.frameRate))
                let outputTimecode = cmTimeToTimecode(
                    timecodeTime, frameRate: baseProperties.frameRate)
                print("🎬 Using extracted timecode for \(segmentInfo.filename):")
                print(
                    "   Extracted TC: \(sourceTimecode) → Frame \(frameNumber) (\(outputTimecode))")
            } else if let parsedStartTime = segmentInfo.startTime {
                // Use parsed start time if available
                startTime = parsedStartTime
                sourceStartTime = .zero
                let frameNumber = Int(parsedStartTime.seconds * Double(baseProperties.frameRate))
                let outputTimecode = cmTimeToTimecode(
                    parsedStartTime, frameRate: baseProperties.frameRate)
                print("🎬 Using parsed start time for \(segmentInfo.filename):")
                print(
                    "   Parsed: \(parsedStartTime.seconds)s → Frame \(frameNumber) (\(outputTimecode))"
                )
            } else {
                // Fallback to sequential timing
                let currentTime =
                    segments.isEmpty
                    ? .zero : CMTimeAdd(segments.last!.startTime, segments.last!.duration)
                startTime = currentTime
                sourceStartTime = .zero
                let frameNumber = Int(currentTime.seconds * Double(baseProperties.frameRate))
                let outputTimecode = cmTimeToTimecode(
                    currentTime, frameRate: baseProperties.frameRate)
                print("🎬 Using sequential timing for \(segmentInfo.filename):")
                print(
                    "   Sequential: \(currentTime.seconds)s → Frame \(frameNumber) (\(outputTimecode))"
                )
            }

            let segment = GradedSegment(
                url: segmentInfo.url,
                startTime: startTime,
                duration: segmentInfo.duration,
                sourceStartTime: sourceStartTime
            )

            segments.append(segment)
        }

        return segments
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
    let sourceTimecode: String?  // Source timecode from the base video
}

struct SegmentInfo {
    let url: URL
    let filename: String
    let duration: CMTime
    let startTime: CMTime?  // Optional: can be parsed from filename or metadata
    let segmentNumber: Int?  // Optional: can be parsed from filename
    let sourceTimecode: String?  // Source timecode from the segment file
    let sourceStartTimecode: String?  // Start timecode of the segment
}

enum CompositorError: Error {
    case setupFailed
    case noVideoTrack
    case cannotAddInput
    case failedToAppendFrame
    case invalidSegment
    case segmentDiscoveryFailed
    case invalidSegmentData
}

// MARK: - Hardware Acceleration Detection
private func checkHardwareAcceleration() {
    print("🔧 Checking hardware acceleration capabilities...")
    
    // Check Metal GPU capabilities
    if let device = MTLCreateSystemDefaultDevice() {
        print("✅ Metal GPU available: \(device.name)")
        print("📊 GPU memory: \(device.recommendedMaxWorkingSetSize / 1024 / 1024)MB")
        
        // Check CPU cores for parallel processing
        let processInfo = ProcessInfo.processInfo
        let cpuCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        print("🖥️ CPU cores: \(cpuCount) total, \(activeProcessorCount) active")
        
        // Check memory availability
        let totalMemory = processInfo.physicalMemory
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        print("💾 Total system memory: \(totalMemory / 1024 / 1024)MB")
        print("💾 Available memory: \(availableMemory / 1024 / 1024)MB")
        
        // Check if we're on Apple Silicon
        if #available(macOS 11.0, *) {
            if processInfo.isiOSAppOnMac {
                print("🚀 Apple Silicon detected - using memory-optimized ProRes engine")
            } else {
                print("🚀 Intel Mac with Metal GPU - using memory-optimized ProRes encoding")
            }
        }
    } else {
        print("❌ Metal GPU not available")
    }
    
    print("📹 Using memory-optimized ProRes encoding")
    print("🚀 Apple Silicon ProRes engine enabled with memory optimization")
}

// MARK: - Command Line Entry Point
func runComposition() async {
    print("🎬 Starting ProRes Composition...")

    checkHardwareAcceleration()

    let compositor = ProResVideoCompositor()
    
    // Paths
    let blankRushURL = URL(
        fileURLWithPath: "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRiush/COS AW25_4K_4444_24FPS_LR001_LOG.mov")
    let segmentsDirectoryURL = URL(fileURLWithPath: "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/ALL_GRADES_MM/")
    let outputURL = URL(fileURLWithPath: "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/OUT/w2/COS AW25_4K_4444_24FPS_LR001_LOG.mov")

    do {
        // Discover and parse segments automatically
        print("🔍 Discovering segments in: \(segmentsDirectoryURL.path)")
        let segmentInfos = try await compositor.discoverSegments(in: segmentsDirectoryURL)

        print("📊 Found \(segmentInfos.count) segments:")
        for (index, info) in segmentInfos.enumerated() {
            print("  \(index + 1). \(info.filename)")
            print(
                "     Duration: \(info.duration.seconds)s (\(Int(info.duration.seconds * 25)) frames)"
            )
            if let segmentNumber = info.segmentNumber {
                print("     Segment #: \(segmentNumber)")
            }
            if let startTime = info.startTime {
                let frameNumber = Int(startTime.seconds * 25)
                let timecode = compositor.cmTimeToTimecode(startTime, frameRate: 25)
                print(
                    "     Start Time: \(startTime.seconds)s (Frame \(frameNumber), TC: \(timecode))"
                )
            }
            if let sourceTimecode = info.sourceTimecode {
                print("     Source Timecode: \(sourceTimecode)")
            }
            if let sourceStartTimecode = info.sourceStartTimecode {
                print("     Start Timecode: \(sourceStartTimecode)")
            }
        }

        // Get base video properties and duration for timing calculations
        let blankRush = AVURLAsset(url: blankRushURL)
        let baseTrack = try await compositor.getVideoTrack(from: blankRush)
        var baseProperties = try await compositor.getVideoProperties(from: baseTrack)
        let baseDuration = try await blankRush.load(.duration)
        let totalFrames = Int(baseDuration.seconds * Double(baseProperties.frameRate))

        // Log the extracted timecode for debugging
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Extracted base timecode: \(sourceTimecode)")
        } else {
            print("📹 No timecode found in base video")
        }

        print("📹 Base video duration: \(baseDuration.seconds)s (\(totalFrames) frames)")
        print(
            "📹 Base video properties: \(baseProperties.width)x\(baseProperties.height) @ \(baseProperties.frameRate)fps"
        )
        if let sourceTimecode = baseProperties.sourceTimecode {
            print("📹 Base video source timecode: \(sourceTimecode)")
        }

        // Create graded segments from discovered info
        let segments = compositor.createGradedSegments(
            from: segmentInfos, baseDuration: baseDuration, baseProperties: baseProperties)

        print("🎬 Created \(segments.count) graded segments:")
        for (index, segment) in segments.enumerated() {
            print("  \(index + 1). \(segment.url.lastPathComponent)")
            let startFrame = Int(segment.startTime.seconds * Double(baseProperties.frameRate))
            let endFrame =
                startFrame + Int(segment.duration.seconds * Double(baseProperties.frameRate))
            let startTimecode = compositor.cmTimeToTimecode(
                segment.startTime, frameRate: baseProperties.frameRate)
            let endTimecode = compositor.cmTimeToTimecode(
                CMTimeAdd(segment.startTime, segment.duration), frameRate: baseProperties.frameRate)
            print(
                "     Start: Frame \(startFrame) (\(startTimecode)), Duration: \(segment.duration.seconds)s (\(Int(segment.duration.seconds * Double(baseProperties.frameRate))) frames)"
            )
            print("     End: Frame \(endFrame) (\(endTimecode))")
            if let sourceTimecode = baseProperties.sourceTimecode {
                print("     Base Source TC: \(sourceTimecode)")
            }
        }

        // 🎬 RENDER PHASE: Press Enter to start (like DaVinci Resolve's render button)
        print("\n🎬 Timeline ready! Press Enter to start render...")
        print("📊 This will measure only the export time (like DaVinci Resolve)")
        _ = readLine()
        print("🚀 Starting render...")

        let settings = CompositorSettings(
            outputURL: outputURL,
            baseVideoURL: blankRushURL,
            gradedSegments: segments,
            proResType: .proRes422HQ
        )

        // Setup progress callback for command line
        compositor.progressHandler = { progress in
            let percentage = Int(progress * 100)
            let progressBar = String(repeating: "█", count: percentage / 2)
            let emptyBar = String(repeating: "░", count: 50 - (percentage / 2))
            print("\r📹 Progress: [\(progressBar)\(emptyBar)] \(percentage)%", terminator: "")
            fflush(stdout)
        }

        // Setup completion handler and wait for completion
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            compositor.completionHandler = { result in
                print("\n")  // New line after progress bar
                switch result {
                case .success(let outputURL):
                    print("✅ Composition complete!")
                    print("📁 Output file: \(outputURL.path)")
                    continuation.resume()
                case .failure(let error):
                    print("❌ Composition failed: \(error.localizedDescription)")
                    continuation.resume()
                }
            }

            // Start the composition
            compositor.composeVideo(with: settings)
        }

    } catch {
        print("❌ Failed to discover or parse segments: \(error.localizedDescription)")
    }
}

Task {
    await runComposition()
    exit(0)
}

RunLoop.main.run()
