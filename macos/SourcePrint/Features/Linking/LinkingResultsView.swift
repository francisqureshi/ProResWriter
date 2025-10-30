//
//  LinkingResultsView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SourcePrintCore
import SwiftUI
import AVFoundation
import CoreMedia
import TimecodeKit

extension Notification.Name {
    static let expandSelectedCards = Notification.Name("expandSelectedCards")
    static let collapseSelectedCards = Notification.Name("collapseSelectedCards")
    static let collapseAllCards = Notification.Name("collapseAllCards")
    static let renderOCF = Notification.Name("renderOCF")
}

// MARK: - Helper Functions

/// Format linkMethod string into user-friendly badge labels
func formatLinkMethodBadges(_ linkMethod: String) -> [String] {
    let criteria = linkMethod.split(separator: "+").map(String.init)
    return criteria.map { criterion in
        switch criterion {
        case "resolution": return "Resolution"
        case "fps": return "FPS"
        case "filename_contains": return "Filename"
        case "timecode_range": return "Timecode"
        case "reel": return "Reel"
        case "vfx_exemption": return "VFX"
        case "consumer_camera": return "Consumer"
        default: return criterion.capitalized
        }
    }
}

/// Sort segments chronologically by start timecode
func sortedByTimecode(_ segments: [LinkedSegment]) -> [LinkedSegment] {
    return segments.sorted { seg1, seg2 in
        guard let tc1 = seg1.segment.sourceTimecode,
              let tc2 = seg2.segment.sourceTimecode else {
            // If no timecode, maintain original order
            return false
        }
        // Timecode strings sort correctly lexicographically (HH:MM:SS:FF or HH:MM:SS;FF)
        return tc1 < tc2
    }
}

struct LinkingResultsView: View {
    @ObservedObject var project: Project
    let timelineVisualizationData: [String: TimelineVisualization]
    @EnvironmentObject var projectManager: ProjectManager
    var onPerformLinking: (() -> Void)? = nil
    var onGenerateBlankRushes: (() -> Void)? = nil

    // Use the project's current linking result instead of a cached copy
    private var linkingResult: LinkingResult? {
        project.linkingResult
    }
    @State private var selectedLinkedFiles: Set<String> = []
    @State private var selectedUnmatchedFiles: Set<String> = []
    @State private var selectedOCFParents: Set<String> = []
    @State private var showUnmatchedDrawer = true

    // Unified navigation state
    enum NavigationContext {
        case ocfList
        case segmentList
    }
    @State private var navigationContext: NavigationContext = .ocfList
    @State private var focusedOCFIndex: Int = 0

    // Batch render queue
    @State private var batchRenderQueue: [String] = []
    @State private var isProcessingBatchQueue = false
    @State private var totalInBatch: Int = 0
    @State private var currentlyRenderingOCF: String? = nil  // Track which OCF is currently rendering

    // Computed properties to separate high/medium confidence from low confidence segments
    var confidentlyLinkedParents: [OCFParent] {
        guard let linkingResult = linkingResult else { return [] }
        return linkingResult.ocfParents.compactMap { parent in
            let goodSegments = parent.children.filter { segment in
                segment.linkConfidence == .high || segment.linkConfidence == .medium
            }
            return goodSegments.isEmpty ? nil : OCFParent(ocf: parent.ocf, children: goodSegments)
        }
    }

    var lowConfidenceSegments: [LinkedSegment] {
        guard let linkingResult = linkingResult else { return [] }
        return linkingResult.ocfParents.flatMap { parent in
            parent.children.filter { segment in
                segment.linkConfidence == .low
            }
        }
    }

    var totalConfidentSegments: Int {
        return confidentlyLinkedParents.reduce(0) { $0 + $1.childCount }
    }

    var totalUnmatchedItems: Int {
        guard let linkingResult = linkingResult else { return 0 }
        return linkingResult.unmatchedOCFs.count + linkingResult.unmatchedSegments.count
            + lowConfidenceSegments.count
    }

    // Batch render computed properties
    var canRenderAll: Bool {
        return confidentlyLinkedParents.contains { parent in
            !project.offlineMediaFiles.contains(parent.ocf.fileName)
        }
    }

    var canRenderModified: Bool {
        return confidentlyLinkedParents.contains { parent in
            parent.children.contains { child in
                project.segmentModificationDates[child.segment.fileName] != nil
            }
        }
    }

