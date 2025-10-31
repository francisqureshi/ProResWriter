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

    // Render queue manager (from SourcePrintCore)
    @StateObject private var renderQueueManager = RenderQueueManager()

    // Computed property to track which OCF is currently rendering
    private var currentlyRenderingOCF: String? {
        renderQueueManager.currentItem?.ocfFileName
    }

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

    // Batch render functions - uses RenderQueueManager from SourcePrintCore

    private func renderAll() {
        let ocfsToRender = confidentlyLinkedParents.filter { parent in
            !project.offlineMediaFiles.contains(parent.ocf.fileName)
        }

        NSLog("🎬 Starting batch render for %d OCFs", ocfsToRender.count)

        renderQueueManager.addToQueue(ocfsToRender)
        renderQueueManager.startProcessing()
    }

    private func renderModified() {
        let modifiedOCFs = confidentlyLinkedParents.filter { parent in
            parent.children.contains { child in
                project.segmentModificationDates[child.segment.fileName] != nil
            }
        }

        NSLog("🔄 Starting batch render for %d modified OCFs", modifiedOCFs.count)

        renderQueueManager.addToQueue(modifiedOCFs)
        renderQueueManager.startProcessing()
    }

    private func renderSingle(parent: OCFParent) {
        NSLog("🎬 Starting single render for: %@", parent.ocf.fileName)
        renderQueueManager.addToQueue([parent])
        renderQueueManager.startProcessing()
    }

    // Render queue state is observed automatically via @StateObject
    // SwiftUI will react to changes in renderQueueManager's @Published properties

    // MARK: - Project Status Updates

    private func handleRenderCompleted(_ result: RenderResult, projectManager: ProjectManager?) {
        guard let projectManager = projectManager else { return }

        if result.success {
            // Update blank rush status
            if let blankRushURL = result.blankRushURL {
                project.blankRushStatus[result.ocfFileName] = .completed(date: Date(), url: blankRushURL)
            }

            // Update print status
            if let outputURL = result.outputURL {
                project.printStatus[result.ocfFileName] = .printed(date: Date(), outputURL: outputURL)
            }

            // Clear modification dates for printed segments
            if let parent = confidentlyLinkedParents.first(where: { $0.ocf.fileName == result.ocfFileName }) {
                for child in parent.children {
                    project.segmentModificationDates.removeValue(forKey: child.segment.fileName)
                }
            }

            // Add print record
            let printRecord = PrintRecord(
                date: Date(),
                outputURL: result.outputURL ?? project.outputDirectory.appendingPathComponent(result.ocfFileName),
                segmentCount: result.segmentCount,
                duration: result.duration,
                success: true
            )
            project.addPrintRecord(printRecord)

            NSLog("✅ Updated project status for: \(result.ocfFileName)")
        } else {
            // Record failed render
            let printRecord = PrintRecord(
                date: Date(),
                outputURL: project.outputDirectory.appendingPathComponent(result.ocfFileName),
                segmentCount: result.segmentCount,
                duration: result.duration,
                success: false
            )
            project.addPrintRecord(printRecord)

            NSLog("❌ Recorded failed render for: \(result.ocfFileName)")
        }

        // Save project
        projectManager.saveProject(project)
    }

    // NOTE: Old batch render functions removed - now handled by RenderQueueManager
    // The following functions have been extracted to SourcePrintCore:
    // - processBatchRenderQueue() -> RenderQueueManager.startProcessing()
    // - processOCFInQueue() -> Handled by card's RenderService
    // - createBlankRushForOCF() -> RenderService.generateBlankRush()
    // - renderOCFInQueue() -> RenderService.composeVideo()

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
        .onAppear {
            // Configure RenderQueueManager with project directories
            let configuration = RenderConfiguration(
                blankRushDirectory: project.blankRushDirectory,
                outputDirectory: project.outputDirectory,
                proResProfile: "4"
            )
            renderQueueManager.configure(with: configuration)
        }
        .onChange(of: renderQueueManager.lastCompletedResult) { _, result in
            // Update project status when a render completes
            guard let result = result else { return }

            handleRenderCompleted(result, projectManager: projectManager)
            NSLog("📊 Queue progress: \(renderQueueManager.completedCount) completed, \(renderQueueManager.failedCount) failed")
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
                    if renderQueueManager.isProcessing {
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .controlSize(.small)

                                let status = renderQueueManager.getStatus()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Batch rendering... (\(status.completedItems)/\(status.totalItems) completed)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    // Show current item progress
                                    if let currentItem = renderQueueManager.currentItem {
                                        Text("\(currentItem.ocfFileName): \(currentItem.progress)")
                                            .font(.caption)
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                }
                            }
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
                                currentlyRenderingOCF: currentlyRenderingOCF,
                                renderProgress: renderQueueManager.currentItem?.ocfFileName == parent.ocf.fileName ? renderQueueManager.currentItem?.progress : nil,
                                onRenderSingle: {
                                    renderSingle(parent: parent)
                                }
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

