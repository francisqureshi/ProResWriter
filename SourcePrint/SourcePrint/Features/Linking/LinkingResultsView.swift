//
//  LinkingResultsView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import ProResWriterCore
import SwiftUI

extension Notification.Name {
    static let expandSelectedCards = Notification.Name("expandSelectedCards")
    static let collapseSelectedCards = Notification.Name("collapseSelectedCards")
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
    
    // Helper to get selected OCF parents for context menu batch operations
    private func getSelectedParents() -> [OCFParent] {
        return confidentlyLinkedParents.filter { parent in
            selectedOCFParents.contains(parent.ocf.fileName)
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
                            
                            if let generateBlankRushes = onGenerateBlankRushes {
                                Button("Generate Blank Rushes") {
                                    generateBlankRushes()
                                }
                                .buttonStyle(CompressorButtonStyle())
                                .disabled(true) // Always disabled when no linking results
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
    }

    private func expandSelectedCards() {
        // This will be handled by each individual card
        NotificationCenter.default.post(name: .expandSelectedCards, object: nil)
    }

    private func collapseSelectedCards() {
        // This will be handled by each individual card
        NotificationCenter.default.post(name: .collapseSelectedCards, object: nil)
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

                            if let generateBlankRushes = onGenerateBlankRushes {
                                Button("Generate Blank Rushes") {
                                    generateBlankRushes()
                                }
                                .buttonStyle(CompressorButtonStyle())
                                .disabled(!project.readyForBlankRush)
                            }

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
                    LazyVStack(spacing: 12) {
                        ForEach(confidentlyLinkedParents, id: \.ocf.fileName) { parent in
                            CompressorStyleOCFCard(
                                parent: parent,
                                project: project,
                                timelineVisualizationData: timelineVisualizationData,
                                selectedLinkedFiles: $selectedLinkedFiles,
                                selectedOCFParents: $selectedOCFParents,
                                projectManager: projectManager,
                                getSelectedParents: getSelectedParents,
                                allParents: confidentlyLinkedParents
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
                    Text(linkedSegment.linkMethod)
                    Text("•")
                    Text("\(linkedSegment.linkConfidence)".lowercased())
                    if let startTC = linkedSegment.segment.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
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
                    Text(linkedSegment.linkMethod)
                    Text("•")
                    Text("low confidence")
                    if let startTC = linkedSegment.segment.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
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
                ForEach(parent.children, id: \.segment.fileName) { linkedSegment in
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
                    Text(linkedSegment.linkMethod)
                    Text("•")
                    Text("\(linkedSegment.linkConfidence)".lowercased())
                    if let startTC = linkedSegment.segment.sourceTimecode {
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
    let project: Project
    let timelineVisualizationData: [String: TimelineVisualization]
    @Binding var selectedLinkedFiles: Set<String>
    @Binding var selectedOCFParents: Set<String>
    let projectManager: ProjectManager
    let getSelectedParents: () -> [OCFParent]
    let allParents: [OCFParent]

    @State private var isExpanded: Bool = true  // Default to expanded

    private var isSelected: Bool {
        selectedOCFParents.contains(parent.ocf.fileName)
    }

    private func navigateToNextSegment(in children: [LinkedSegment]) {
        guard !children.isEmpty else { return }

        if let currentSelected = selectedLinkedFiles.first,
           let currentIndex = children.firstIndex(where: { $0.segment.fileName == currentSelected }) {
            // Move to next segment
            if currentIndex < children.count - 1 {
                selectedLinkedFiles = [children[currentIndex + 1].segment.fileName]
            }
        } else {
            // No selection, select first segment
            selectedLinkedFiles = [children[0].segment.fileName]
        }
    }

    private func navigateToPreviousSegment(in children: [LinkedSegment]) {
        guard !children.isEmpty else { return }

        if let currentSelected = selectedLinkedFiles.first,
           let currentIndex = children.firstIndex(where: { $0.segment.fileName == currentSelected }) {
            // Move to previous segment
            if currentIndex > 0 {
                selectedLinkedFiles = [children[currentIndex - 1].segment.fileName]
            }
        } else {
            // No selection, select last segment
            selectedLinkedFiles = [children.last!.segment.fileName]
        }
    }

    private func handleCardSelection() {
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

                        // Blank Rush Status
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                if project.blankRushFileExists(for: parent.ocf.fileName) {
                                    Image(systemName: "film.fill")
                                        .foregroundColor(.green)
                                    Text("Blank Rush")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "film")
                                        .foregroundColor(.secondary)
                                    Text("No Blank Rush")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

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
            .background(isSelected ? Color.accentColor : Color.appBackgroundSecondary)
            .onTapGesture {
                handleCardSelection()
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

                        // Linked segments container with unified keyboard navigation
                        VStack(spacing: 0) {
                            ForEach(Array(parent.children.enumerated()), id: \.element.segment.fileName) { index, linkedSegment in
                                TreeLinkedSegmentRowView(
                                    linkedSegment: linkedSegment,
                                    isLast: linkedSegment.segment.fileName
                                        == parent.children.last?.segment.fileName,
                                    project: project
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .onTapGesture {
                                    selectedLinkedFiles = [linkedSegment.segment.fileName]
                                }
                                .background(
                                    selectedLinkedFiles.contains(linkedSegment.segment.fileName)
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                                )
                            }
                        }
                        .focusable()
                        .focusEffectDisabled()
                        .onKeyPress(.downArrow) {
                            navigateToNextSegment(in: parent.children)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            navigateToPreviousSegment(in: parent.children)
                            return .handled
                        }
                    }
                    .padding(8)
                    .background(Color.appBackgroundTertiary.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 0)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .background(isSelected ? Color.accentColor : Color.appBackgroundSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onReceive(NotificationCenter.default.publisher(for: .expandSelectedCards)) { _ in
            if isSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseSelectedCards)) { _ in
            if isSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
        .onAppear {
            // Initialize expansion state from project (default to true if not set)
            isExpanded = project.ocfCardExpansionState[parent.ocf.fileName] ?? true
        }
    }
}