    // Helper to get selected OCF parents for context menu batch operations
    private func getSelectedParents() -> [OCFParent] {
        return confidentlyLinkedParents.filter { parent in
            selectedOCFParents.contains(parent.ocf.fileName)
        }
    }

    // Batch render functions - simple queue approach
    // Each OCF card handles its own blank rush check/creation then prints

    private func renderAll() {
        let ocfsToRender = confidentlyLinkedParents.filter { parent in
            !project.offlineMediaFiles.contains(parent.ocf.fileName)
        }

        NSLog("🎬 Starting batch render for %d OCFs", ocfsToRender.count)

        batchRenderQueue = ocfsToRender.map { $0.ocf.fileName }
        totalInBatch = batchRenderQueue.count
        isProcessingBatchQueue = true

        // Start processing queue - each card will handle blank rush + print
        processBatchRenderQueue()
    }

    private func renderModified() {
        let modifiedOCFs = confidentlyLinkedParents.filter { parent in
            parent.children.contains { child in
                project.segmentModificationDates[child.segment.fileName] != nil
            }
        }

        NSLog("🔄 Starting batch render for %d modified OCFs", modifiedOCFs.count)

        batchRenderQueue = modifiedOCFs.map { $0.ocf.fileName }
        totalInBatch = batchRenderQueue.count
        isProcessingBatchQueue = true

        // Start processing queue - each card will handle blank rush + print
        processBatchRenderQueue()
    }

