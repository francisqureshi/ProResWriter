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
    let project: Project
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isRendering = false
    @State private var renderProgress = ""
    @State private var currentClipName: String = ""
    @State private var currentFileIndex: Int = 0
    @State private var totalFileCount: Int = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Render Controls
            VStack {
                HStack {
                    Button("Start Print Process") {
                        startPrintProcess()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReadyForRender || isRendering)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(renderStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Output: \(project.outputDirectory.path)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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
            
            // Render Results Display
            if project.printHistory.isEmpty {
                VStack {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No renders yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Complete linking and blank rush generation, then start the print process")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Print History Display
                List(project.printHistory.reversed(), id: \.id) { record in
                    HStack {
                        Text(record.statusIcon)
                        VStack(alignment: .leading) {
                            Text("Print: \(DateFormatter.short.string(from: record.date))")
                                .font(.headline)
                            Text("\(record.segmentCount) segments • \(String(format: "%.1f", record.duration))s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Show Output Folder") {
                            NSWorkspace.shared.open(project.outputDirectory)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
    
    var isReadyForRender: Bool {
        guard project.linkingResult != nil else { return false }
        
        // Check if we have any completed blank rushes
        let completedBlankRushes = project.blankRushStatus.values.compactMap { status in
            if case .completed = status { return 1 } else { return nil }
        }.count
        
        return completedBlankRushes > 0
    }
    
    var renderStatusText: String {
        if !isReadyForRender {
            return "Complete linking and blank rush generation first"
        }
        
        let completedBlankRushes = project.blankRushStatus.values.compactMap { status in
            if case .completed = status { return 1 } else { return nil }
        }.count
        
        return "\(completedBlankRushes) blank rushes ready for print"
    }
    
    private func startPrintProcess() {
        guard let linkingResult = project.linkingResult else { return }
        
        // Get completed blank rushes
        let completedBlankRushes = project.blankRushStatus.compactMap { (fileName, status) -> (String, URL)? in
            if case .completed(_, let url) = status {
                return (fileName, url)
            }
            return nil
        }
        
        guard !completedBlankRushes.isEmpty else { return }
        
        isRendering = true
        renderProgress = "Starting print process..."
        totalFileCount = completedBlankRushes.count
        currentFileIndex = 0
        
        Task {
            let startTime = Date()
            var allPrintRecords: [PrintRecord] = []
            
            // Process each OCF that has children and a completed blank rush
            let validParents = linkingResult.parentsWithChildren
            
            for (index, ocfParent) in validParents.enumerated() {
                guard let blankRushEntry = completedBlankRushes.first(where: { $0.0 == ocfParent.ocf.fileName }) else {
                    NSLog("⚠️ No blank rush found for \(ocfParent.ocf.fileName)")
                    continue
                }
                
                let blankRushURL = blankRushEntry.1
                
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
                        let segmentInfo = child.segment
                        
                        // Find corresponding MediaFileInfo for VFX metadata
                        guard let mediaFileInfo = project.segments.first(where: { $0.fileName == segmentInfo.fileName }) else {
                            NSLog("⚠️ Warning: No MediaFileInfo found for \(segmentInfo.fileName)")
                            continue
                        }
                        
                        if let segmentTC = segmentInfo.sourceTimecode,
                           let baseTC = ocfParent.ocf.sourceTimecode,
                           let segmentFrameRate = segmentInfo.frameRate,
                           let duration = segmentInfo.durationInFrames {
                            
                            // Use SMPTE for precise timecode calculation like CLI
                            let smpte = SMPTE(fps: Double(segmentFrameRate), dropFrame: segmentInfo.isDropFrame ?? false)
                            
                            do {
                                let segmentFrames = try smpte.getFrames(tc: segmentTC)
                                let baseFrames = try smpte.getFrames(tc: baseTC)
                                let relativeFrames = segmentFrames - baseFrames
                                
                                let startTime = CMTime(
                                    value: CMTimeValue(relativeFrames),
                                    timescale: CMTimeScale(segmentFrameRate)
                                )
                                
                                let segmentDuration = CMTime(
                                    seconds: Double(duration) / Double(segmentFrameRate),
                                    preferredTimescale: CMTimeScale(segmentFrameRate * 1000)
                                )
                                
                                let ffmpegSegment = FFmpegGradedSegment(
                                    url: segmentInfo.url,
                                    startTime: startTime,
                                    duration: segmentDuration,
                                    sourceStartTime: .zero,
                                    isVFXShot: mediaFileInfo.isVFXShot ?? false,
                                    sourceTimecode: segmentInfo.sourceTimecode,
                                    frameRate: segmentInfo.frameRate,
                                    isDropFrame: segmentInfo.isDropFrame
                                )
                                ffmpegGradedSegments.append(ffmpegSegment)
                                
                            } catch {
                                NSLog("⚠️ SMPTE calculation failed for \(segmentInfo.fileName): \(error)")
                                continue
                            }
                        }
                    }
                    
                    guard !ffmpegGradedSegments.isEmpty else {
                        NSLog("❌ No valid FFmpeg graded segments for \(ocfParent.ocf.fileName)")
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
                
                isRendering = false
                renderProgress = ""
                currentClipName = ""
                currentFileIndex = 0
                totalFileCount = 0
                
                let successCount = allPrintRecords.filter { $0.success }.count
                NSLog("✅ Print process completed: \(successCount)/\(allPrintRecords.count) compositions successful")
            }
        }
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