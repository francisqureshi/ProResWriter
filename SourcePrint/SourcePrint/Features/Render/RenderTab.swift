//
//  RenderTab.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore
import AVFoundation
import CoreMedia
import TimecodeKit

@available(macOS 15, *)
struct RenderTab: View {
    @ObservedObject var project: Project
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isRendering = false
    @State private var renderProgress = ""
    @State private var currentClipName: String = ""
    @State private var currentFileIndex: Int = 0
    @State private var totalFileCount: Int = 0
    @State private var shouldStopRendering = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Render Queue Controls
            VStack {
                HStack {
                    Text("Render Queue")
                        .font(.headline)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button("Clear Completed") {
                            clearCompletedItems()
                        }
                        .buttonStyle(CompressorButtonStyle())
                        .disabled(project.renderQueue.isEmpty || !hasCompletedItems)
                        
                        Button(isRendering ? "Stop" : "Process Queue") {
                            if isRendering {
                                stopQueueProcessing()
                            } else {
                                startQueueProcessing()
                            }
                        }
                        .buttonStyle(CompressorButtonStyle(prominent: true))
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isRendering ? AppTheme.error : AppTheme.accent)
                        )
                        .disabled(!isRendering && queuedItemsCount == 0)
                    }
                }
                
                HStack {
                    Text("\(queuedItemsCount) queued • \(completedItemsCount) completed • \(failedItemsCount) failed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Output: \(project.outputDirectory.path)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if isRendering {
                    VStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(renderProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if totalFileCount > 0 {
                                    Text("\(currentFileIndex)/\(totalFileCount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            if !currentClipName.isEmpty {
                                HStack {
                                    Text("🎬 \(currentClipName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("ProRes 4444 Passthrough")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        ProgressView()
                            .progressViewStyle(.linear)
                            .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    }
                }
            }
            .padding()
            
            // Render Queue Display
            if project.renderQueue.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Render Queue Empty")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Add items to the render queue from the Linking tab")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Render Queue Items
                List {
                    ForEach(sortedRenderQueue, id: \.id) { item in
                        RenderQueueItemView(item: item, project: project)
                    }
                    .onDelete(perform: removeQueueItems)
                }
            }
        }
    }
    
    // MARK: - Render Queue Computed Properties
    
    var sortedRenderQueue: [RenderQueueItem] {
        project.renderQueue.sorted { $0.addedDate < $1.addedDate }
    }
    
    var queuedItemsCount: Int {
        project.renderQueue.filter { $0.status == .queued }.count
    }
    
    var completedItemsCount: Int {
        project.renderQueue.filter { $0.status == .completed }.count
    }
    
    var failedItemsCount: Int {
        project.renderQueue.filter { $0.status == .failed }.count
    }
    
    var hasCompletedItems: Bool {
        project.renderQueue.contains { $0.status == .completed || $0.status == .failed }
    }
    
    var isReadyForRender: Bool {
        guard project.linkingResult != nil else { return false }
        
        // Check if we have any completed blank rushes
        let completedBlankRushes = project.blankRushStatus.values.compactMap { status in
            if case .completed = status { return 1 } else { return nil }
        }.count
        
        return completedBlankRushes > 0
    }
    
    // MARK: - Render Queue Methods
    
    private func clearCompletedItems() {
        project.renderQueue.removeAll { $0.status == .completed || $0.status == .failed }
        projectManager.saveProject(project)
    }
    
    private func stopQueueProcessing() {
        shouldStopRendering = true
        renderProgress = "Stopping after current item..."
        NSLog("🛑 User requested to stop queue processing")
    }
    
    private func removeQueueItems(at offsets: IndexSet) {
        let itemsToRemove = offsets.map { sortedRenderQueue[$0] }
        for item in itemsToRemove {
            project.renderQueue.removeAll { $0.id == item.id }
        }
        projectManager.saveProject(project)
    }
    
    private func startQueueProcessing() {
        guard let linkingResult = project.linkingResult else { return }
        
        // Get queued items that have completed blank rushes
        let queuedItems = project.renderQueue.filter { $0.status == .queued }
        guard !queuedItems.isEmpty else { return }
        
        isRendering = true
        shouldStopRendering = false  // Reset stop flag
        renderProgress = "Processing render queue..."
        totalFileCount = queuedItems.count
        currentFileIndex = 0
        
        Task {
            var allPrintRecords: [PrintRecord] = []
            
            for (index, queueItem) in queuedItems.enumerated() {
                // Check if user requested to stop
                if shouldStopRendering {
                    NSLog("🛑 Stopping queue processing as requested by user")
                    break
                }
                
                // Mark item as rendering
                if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                    project.renderQueue[queueIndex].status = .rendering
                }
                
                // Find the OCF parent for this queue item
                guard let ocfParent = linkingResult.parentsWithChildren.first(where: { $0.ocf.fileName == queueItem.ocfFileName }) else {
                    NSLog("⚠️ No OCF parent found for \(queueItem.ocfFileName)")
                    if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                        project.renderQueue[queueIndex].status = .failed
                    }
                    continue
                }
                
                // Get the blank rush URL
                guard let blankRushStatus = project.blankRushStatus[queueItem.ocfFileName],
                      case .completed(_, let blankRushURL) = blankRushStatus else {
                    NSLog("⚠️ No completed blank rush found for \(queueItem.ocfFileName)")
                    if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                        project.renderQueue[queueIndex].status = .failed
                    }
                    continue
                }
                
                await MainActor.run {
                    currentFileIndex = index + 1
                    currentClipName = (ocfParent.ocf.fileName as NSString).deletingPathExtension
                    renderProgress = "Creating composition..."
                }
                
                do {
                    // Generate output filename - use source name only, overwrite existing
                    let baseName = (ocfParent.ocf.fileName as NSString).deletingPathExtension
                    let outputFileName = "\(baseName).mov"
                    let outputURL = project.outputDirectory.appendingPathComponent(outputFileName)
                    
                    // Create SwiftFFmpeg compositor (Premiere Pro compatible)
                    let compositor = SwiftFFmpegProResCompositor()
                    
                    // Convert linked children to FFmpegGradedSegments with VFX metadata
                    var ffmpegGradedSegments: [FFmpegGradedSegment] = []
                    for child in ocfParent.children {
                        let segmentInfo = child.segment  // This is a MediaFileInfo

                        // Debug: Check what data we have
                        NSLog("🔍 Segment \(segmentInfo.fileName):")
                        NSLog("   sourceTimecode: \(segmentInfo.sourceTimecode ?? "nil")")
                        NSLog("   frameRate (AVRational): \(String(describing: segmentInfo.frameRate))")
                        NSLog("   frameRateFloat: \(String(describing: segmentInfo.frameRateFloat))")
                        NSLog("   durationInFrames: \(String(describing: segmentInfo.durationInFrames))")

                        // MediaFileInfo already has all the data we need
                        if let segmentTC = segmentInfo.sourceTimecode,
                           let baseTC = ocfParent.ocf.sourceTimecode,
                           let segmentFrameRate = segmentInfo.frameRate,  // This is AVRational
                           let segmentFrameRateFloat = segmentInfo.frameRateFloat,
                           let duration = segmentInfo.durationInFrames {

                            // Use SMPTE for precise timecode calculation like CLI
                            let smpte = SMPTE(fps: Double(segmentFrameRateFloat), dropFrame: segmentInfo.isDropFrame ?? false)

                            do {
                                let segmentFrames = try smpte.getFrames(tc: segmentTC)
                                let baseFrames = try smpte.getFrames(tc: baseTC)
                                let relativeFrames = segmentFrames - baseFrames

                                let startTime = CMTime(
                                    value: CMTimeValue(relativeFrames),
                                    timescale: CMTimeScale(segmentFrameRateFloat)
                                )

                                let segmentDuration = CMTime(
                                    seconds: Double(duration) / Double(segmentFrameRateFloat),
                                    preferredTimescale: CMTimeScale(segmentFrameRateFloat * 1000)
                                )

                                let ffmpegSegment = FFmpegGradedSegment(
                                    url: segmentInfo.url,
                                    startTime: startTime,
                                    duration: segmentDuration,
                                    sourceStartTime: .zero,
                                    isVFXShot: segmentInfo.isVFXShot ?? false,
                                    sourceTimecode: segmentInfo.sourceTimecode,
                                    frameRate: segmentFrameRateFloat,
                                    frameRateRational: segmentFrameRate,  // Pass the AVRational directly
                                    isDropFrame: segmentInfo.isDropFrame
                                )
                                ffmpegGradedSegments.append(ffmpegSegment)
                                
                            } catch {
                                NSLog("⚠️ SMPTE calculation failed for \(segmentInfo.fileName): \(error)")
                                continue
                            }
                        } else {
                            NSLog("❌ Skipping segment \(segmentInfo.fileName) - missing required data")
                            NSLog("   Missing: \(segmentInfo.sourceTimecode == nil ? "sourceTimecode " : "")\(segmentInfo.frameRate == nil ? "frameRate " : "")\(segmentInfo.frameRateFloat == nil ? "frameRateFloat " : "")\(segmentInfo.durationInFrames == nil ? "durationInFrames" : "")")
                        }
                    }
                    
                    guard !ffmpegGradedSegments.isEmpty else {
                        NSLog("❌ No valid FFmpeg graded segments for \(ocfParent.ocf.fileName)")
                        if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                            project.renderQueue[queueIndex].status = .failed
                        }
                        continue
                    }
                    
                    // Setup SwiftFFmpeg compositor settings
                    let settings = FFmpegCompositorSettings(
                        outputURL: outputURL,
                        baseVideoURL: blankRushURL,
                        gradedSegments: ffmpegGradedSegments,
                        proResProfile: "4"  // ProRes 4444
                    )
                    
                    // Remove progress handler for indeterminate progress bar
                    compositor.progressHandler = nil
                    
                    // Process composition
                    let compositionStartTime = Date()
                    let result = await withCheckedContinuation { continuation in
                        compositor.completionHandler = { result in
                            continuation.resume(returning: result)
                        }
                        compositor.composeVideo(with: settings)
                    }
                    
                    let compositionDuration = Date().timeIntervalSince(compositionStartTime)
                    
                    switch result {
                    case .success(let finalOutputURL):
                        let printRecord = PrintRecord(
                            date: Date(),
                            outputURL: finalOutputURL,
                            segmentCount: ffmpegGradedSegments.count,
                            duration: compositionDuration,
                            success: true
                        )
                        allPrintRecords.append(printRecord)
                        
                        // Mark queue item as completed and update print status
                        if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                            project.renderQueue[queueIndex].status = .completed
                        }
                        project.printStatus[queueItem.ocfFileName] = .printed(date: Date(), outputURL: finalOutputURL)

                        // Clear modification dates for all printed segments (they're now in the print)
                        for child in ocfParent.children {
                            if project.segmentModificationDates[child.segment.fileName] != nil {
                                project.segmentModificationDates.removeValue(forKey: child.segment.fileName)
                                NSLog("🔄 Cleared 'Updated' status for printed segment: %@", child.segment.fileName)
                            }
                        }

                        NSLog("✅ Composition completed: \(finalOutputURL.lastPathComponent)")
                        
                    case .failure(let error):
                        let printRecord = PrintRecord(
                            date: Date(),
                            outputURL: outputURL,
                            segmentCount: ffmpegGradedSegments.count,
                            duration: compositionDuration,
                            success: false
                        )
                        allPrintRecords.append(printRecord)
                        
                        // Mark queue item as failed
                        if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                            project.renderQueue[queueIndex].status = .failed
                        }
                        
                        NSLog("❌ Composition failed: \(error)")
                    }
                    
                } catch {
                    NSLog("❌ Print process error for \(ocfParent.ocf.fileName): \(error)")
                    let printRecord = PrintRecord(
                        date: Date(),
                        outputURL: project.outputDirectory.appendingPathComponent("\(currentClipName).mov"),
                        segmentCount: 0,
                        duration: 0,
                        success: false
                    )
                    allPrintRecords.append(printRecord)
                    
                    // Mark queue item as failed
                    if let queueIndex = project.renderQueue.firstIndex(where: { $0.id == queueItem.id }) {
                        project.renderQueue[queueIndex].status = .failed
                    }
                }
                
                // Brief pause between files
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await MainActor.run {
                // Add all print records to project
                for record in allPrintRecords {
                    project.addPrintRecord(record)
                }
                projectManager.saveProject(project)
                
                let successCount = allPrintRecords.filter { $0.success }.count
                let wasStopped = shouldStopRendering
                
                isRendering = false
                shouldStopRendering = false
                renderProgress = ""
                currentClipName = ""
                currentFileIndex = 0
                totalFileCount = 0
                
                if wasStopped {
                    NSLog("🛑 Render queue processing stopped by user: \(successCount)/\(allPrintRecords.count) items completed before stopping")
                } else {
                    NSLog("✅ Render queue processing completed: \(successCount)/\(allPrintRecords.count) items successful")
                }
            }
        }
    }
}

// MARK: - Render Queue Item View

struct RenderQueueItemView: View {
    let item: RenderQueueItem
    @ObservedObject var project: Project
    
    var body: some View {
        HStack {
            Image(systemName: item.status.icon)
                .foregroundColor(item.status.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text((item.ocfFileName as NSString).deletingPathExtension)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                HStack {
                    Text("Added: \(DateFormatter.short.string(from: item.addedDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(item.status.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if item.status == .rendering {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            
            Spacer()
            
            // Show print status if available
            if let printStatus = project.printStatus[item.ocfFileName] {
                StatusLabel(printStatus.displayName, color: printStatus.color, icon: printStatus.icon)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let filenameSafe: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}