    private func processBatchRenderQueue() {
        guard !batchRenderQueue.isEmpty else {
            isProcessingBatchQueue = false
            totalInBatch = 0
            NSLog("✅ Batch render queue completed!")
            return
        }

        let nextOCFFileName = batchRenderQueue.removeFirst()

        NSLog("📤 Processing batch queue: %@ (%d remaining)", nextOCFFileName, batchRenderQueue.count)

        // Find the parent for this OCF
        guard let parent = confidentlyLinkedParents.first(where: { $0.ocf.fileName == nextOCFFileName }) else {
            NSLog("⚠️ Could not find parent for %@, skipping", nextOCFFileName)
            processBatchRenderQueue()
            return
        }

        // Set the currently rendering OCF (prevents other cards from starting)
        currentlyRenderingOCF = nextOCFFileName

        // Post notification to trigger card's UI and rendering
        NotificationCenter.default.post(
            name: .renderOCF,
            object: nil,
            userInfo: ["ocfFileName": nextOCFFileName]
        )

        // Poll until this OCF completes or times out (5 minutes max per OCF)
        var pollCount = 0
        let maxPolls = 600 // 5 minutes at 0.5s intervals

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            pollCount += 1

            if case .printed = project.printStatus[nextOCFFileName] {
                timer.invalidate()
                NSLog("✅ Completed %@ after %d polls, processing next in queue", nextOCFFileName, pollCount)

                // Clear currently rendering flag
                currentlyRenderingOCF = nil

                // Small delay then process next item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    processBatchRenderQueue()
                }
            } else if pollCount >= maxPolls {
                timer.invalidate()
                NSLog("⚠️ Timeout waiting for %@ after %d seconds, falling back to direct processing", nextOCFFileName, pollCount / 2)

                // Clear currently rendering flag before fallback
                currentlyRenderingOCF = nil

                // Fallback to direct processing if card doesn't respond
                Task {
                    await processOCFInQueue(parent: parent)

                    // Process next item
                    await MainActor.run {
                        processBatchRenderQueue()
                    }
                }
            } else if pollCount % 20 == 0 {
                // Log status every 10 seconds
                NSLog("   Still waiting for %@... (status: %@)", nextOCFFileName, String(describing: project.printStatus[nextOCFFileName]))
            }
        }
    }

    @MainActor
    private func processOCFInQueue(parent: OCFParent) async {
        let ocfFileName = parent.ocf.fileName
        NSLog("🎬 Starting render for %@", ocfFileName)

        // Check if blank rush exists
        let blankRushStatus = project.blankRushStatus[ocfFileName] ?? .notCreated

        var blankRushURL: URL?

        switch blankRushStatus {
        case .completed(_, let url):
            // Verify blank rush file actually exists on disk
            if FileManager.default.fileExists(atPath: url.path) {
                NSLog("✅ Using existing blank rush for %@", ocfFileName)
                blankRushURL = url
            } else {
                NSLog("⚠️ Blank rush file missing for %@ - will create", ocfFileName)
                blankRushURL = await createBlankRushForOCF(parent: parent)
            }

        case .notCreated, .failed:
            NSLog("📝 Creating blank rush for %@", ocfFileName)
            blankRushURL = await createBlankRushForOCF(parent: parent)

        case .inProgress:
            // Check if file exists despite .inProgress status
            let url = project.blankRushDirectory
                .appendingPathComponent(parent.ocf.fileName)
                .deletingPathExtension()
                .appendingPathExtension("mov")

            if FileManager.default.fileExists(atPath: url.path) {
                NSLog("✅ Using existing blank rush for %@ (was .inProgress)", ocfFileName)
                blankRushURL = url
            } else {
                NSLog("⚠️ Blank rush stuck in .inProgress for %@ - recreating", ocfFileName)
                project.blankRushStatus[ocfFileName] = .notCreated
                projectManager.saveProject(project)
                blankRushURL = await createBlankRushForOCF(parent: parent)
            }
        }

        guard let validBlankRushURL = blankRushURL else {
            NSLog("❌ Failed to get/create blank rush for %@, skipping", ocfFileName)
            return
        }

        // Now render
        await renderOCFInQueue(parent: parent, blankRushURL: validBlankRushURL)
    }

    @MainActor
    private func createBlankRushForOCF(parent: OCFParent) async -> URL? {
        let ocfFileName = parent.ocf.fileName

        // Mark as in progress
        project.blankRushStatus[ocfFileName] = .inProgress
        projectManager.saveProject(project)

        // Create single-file linking result for this OCF
        let singleOCFResult = LinkingResult(
            ocfParents: [parent],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )

        let blankRushCreator = BlankRushIntermediate(projectDirectory: project.blankRushDirectory.path)

        // Create blank rush
        let results = await blankRushCreator.createBlankRushes(from: singleOCFResult)

        // Process result
        if let result = results.first {
            if result.success {
                project.blankRushStatus[result.originalOCF.fileName] = .completed(date: Date(), url: result.blankRushURL)
                projectManager.saveProject(project)
                NSLog("✅ Created blank rush for %@", ocfFileName)
                return result.blankRushURL
            } else {
                let errorMessage = result.error ?? "Unknown error"
                project.blankRushStatus[result.originalOCF.fileName] = .failed(error: errorMessage)
                projectManager.saveProject(project)
                NSLog("❌ Failed to create blank rush for %@: %@", ocfFileName, errorMessage)
                return nil
            }
        }

        return nil
    }

    @MainActor
    private func renderOCFInQueue(parent: OCFParent, blankRushURL: URL) async {
        let ocfFileName = parent.ocf.fileName
        NSLog("🎥 Rendering %@", ocfFileName)

        do {
            // Generate output filename
            let baseName = (ocfFileName as NSString).deletingPathExtension
            let outputFileName = "\(baseName).mov"
            let outputURL = project.outputDirectory.appendingPathComponent(outputFileName)

            // Create SwiftFFmpeg compositor
            let compositor = SwiftFFmpegProResCompositor()

            // Convert linked children to FFmpegGradedSegments
            var ffmpegGradedSegments: [FFmpegGradedSegment] = []
            for child in parent.children {
                let segmentInfo = child.segment

                if let segmentTC = segmentInfo.sourceTimecode,
                   let baseTC = parent.ocf.sourceTimecode,
                   let segmentFrameRate = segmentInfo.frameRate,
                   let segmentFrameRateFloat = segmentInfo.frameRateFloat,
                   let duration = segmentInfo.durationInFrames {

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
                            frameRateRational: segmentFrameRate,
                            isDropFrame: segmentInfo.isDropFrame
                        )
                        ffmpegGradedSegments.append(ffmpegSegment)
                    } catch {
                        NSLog("⚠️ SMPTE calculation failed for %@: %@", segmentInfo.fileName, error.localizedDescription)
                        continue
                    }
                }
            }

            guard !ffmpegGradedSegments.isEmpty else {
                NSLog("❌ No valid FFmpeg graded segments for %@", ocfFileName)
                return
            }

            // Setup compositor settings
            let settings = FFmpegCompositorSettings(
                outputURL: outputURL,
                baseVideoURL: blankRushURL,
                gradedSegments: ffmpegGradedSegments,
                proResProfile: "4"
            )

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

                project.printStatus[ocfFileName] = .printed(date: Date(), outputURL: finalOutputURL)
                project.printHistory.append(printRecord)
                projectManager.saveProject(project)

                NSLog("✅ Successfully rendered %@ in %.1fs", ocfFileName, compositionDuration)

            case .failure(let error):
                NSLog("❌ Failed to render %@: %@", ocfFileName, error.localizedDescription)
            }
        } catch {
            NSLog("❌ Error rendering %@: %@", ocfFileName, error.localizedDescription)
        }
    }

    var body: some View {
        Group {
            if linkingResult == nil {
                VStack {
                    // Action buttons even when no results
                    HStack {
                        Text("Linking")
                            .font(.headline)
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            if let performLinking = onPerformLinking {
                                Button("Run Auto-Linking") {
                                    performLinking()
                                }
                                .buttonStyle(CompressorButtonStyle(prominent: true))
                                .disabled(project.ocfFiles.isEmpty || project.segments.isEmpty)
                            }
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    VStack(spacing: 12) {
                        Image(systemName: "link.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No linking results yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        if project.ocfFiles.isEmpty && project.segments.isEmpty {
                            Text("Import OCF files and segments to begin linking")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else if project.ocfFiles.isEmpty {
                            Text("Import OCF files to link with segments")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else if project.segments.isEmpty {
                            Text("Import segments to link with OCF files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Click 'Run Auto-Linking' to match segments with OCF files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                linkingResultsContent
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) {
            expandSelectedCards()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            collapseSelectedCards()
            return .handled
        }
        .onKeyPress(.downArrow) {
            handleDownArrow()
            return .handled
        }
        .onKeyPress(.upArrow) {
            handleUpArrow()
            return .handled
        }
    }

    private func expandSelectedCards() {
        // This will be handled by each individual card
        NotificationCenter.default.post(name: .expandSelectedCards, object: nil)
    }

    private func collapseSelectedCards() {
        // This will be handled by each individual card
        NotificationCenter.default.post(name: .collapseSelectedCards, object: nil)
    }

    private func handleDownArrow() {
        guard !confidentlyLinkedParents.isEmpty else { return }

        // Ensure focusedOCFIndex is valid
        if focusedOCFIndex >= confidentlyLinkedParents.count {
            focusedOCFIndex = 0
        }

        let currentOCF = confidentlyLinkedParents[focusedOCFIndex]
        let sortedChildren = sortedByTimecode(currentOCF.children)

        switch navigationContext {
        case .ocfList:
            // Currently focused on an OCF card
            let isExpanded = project.ocfCardExpansionState[currentOCF.ocf.fileName] ?? true

            if isExpanded && !sortedChildren.isEmpty {
                // OCF is expanded and has segments → move to first segment
                navigationContext = .segmentList
                selectedOCFParents = [currentOCF.ocf.fileName]
                selectedLinkedFiles = [sortedChildren[0].segment.fileName]
            } else {
                // OCF is collapsed or has no segments → move to next OCF
                if focusedOCFIndex < confidentlyLinkedParents.count - 1 {
                    focusedOCFIndex += 1
                    selectedOCFParents = [confidentlyLinkedParents[focusedOCFIndex].ocf.fileName]
                }
            }

        case .segmentList:
            // Currently focused on a segment
            guard let currentSegment = selectedLinkedFiles.first,
                  let segmentIndex = sortedChildren.firstIndex(where: { $0.segment.fileName == currentSegment }) else {
                return
            }

            if segmentIndex < sortedChildren.count - 1 {
                // Move to next segment in current OCF
                selectedLinkedFiles = [sortedChildren[segmentIndex + 1].segment.fileName]
            } else {
                // At last segment → move to next OCF card
                if focusedOCFIndex < confidentlyLinkedParents.count - 1 {
                    focusedOCFIndex += 1
                    navigationContext = .ocfList
                    selectedLinkedFiles.removeAll()
                    selectedOCFParents = [confidentlyLinkedParents[focusedOCFIndex].ocf.fileName]
                }
            }
        }
    }

    private func handleUpArrow() {
        guard !confidentlyLinkedParents.isEmpty else { return }

        // Ensure focusedOCFIndex is valid
        if focusedOCFIndex >= confidentlyLinkedParents.count {
            focusedOCFIndex = max(0, confidentlyLinkedParents.count - 1)
        }

        let currentOCF = confidentlyLinkedParents[focusedOCFIndex]
        let sortedChildren = sortedByTimecode(currentOCF.children)

        switch navigationContext {
        case .segmentList:
            // Currently focused on a segment
            guard let currentSegment = selectedLinkedFiles.first,
                  let segmentIndex = sortedChildren.firstIndex(where: { $0.segment.fileName == currentSegment }) else {
                return
            }

            if segmentIndex > 0 {
                // Move to previous segment in current OCF
                selectedLinkedFiles = [sortedChildren[segmentIndex - 1].segment.fileName]
            } else {
                // At first segment → move back to parent OCF card
                navigationContext = .ocfList
                selectedLinkedFiles.removeAll()
                selectedOCFParents = [currentOCF.ocf.fileName]
            }

        case .ocfList:
            // Currently focused on an OCF card
            if focusedOCFIndex > 0 {
                focusedOCFIndex -= 1
                let previousOCF = confidentlyLinkedParents[focusedOCFIndex]
                let previousSortedChildren = sortedByTimecode(previousOCF.children)
                let isExpanded = project.ocfCardExpansionState[previousOCF.ocf.fileName] ?? true

                if isExpanded && !previousSortedChildren.isEmpty {
                    // Previous OCF is expanded → jump to its last segment
                    navigationContext = .segmentList
                    selectedOCFParents = [previousOCF.ocf.fileName]
                    selectedLinkedFiles = [previousSortedChildren.last!.segment.fileName]
                } else {
                    // Previous OCF is collapsed → select it
                    selectedOCFParents = [previousOCF.ocf.fileName]
                }
            }
            // If already at first OCF, do nothing (stay at top)
        }
    }


    @ViewBuilder
    private var linkingResultsContent: some View {
        HStack(spacing: 0) {
            // Main Linked Results with List View
            VStack(alignment: .leading) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Linked Files (\(totalConfidentSegments) segments)")
                            .font(.headline)
                            .monospacedDigit()

                        Spacer()

                        // Action buttons
                        HStack(spacing: 12) {
                            if let performLinking = onPerformLinking {
                                Button("Run Auto-Linking") {
                                    performLinking()
                                }
                                .buttonStyle(CompressorButtonStyle(prominent: true))
                                .disabled(project.ocfFiles.isEmpty || project.segments.isEmpty)
                            }

                            Button("Render All") {
                                renderAll()
                            }
                            .buttonStyle(CompressorButtonStyle())
                            .disabled(!canRenderAll)

                            Button("Re-render Modified") {
                                renderModified()
                            }
                            .buttonStyle(CompressorButtonStyle())
                            .disabled(!canRenderModified)

                            if !confidentlyLinkedParents.isEmpty {
                                Group {
                                    Button("Select All") {
                                        selectedOCFParents = Set(confidentlyLinkedParents.map { $0.ocf.fileName })
                                    }
                                    .keyboardShortcut("a", modifiers: .command)

                                    Button("Clear Selection") {
                                        selectedOCFParents.removeAll()
                                    }
                                    .keyboardShortcut(.escape, modifiers: [])
                                    .opacity(selectedOCFParents.isEmpty ? 0 : 1)
                                    .disabled(selectedOCFParents.isEmpty)
                                }
                                .buttonStyle(CompressorButtonStyle())
                            }
                        }

                        // Show toggle button here when drawer is hidden
                        if !showUnmatchedDrawer {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showUnmatchedDrawer.toggle()
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "inset.filled.righthalf.rectangle")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Show Unmatched Items (\(totalUnmatchedItems))")
                            .padding(.trailing)
                        }
                    }

                    // Batch render progress indicator
                    if isProcessingBatchQueue {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .controlSize(.small)

                            let completed = totalInBatch - batchRenderQueue.count
                            Text("Batch rendering... (\(completed)/\(totalInBatch) completed)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                    }

                    // Status line with linking result summary
                    if let result = project.linkingResult {
                        HStack {
                            Text(result.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()

                // Use ScrollView for true card layout
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(confidentlyLinkedParents.enumerated()), id: \.element.ocf.fileName) { index, parent in
                            CompressorStyleOCFCard(
                                parent: parent,
                                ocfIndex: index,
                                project: project,
                                timelineVisualizationData: timelineVisualizationData,
                                selectedLinkedFiles: $selectedLinkedFiles,
                                selectedOCFParents: $selectedOCFParents,
                                focusedOCFIndex: $focusedOCFIndex,
                                navigationContext: $navigationContext,
                                projectManager: projectManager,
                                getSelectedParents: getSelectedParents,
                                allParents: confidentlyLinkedParents,
                                currentlyRenderingOCF: currentlyRenderingOCF
                            )
                            .contextMenu {
                                OCFParentContextMenu(
                                    parent: parent,
                                    project: project,
                                    projectManager: projectManager,
                                    selectedParents: getSelectedParents(),
                                    allParents: confidentlyLinkedParents
                                )
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(minWidth: 400)

            // Collapsible Unmatched Items Drawer
            if showUnmatchedDrawer {
                // Visual divider similar to Xcode
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)

                VStack(alignment: .leading) {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Unmatched Items")
                                .font(.headline)

                            Spacer()
                            
                            // Balance with some actions or info
                            HStack(spacing: 12) {
                                Text("(\(totalUnmatchedItems))")
                                    .font(.headline)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }

                            // Xcode-style drawer toggle button
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showUnmatchedDrawer.toggle()
                                }
                            } label: {
                                Image(
                                    systemName: showUnmatchedDrawer
                                        ? "inset.filled.righthalf.rectangle"
                                        : "inset.filled.righthalf.rectangle"
                                )
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(showUnmatchedDrawer ? "Hide Unmatched Items" : "Show Unmatched Items")
                            .padding(.trailing)
                        }
                        
                        // Status line for unmatched items
                        if totalUnmatchedItems > 0 {
                            HStack {
                                Text("Review these items before proceeding")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding()

                    List(selection: $selectedUnmatchedFiles) {
                        // Unmatched Segments (shown first - most important)
                        if let linkingResult = linkingResult,
                            !linkingResult.unmatchedSegments.isEmpty
                        {
                            Section("Unmatched Segments (\(linkingResult.unmatchedSegments.count))")
                            {
                                ForEach(linkingResult.unmatchedSegments, id: \.fileName) {
                                    segment in
                                    UnmatchedFileRowView(file: segment, type: .segment)
                                        .tag(segment.fileName)
                                }
                            }
                        }

                        // Unmatched OCF Files
                        if let linkingResult = linkingResult, !linkingResult.unmatchedOCFs.isEmpty {
                            Section {
                                ForEach(linkingResult.unmatchedOCFs, id: \.fileName) { ocf in
                                    UnmatchedFileRowView(file: ocf, type: .ocf)
                                        .tag(ocf.fileName)
                                }
                            } header: {
                                HStack {
                                    Text(
                                        "Unmatched OCF Files (\(linkingResult.unmatchedOCFs.count))"
                                    )
                                    .monospacedDigit()

                                    Spacer()

                                    Menu {
                                        Button(
                                            "Remove Unmatched OCF Files", systemImage: "trash"
                                        ) {
                                            removeUnmatchedOCFFiles()
                                        }
                                        .foregroundColor(.red)
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .menuOrder(.fixed)
                                    .fixedSize()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Low Confidence Matches
                        if !lowConfidenceSegments.isEmpty {
                            Section("Low Confidence Matches (\(lowConfidenceSegments.count))") {
                                ForEach(lowConfidenceSegments, id: \.segment.fileName) {
                                    linkedSegment in
                                    LowConfidenceSegmentRowView(linkedSegment: linkedSegment)
                                        .tag(linkedSegment.segment.fileName)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 300)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: - Unmatched File Removal

    private func removeUnmatchedOCFFiles() {
        guard let currentLinkingResult = linkingResult else { return }
        let fileNamesToRemove = currentLinkingResult.unmatchedOCFs.map { $0.fileName }

        // Remove from project files
        project.ocfFiles.removeAll { fileNamesToRemove.contains($0.fileName) }

        // Clean up related blank rush status
        for fileName in fileNamesToRemove {
            project.blankRushStatus.removeValue(forKey: fileName)
        }

        // Update the linking result to remove these from unmatched list (keep all linked data)
        let updatedUnmatchedOCFs = currentLinkingResult.unmatchedOCFs.filter {
            !fileNamesToRemove.contains($0.fileName)
        }

        let updatedLinkingResult = LinkingResult(
            ocfParents: currentLinkingResult.ocfParents,  // Keep all linked data
            unmatchedSegments: currentLinkingResult.unmatchedSegments,  // Keep unchanged
            unmatchedOCFs: updatedUnmatchedOCFs  // Remove the files we deleted
        )

        project.linkingResult = updatedLinkingResult
        project.updateModified()
        projectManager.saveProject(project)

        NSLog(
            "🗑️ Removed \(fileNamesToRemove.count) unmatched OCF file(s) from project: \(fileNamesToRemove.joined(separator: ", "))"
        )
    }
}

