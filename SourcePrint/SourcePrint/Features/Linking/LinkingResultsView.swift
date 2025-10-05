//
//  LinkingResultsView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import ProResWriterCore
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
fileprivate func formatLinkMethodBadges(_ linkMethod: String) -> [String] {
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
fileprivate func sortedByTimecode(_ segments: [LinkedSegment]) -> [LinkedSegment] {
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

struct OCFParentHeaderView: View {
    let parent: OCFParent
    let project: Project
    let timelineVisualization: TimelineVisualization?
    let selectedSegmentFileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(parent.ocf.fileName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack {
                    Text("\(parent.childCount) linked segments")
                        .monospacedDigit()
                    Text("•")
                    if let fps = parent.ocf.frameRate {
                        Text("\(fps.floatValue, specifier: "%.3f") fps")
                            .monospacedDigit()
                    }
                    if let startTC = parent.ocf.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                // Print Status Indicator
                if let printStatus = project.printStatus[parent.ocf.fileName] {
                    Label(printStatus.displayName, systemImage: printStatus.icon)
                        .font(.caption2)
                        .foregroundColor(printStatus.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(printStatus.color.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Label("Not Printed", systemImage: "minus.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }

                // Blank Rush Status Indicator
                if project.blankRushFileExists(for: parent.ocf.fileName) {
                    Label("Blank Rush", systemImage: "film.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Label("No Blank Rush", systemImage: "film")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)

        // Timeline visualization
        if let timelineData = timelineVisualization {
            TimelineChartView(
                visualizationData: timelineData,
                ocfFileName: parent.ocf.fileName,
                selectedSegmentFileName: selectedSegmentFileName
            )
        }
        }
    }
}

struct TreeLinkedSegmentRowView: View {
    let linkedSegment: LinkedSegment
    let isLast: Bool
    @ObservedObject var project: Project

    // Check if this is a VFX shot
    private var isVFXShot: Bool {
        linkedSegment.segment.isVFX
    }

    // Online/offline/updated status
    private var isOffline: Bool {
        project.offlineMediaFiles.contains(linkedSegment.segment.fileName)
    }

    private var modificationDate: Date? {
        project.segmentModificationDates[linkedSegment.segment.fileName]
    }

    var confidenceColor: Color {
        switch linkedSegment.linkConfidence {
        case .high: return AppTheme.success
        case .medium: return AppTheme.warning
        case .low: return AppTheme.error
        case .none: return .gray
        }
    }

    var confidenceIcon: String {
        switch linkedSegment.linkConfidence {
        case .high: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        case .none: return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: confidenceIcon)
                .foregroundColor(confidenceColor)
                .frame(width: 16)

            Image(systemName: "film")
                .foregroundColor(AppTheme.segmentColor)
                .frame(width: 16)

            // // VFX indicator
            // if isVFXShot {
            //     Image(systemName: "wand.and.stars")
            //         .foregroundColor(.purple)
            //         .frame(width: 16)
            // }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(linkedSegment.segment.fileName)
                        .font(.body)
                        .foregroundColor(isOffline ? .red : .primary)

                    // VFX badge
                    if isVFXShot {
                        Text("VFX")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }

                    // Online/Offline/Updated status badge
                    if isOffline {
                        HStack(spacing: 2) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.red)
                            Text("OFFLINE")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(3)
                    } else if let modDate = modificationDate {
                        HStack(spacing: 2) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.yellow)
                            Text("UPDATED")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.yellow)
                        .cornerRadius(3)
                    }
                }

                HStack {
                    HStack(spacing: 4) {
                        ForEach(formatLinkMethodBadges(linkedSegment.linkMethod), id: \.self) { badge in
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    if let startTC = linkedSegment.segment.sourceTimecode,
                       let endTC = linkedSegment.segment.endTimecode {
                        Text("•")
                        Text("\(startTC) - \(endTC)")
                            .monospacedDigit()
                    }
                    // Show modification date for updated files
                    if let modDate = modificationDate {
                        Text("•")
                        Text("Updated: \(formatDate(modDate))")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.leading, 20)
        .opacity(isOffline ? 0.6 : 1.0)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct UnmatchedFileRowView: View {
    let file: MediaFileInfo
    let type: MediaType

    enum MediaType {
        case ocf, segment
    }

    var body: some View {
        HStack {
            Image(systemName: type == .ocf ? "film.fill" : "film")
                .foregroundColor(type == .ocf ? AppTheme.ocfColor : AppTheme.segmentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.body)

                HStack {
                    if let fps = file.frameRate {
                        Text("\(fps.floatValue, specifier: "%.3f") fps")
                            .monospacedDigit()
                    }
                    if let startTC = file.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text("Unmatched")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
        }
    }
}

struct LowConfidenceSegmentRowView: View {
    let linkedSegment: LinkedSegment

    // Check if this is a VFX shot
    private var isVFXShot: Bool {
        linkedSegment.segment.isVFX
    }

    var body: some View {
        HStack {
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.red)
                .frame(width: 16)

            Image(systemName: "film")
                .foregroundColor(AppTheme.segmentColor)
                .frame(width: 16)

            // VFX indicator
            if isVFXShot {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(linkedSegment.segment.fileName)
                        .font(.body)

                    // VFX badge
                    if isVFXShot {
                        Text("VFX")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                }

                HStack {
                    HStack(spacing: 4) {
                        ForEach(formatLinkMethodBadges(linkedSegment.linkMethod), id: \.self) { badge in
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    if let startTC = linkedSegment.segment.sourceTimecode,
                       let endTC = linkedSegment.segment.endTimecode {
                        Text("•")
                        Text("\(startTC) - \(endTC)")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text("Needs Review")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .cornerRadius(4)
        }
    }
}

// Additional components for alternative linking displays
struct OCFParentRowView: View {
    let parent: OCFParent
    let project: Project
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading) {
            // OCF Parent Row
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: "film.fill")
                    .foregroundColor(AppTheme.ocfColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(parent.ocf.fileName)
                        .font(.body)
                        .fontWeight(.medium)

                    HStack {
                        Text("\(parent.childCount) linked segments")
                            .monospacedDigit()
                        Text("•")
                        if let fps = parent.ocf.frameRate {
                            Text("\(fps.floatValue, specifier: "%.3f") fps")
                                .monospacedDigit()
                        }
                        if let startTC = parent.ocf.sourceTimecode {
                            Text("•")
                            Text("TC: \(startTC)")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Children Segments (when expanded)
            if isExpanded && parent.hasChildren {
                ForEach(sortedByTimecode(parent.children), id: \.segment.fileName) { linkedSegment in
                    LinkedSegmentRowView(linkedSegment: linkedSegment)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct LinkedSegmentRowView: View {
    let linkedSegment: LinkedSegment

    // Check if this is a VFX shot
    private var isVFXShot: Bool {
        linkedSegment.segment.isVFX
    }

    var confidenceColor: Color {
        switch linkedSegment.linkConfidence {
        case .high: return AppTheme.success
        case .medium: return AppTheme.warning
        case .low: return AppTheme.error
        case .none: return .gray
        }
    }

    var confidenceIcon: String {
        switch linkedSegment.linkConfidence {
        case .high: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        case .none: return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: confidenceIcon)
                .foregroundColor(confidenceColor)
                .frame(width: 16)

            Image(systemName: "film")
                .foregroundColor(AppTheme.segmentColor)
                .frame(width: 16)

            // VFX indicator
            if isVFXShot {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(linkedSegment.segment.fileName)
                        .font(.body)

                    // VFX badge
                    if isVFXShot {
                        Text("VFX")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                }

                HStack {
                    HStack(spacing: 4) {
                        ForEach(formatLinkMethodBadges(linkedSegment.linkMethod), id: \.self) { badge in
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    if let startTC = linkedSegment.segment.sourceTimecode,
                       let endTC = linkedSegment.segment.endTimecode {
                        Text("•")
                        Text("\(startTC) - \(endTC)")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Context Menu

struct OCFParentContextMenu: View {
    let parent: OCFParent
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    let selectedParents: [OCFParent]
    let allParents: [OCFParent]
    
    // Determine which parents to operate on - selected parents if multiple are selected, otherwise just the clicked parent
    private var operatingParents: [OCFParent] {
        return selectedParents.count > 1 ? selectedParents : [parent]
    }
    
    private var isBlankRushReady: Bool {
        if operatingParents.count == 1 {
            return project.blankRushFileExists(for: parent.ocf.fileName)
        } else {
            // For multiple selection, check if ANY have blank rushes ready
            return operatingParents.contains { project.blankRushFileExists(for: $0.ocf.fileName) }
        }
    }
    
    private var isAlreadyInQueue: Bool {
        if operatingParents.count == 1 {
            return project.renderQueue.contains { $0.ocfFileName == parent.ocf.fileName && $0.status != .completed }
        } else {
            // For multiple selection, check if ALL are already in queue
            return operatingParents.allSatisfy { parent in
                project.renderQueue.contains { $0.ocfFileName == parent.ocf.fileName && $0.status != .completed }
            }
        }
    }
    
    private var eligibleParentsForQueue: [OCFParent] {
        return operatingParents.filter { parent in
            project.blankRushFileExists(for: parent.ocf.fileName) &&
            !project.renderQueue.contains { $0.ocfFileName == parent.ocf.fileName && $0.status != .completed }
        }
    }
    
    private var hasModifiedSegments: Bool {
        // Check if any segments for this OCF have been modified since last print
        guard let printStatus = project.printStatus[parent.ocf.fileName],
              case .printed(let lastPrintDate, _) = printStatus else {
            return false
        }
        
        for child in parent.children {
            let segmentFileName = child.segment.fileName
            if let fileModDate = getFileModificationDate(for: child.segment.url),
               fileModDate > lastPrintDate {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        Group {
            // Add to Render Queue
            Button(operatingParents.count > 1 ? "Add \(operatingParents.count) Items to Render Queue" : "Add to Render Queue") {
                addToRenderQueue()
            }
            .disabled(eligibleParentsForQueue.isEmpty)
            
            if eligibleParentsForQueue.count != operatingParents.count && operatingParents.count > 1 {
                Text("\(eligibleParentsForQueue.count)/\(operatingParents.count) items eligible")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Blank Rush Management
            if operatingParents.count == 1 {
                if project.blankRushFileExists(for: parent.ocf.fileName) {
                    Button("Regenerate Blank Rush", systemImage: "film.fill") {
                        regenerateBlankRush()
                    }
                }
            }

            // Only show print status actions for single item context menus
            if operatingParents.count == 1 {
                Divider()
                
                // Print status actions
                if let printStatus = project.printStatus[parent.ocf.fileName] {
                switch printStatus {
                case .printed:
                    if hasModifiedSegments {
                        Button("Mark for Re-print (Segments Modified)", systemImage: "exclamationmark.circle") {
                            project.printStatus[parent.ocf.fileName] = .needsReprint(
                                lastPrintDate: Date(),
                                reason: .segmentModified
                            )
                            projectManager.saveProject(project)
                        }
                    } else {
                        Button("Force Re-print", systemImage: "arrow.clockwise") {
                            project.printStatus[parent.ocf.fileName] = .needsReprint(
                                lastPrintDate: Date(),
                                reason: .manualRequest
                            )
                            projectManager.saveProject(project)
                        }
                    }
                    
                case .needsReprint:
                    Button("Clear Re-print Flag", systemImage: "checkmark.circle") {
                        // Find the last successful print date
                        if let lastSuccessfulPrint = project.printHistory
                            .filter({ $0.success && $0.outputURL.lastPathComponent.contains((parent.ocf.fileName as NSString).deletingPathExtension) })
                            .max(by: { $0.date < $1.date }) {
                            project.printStatus[parent.ocf.fileName] = .printed(date: lastSuccessfulPrint.date, outputURL: lastSuccessfulPrint.outputURL)
                        } else {
                            project.printStatus.removeValue(forKey: parent.ocf.fileName)
                        }
                        projectManager.saveProject(project)
                    }
                    
                case .notPrinted:
                    EmptyView()
                }
                }
            }
        }
    }
    
    private func addToRenderQueue() {
        let parentsToAdd = eligibleParentsForQueue
        var addedCount = 0

        for parent in parentsToAdd {
            let queueItem = RenderQueueItem(ocfFileName: parent.ocf.fileName)
            project.renderQueue.append(queueItem)
            addedCount += 1
        }

        projectManager.saveProject(project)

        if addedCount == 1 {
            NSLog("➕ Added \(parentsToAdd.first!.ocf.fileName) to render queue")
        } else {
            NSLog("➕ Added \(addedCount) items to render queue")
        }
    }

    private func regenerateBlankRush() {
        NSLog("🔄 Regenerating blank rush for \(parent.ocf.fileName)")

        // Mark as in progress
        project.blankRushStatus[parent.ocf.fileName] = .inProgress
        projectManager.saveProject(project)

        // Create single-file linking result for this OCF
        let singleOCFResult = LinkingResult(
            ocfParents: [parent],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )

        Task {
            let blankRushCreator = BlankRushIntermediate(projectDirectory: project.blankRushDirectory.path)

            // Create blank rush
            let results = await blankRushCreator.createBlankRushes(from: singleOCFResult) { clipName, current, total, fps in
                // No progress UI needed for context menu action
            }

            await MainActor.run {
                if let result = results.first {
                    if result.success {
                        project.blankRushStatus[result.originalOCF.fileName] = .completed(date: Date(), url: result.blankRushURL)
                        projectManager.saveProject(project)
                        NSLog("✅ Regenerated blank rush for \(parent.ocf.fileName): \(result.blankRushURL.lastPathComponent)")
                    } else {
                        let errorMessage = result.error ?? "Unknown error"
                        project.blankRushStatus[result.originalOCF.fileName] = .failed(error: errorMessage)
                        projectManager.saveProject(project)
                        NSLog("❌ Failed to regenerate blank rush for \(parent.ocf.fileName): \(errorMessage)")
                    }
                }
            }
        }
    }

    private func getFileModificationDate(for url: URL) -> Date? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            return nil
        }
    }
}

// MARK: - Compressor Style OCF Card

struct CompressorStyleOCFCard: View {
    let parent: OCFParent
    let ocfIndex: Int
    let project: Project
    let timelineVisualizationData: [String: TimelineVisualization]
    @Binding var selectedLinkedFiles: Set<String>
    @Binding var selectedOCFParents: Set<String>
    @Binding var focusedOCFIndex: Int
    @Binding var navigationContext: LinkingResultsView.NavigationContext
    let projectManager: ProjectManager
    let getSelectedParents: () -> [OCFParent]
    let allParents: [OCFParent]
    let currentlyRenderingOCF: String?  // Global lock to prevent concurrent rendering


    @State private var isExpanded: Bool = true  // Default to expanded
    @State private var isRendering = false
    @State private var renderProgress = ""
    @State private var renderStartTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var renderTimer: Timer?

    private var isSelected: Bool {
        selectedOCFParents.contains(parent.ocf.fileName)
    }

    private func handleCardSelection() {
        // Update navigation state
        focusedOCFIndex = ocfIndex
        navigationContext = .ocfList
        selectedLinkedFiles.removeAll()

        // Check if shift key is pressed for range selection
        let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
        let isShiftPressed = modifierFlags.contains(.shift)

        if isShiftPressed {
            handleRangeSelection()
        } else {
            // Simple toggle
            if selectedOCFParents.contains(parent.ocf.fileName) {
                selectedOCFParents.remove(parent.ocf.fileName)
            } else {
                selectedOCFParents.insert(parent.ocf.fileName)
            }
        }
    }

    private func handleRangeSelection() {
        // Find the last selected item to use as range start
        guard let lastSelectedFileName = selectedOCFParents.first,
              let lastIndex = allParents.firstIndex(where: { $0.ocf.fileName == lastSelectedFileName }),
              let currentIndex = allParents.firstIndex(where: { $0.ocf.fileName == parent.ocf.fileName }) else {
            // No previous selection, just select this one
            selectedOCFParents.insert(parent.ocf.fileName)
            return
        }

        let startIndex = min(lastIndex, currentIndex)
        let endIndex = max(lastIndex, currentIndex)

        // Select all items in the range
        for i in startIndex...endIndex {
            selectedOCFParents.insert(allParents[i].ocf.fileName)
        }
    }

    private func startRendering() {
        guard !isRendering else { return }

        // Check global rendering lock - only proceed if this card is the one that should render
        if let rendering = currentlyRenderingOCF, rendering != parent.ocf.fileName {
            NSLog("⏸️ Skipping %@ - another OCF is currently rendering (%@)", parent.ocf.fileName, rendering)
            return
        }

        // Check if blank rush exists
        let blankRushStatus = project.blankRushStatus[parent.ocf.fileName] ?? .notCreated

        switch blankRushStatus {
        case .completed(_, let blankRushURL):
            // Verify blank rush file actually exists on disk
            if FileManager.default.fileExists(atPath: blankRushURL.path) {
                // Blank rush exists - proceed directly to render
                beginRender(with: blankRushURL)
            } else {
                // Status says completed but file is missing - regenerate
                NSLog("⚠️ Blank rush file missing for \(parent.ocf.fileName) - regenerating")
                project.blankRushStatus[parent.ocf.fileName] = .notCreated
                // Don't save here - will save after blank rush creation completes
                startRendering() // Retry - will hit .notCreated case
            }

        case .notCreated:
            // No blank rush - create it first, then render
            NSLog("📝 No blank rush exists for \(parent.ocf.fileName) - creating automatically")
            isRendering = true
            renderStartTime = Date()
            elapsedTime = 0
            renderProgress = "Creating blank rush..."

            // Start timer
            renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
                if let startTime = renderStartTime {
                    elapsedTime = Date().timeIntervalSince(startTime)
                }
            }

            Task {
                if let blankRushURL = await generateBlankRushForOCF() {
                    // Blank rush created successfully - proceed to render
                    await MainActor.run {
                        renderProgress = "Blank rush ready - rendering..."
                    }
                    await renderOCF(blankRushURL: blankRushURL)
                } else {
                    // Blank rush creation failed
                    await MainActor.run {
                        stopRendering()
                        NSLog("❌ Failed to create blank rush for \(parent.ocf.fileName)")
                    }
                }
            }

        case .inProgress:
            // Check if blank rush file exists from previous incomplete creation
            let expectedURL = project.blankRushDirectory.appendingPathComponent("\(parent.ocf.fileName)_blank.mov")

            if FileManager.default.fileExists(atPath: expectedURL.path) {
                // File exists - verify it's a valid video file using MediaAnalyzer
                NSLog("🔍 Validating stuck .inProgress blank rush for \(parent.ocf.fileName)...")
                Task {
                    let isValid = await isValidBlankRush(at: expectedURL)

                    await MainActor.run {
                        if isValid {
                            // File is valid - mark as completed and use it
                            NSLog("✅ Found valid blank rush file for stuck .inProgress status: \(parent.ocf.fileName)")
                            project.blankRushStatus[parent.ocf.fileName] = .completed(date: Date(), url: expectedURL)
                            // Save will happen after render completes
                            beginRender(with: expectedURL)
                        } else {
                            // File is invalid/corrupted - reset and regenerate
                            NSLog("⚠️ Invalid blank rush file for .inProgress status - regenerating: \(parent.ocf.fileName)")
                            project.blankRushStatus[parent.ocf.fileName] = .notCreated
                            // Save will happen after blank rush creation completes
                            startRendering()
                        }
                    }
                }
            } else {
                // Status is .inProgress but file doesn't exist - reset to .notCreated
                NSLog("⚠️ Blank rush stuck in .inProgress but file missing for \(parent.ocf.fileName) - resetting")
                project.blankRushStatus[parent.ocf.fileName] = .notCreated
                // Save will happen after blank rush creation completes
                startRendering() // Retry - will hit .notCreated case
            }

        case .failed(let error):
            // Allow retry by resetting to .notCreated
            NSLog("⚠️ Previous blank rush creation failed for \(parent.ocf.fileName): \(error) - retrying")
            project.blankRushStatus[parent.ocf.fileName] = .notCreated
            // Save will happen after blank rush creation completes
            startRendering()
        }
    }

    /// Validate that a blank rush file is actually a valid, readable video file
    private func isValidBlankRush(at url: URL) async -> Bool {
        do {
            // Use MediaAnalyzer to verify it's a valid video file
            let _ = try await MediaAnalyzer().analyzeMediaFile(at: url, type: .gradedSegment)
            return true
        } catch {
            NSLog("⚠️ Blank rush validation failed for \(url.lastPathComponent): \(error)")
            return false
        }
    }

    private func beginRender(with blankRushURL: URL) {
        isRendering = true
        renderStartTime = Date()
        elapsedTime = 0
        renderProgress = "Rendering..."

        // Start timer
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            if let startTime = renderStartTime {
                elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        Task {
            await renderOCF(blankRushURL: blankRushURL)
        }
    }

    private func stopRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
        isRendering = false
        renderProgress = ""
        renderStartTime = nil
        elapsedTime = 0
    }

    @MainActor
    private func generateBlankRushForOCF() async -> URL? {
        renderProgress = "Creating blank rush..."

        // Mark as in progress
        project.blankRushStatus[parent.ocf.fileName] = .inProgress
        // Don't save here - status updates will be saved after completion

        // Create single-file linking result for this OCF
        let singleOCFResult = LinkingResult(
            ocfParents: [parent],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )

        let blankRushCreator = BlankRushIntermediate(projectDirectory: project.blankRushDirectory.path)

        // Create blank rush with progress callback
        let results = await blankRushCreator.createBlankRushes(from: singleOCFResult) { clipName, current, total, fps in
            await MainActor.run {
                self.renderProgress = "Creating blank rush... \(Int((current/total) * 100))%"
            }
        }

        // Process result
        if let result = results.first {
            if result.success {
                project.blankRushStatus[result.originalOCF.fileName] = .completed(date: Date(), url: result.blankRushURL)
                // Save will happen after render completes
                NSLog("✅ Created blank rush for \(parent.ocf.fileName): \(result.blankRushURL.lastPathComponent)")
                return result.blankRushURL
            } else {
                let errorMessage = result.error ?? "Unknown error"
                project.blankRushStatus[result.originalOCF.fileName] = .failed(error: errorMessage)
                // Save will happen when status is checked
                NSLog("❌ Failed to create blank rush for \(parent.ocf.fileName): \(errorMessage)")
                return nil
            }
        }

        return nil
    }

    @MainActor
    private func renderOCF(blankRushURL: URL) async {
        renderProgress = "Creating composition..."

        do {
            // Generate output filename
            let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
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
                        NSLog("⚠️ SMPTE calculation failed for \(segmentInfo.fileName): \(error)")
                        continue
                    }
                }
            }

            guard !ffmpegGradedSegments.isEmpty else {
                NSLog("❌ No valid FFmpeg graded segments for \(parent.ocf.fileName)")
                await MainActor.run {
                    stopRendering()
                }
                return
            }

            // Setup compositor settings
            let settings = FFmpegCompositorSettings(
                outputURL: outputURL,
                baseVideoURL: blankRushURL,
                gradedSegments: ffmpegGradedSegments,
                proResProfile: "4"
            )

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

            await MainActor.run {
                switch result {
                case .success(let finalOutputURL):
                    let printRecord = PrintRecord(
                        date: Date(),
                        outputURL: finalOutputURL,
                        segmentCount: ffmpegGradedSegments.count,
                        duration: compositionDuration,
                        success: true
                    )
                    project.addPrintRecord(printRecord)
                    project.printStatus[parent.ocf.fileName] = .printed(date: Date(), outputURL: finalOutputURL)

                    // Clear modification dates for printed segments
                    for child in parent.children {
                        if project.segmentModificationDates[child.segment.fileName] != nil {
                            project.segmentModificationDates.removeValue(forKey: child.segment.fileName)
                        }
                    }

                    projectManager.saveProject(project)
                    NSLog("✅ Composition completed: \(finalOutputURL.lastPathComponent)")

                case .failure(let error):
                    let printRecord = PrintRecord(
                        date: Date(),
                        outputURL: outputURL,
                        segmentCount: ffmpegGradedSegments.count,
                        duration: compositionDuration,
                        success: false
                    )
                    project.addPrintRecord(printRecord)
                    projectManager.saveProject(project)
                    NSLog("❌ Composition failed: \(error)")
                }

                stopRendering()
            }

        } catch {
            await MainActor.run {
                NSLog("❌ Print process error for \(parent.ocf.fileName): \(error)")
                stopRendering()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compressor-style header (title bar)
            HStack {
                // OCF filename as main title (clickable)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        // Save expansion state to project
                        project.ocfCardExpansionState[parent.ocf.fileName] = isExpanded
                        projectManager.saveProject(project)
                    }
                }) {
                    Text(parent.ocf.fileName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                    Spacer()

                    // Status indicators (from original header)
                    HStack(spacing: 8) {
                        // Print Status
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                if let printStatus = project.printStatus[parent.ocf.fileName] {
                                    Image(systemName: printStatus.icon)
                                        .foregroundColor(printStatus.color)
                                    Text(printStatus.displayName)
                                        .font(.caption)
                                        .foregroundColor(printStatus.color)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                    Text("Not Printed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Render State Display
                        if isRendering {
                            Button(action: {
                                stopRendering()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundColor(.red)
                                    Text(String(format: "%.1fs", elapsedTime))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: {
                                startRendering()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text("Render")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // Chevron indicator with fixed width and larger click area
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                                // Save expansion state to project
                                project.ocfCardExpansionState[parent.ocf.fileName] = isExpanded
                                projectManager.saveProject(project)
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.3) : Color.appBackgroundSecondary)
            .onTapGesture {
                handleCardSelection()
            }

            // Render Progress Bar (shown when rendering, whether expanded or collapsed)
            if isRendering {
                VStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    Text(renderProgress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.appBackgroundSecondary)
            }

            // Card body (expandable content)
            if isExpanded {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Timeline
                        if let timelineData = timelineVisualizationData[parent.ocf.fileName] {
                            TimelineChartView(
                                visualizationData: timelineData,
                                ocfFileName: parent.ocf.fileName,
                                selectedSegmentFileName: selectedLinkedFiles.first
                            )
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }

                        // Render Log Section
                        RenderLogSection(
                            project: project,
                            ocfFileName: parent.ocf.fileName
                        )

                        // Linked segments container - keyboard navigation handled at LinkingResultsView level
                        VStack(spacing: 0) {
                            ForEach(Array(sortedByTimecode(parent.children).enumerated()), id: \.element.segment.fileName) { index, linkedSegment in
                                TreeLinkedSegmentRowView(
                                    linkedSegment: linkedSegment,
                                    isLast: linkedSegment.segment.fileName
                                        == sortedByTimecode(parent.children).last?.segment.fileName,
                                    project: project
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .onTapGesture {
                                    // Update navigation state
                                    focusedOCFIndex = ocfIndex
                                    navigationContext = .segmentList
                                    selectedLinkedFiles = [linkedSegment.segment.fileName]
                                    selectedOCFParents = [parent.ocf.fileName]
                                }
                                .background(
                                    selectedLinkedFiles.contains(linkedSegment.segment.fileName)
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                                )
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.appBackgroundTertiary.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 0)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.appBackgroundSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onReceive(NotificationCenter.default.publisher(for: .expandSelectedCards)) { _ in
            if isSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
                // Save expansion state to project
                project.ocfCardExpansionState[parent.ocf.fileName] = true
                projectManager.saveProject(project)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseSelectedCards)) { _ in
            if isSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
                // Save expansion state to project
                project.ocfCardExpansionState[parent.ocf.fileName] = false
                projectManager.saveProject(project)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseAllCards)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = false
            }
            // Update state but don't save (batch collapse shouldn't trigger multiple saves)
            project.ocfCardExpansionState[parent.ocf.fileName] = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .renderOCF)) { notification in
            if let userInfo = notification.userInfo,
               let ocfFileName = userInfo["ocfFileName"] as? String,
               ocfFileName == parent.ocf.fileName {
                startRendering()
            }
        }
        .onAppear {
            // Initialize expansion state from project (default to true if not set)
            isExpanded = project.ocfCardExpansionState[parent.ocf.fileName] ?? true
        }
    }
}

// MARK: - Render Log Section

struct RenderLogSection: View {
    @ObservedObject var project: Project
    let ocfFileName: String

    // Filter print history for this specific OCF
    private var relevantPrintHistory: [PrintRecord] {
        let baseName = (ocfFileName as NSString).deletingPathExtension
        return project.printHistory.filter { record in
            record.outputURL.lastPathComponent.contains(baseName)
        }.sorted { $0.date > $1.date } // Most recent first
    }

    private var mostRecentPrint: PrintRecord? {
        relevantPrintHistory.first
    }

    private var blankRushStatus: BlankRushStatus {
        project.blankRushStatus[ocfFileName] ?? .notCreated
    }

    // Actual status verified against file system
    private var actualBlankRushStatus: BlankRushStatus {
        let storedStatus = project.blankRushStatus[ocfFileName] ?? .notCreated

        // Verify file existence for "completed" status
        if case .completed(_, let url) = storedStatus {
            if !FileManager.default.fileExists(atPath: url.path) {
                // File is missing - return .notCreated instead
                return .notCreated
            }
        }

        return storedStatus
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Blank Rush Status Row
                HStack(spacing: 12) {
                    Label {
                        Text("Blank Rush")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "film.fill")
                            .foregroundColor(blankRushStatusColor)
                    }

                    Spacer()

                    Text(blankRushStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if case .completed(_, let url) = actualBlankRushStatus {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            Image(systemName: "play.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open blank rush")
                    }
                }

                Divider()

                // Print History Row
                HStack(spacing: 12) {
                    Label {
                        Text("Print Status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: printStatusIcon)
                            .foregroundColor(printStatusColor)
                    }

                    Spacer()

                    if let print = mostRecentPrint {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(print.success ? "Completed" : "Failed")
                                    .font(.caption)
                                    .foregroundColor(print.success ? .green : .red)

                                Text(RelativeDateTimeFormatter.shared.localizedString(for: print.date, relativeTo: Date()))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(String(format: "%.1fs • %d segments", print.duration, print.segmentCount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        if print.success {
                            Button(action: {
                                showInFinder(url: print.outputURL)
                            }) {
                                Image(systemName: "folder")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                        }
                    } else {
                        Text("Never printed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Render Pipeline", systemImage: "gearshape.2")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helper Properties

    private var blankRushStatusColor: Color {
        switch actualBlankRushStatus {
        case .completed: return Color.green.opacity(0.7)
        case .inProgress: return .yellow
        case .failed: return .red
        case .notCreated: return .secondary
        }
    }

    private var blankRushStatusText: String {
        switch actualBlankRushStatus {
        case .completed(let date, _):
            return "Created \(RelativeDateTimeFormatter.shared.localizedString(for: date, relativeTo: Date()))"
        case .inProgress:
            return "In Progress..."
        case .failed(let error):
            return "Failed: \(error)"
        case .notCreated:
            return "Not Created"
        }
    }

    private var printStatusIcon: String {
        if let print = mostRecentPrint {
            return print.success ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        return "circle"
    }

    private var printStatusColor: Color {
        if let print = mostRecentPrint {
            return print.success ? .green : .red
        }
        return .secondary
    }

    // MARK: - Actions

    private func showInFinder(url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}

// MARK: - Relative Date Formatter

extension RelativeDateTimeFormatter {
    static let shared: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
