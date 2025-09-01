//
//  LinkingResultsView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct LinkingResultsView: View {
    @ObservedObject var project: Project
    @EnvironmentObject var projectManager: ProjectManager
    
    // Use the project's current linking result instead of a cached copy
    private var linkingResult: LinkingResult? {
        project.linkingResult
    }
    @State private var selectedLinkedFiles: Set<String> = []
    @State private var selectedUnmatchedFiles: Set<String> = []
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
        return linkingResult.unmatchedOCFs.count + 
               linkingResult.unmatchedSegments.count + 
               lowConfidenceSegments.count
    }
    
    var body: some View {
        Group {
            if linkingResult == nil {
                VStack {
                    Image(systemName: "link.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No linking results available")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Files were removed. Run auto-linking again to see updated results.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                linkingResultsContent
            }
        }
    }
    
    @ViewBuilder
    private var linkingResultsContent: some View {
        HStack(spacing: 0) {
                // Confidently Linked OCF Parents and Children
                VStack(alignment: .leading) {
                    HStack {
                        Text("Linked Files (\(totalConfidentSegments) segments)")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Spacer()
                        
                        // Show toggle button here when drawer is hidden
                        if !showUnmatchedDrawer {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showUnmatchedDrawer.toggle()
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    // Text("\(totalUnmatchedItems)")
                                    //     .font(.caption2)
                                    //     .foregroundColor(.white)
                                    Image(systemName: "inset.filled.righthalf.rectangle")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                                // .padding(.horizontal, 8)
                                // .padding(.vertical, 3)
                                // .background(Color.gray.opacity(0.7))
                                // .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Show Unmatched Items (\(totalUnmatchedItems))")
                            .padding(.trailing)
                        }
                    }
                
                List(selection: $selectedLinkedFiles) {
                    ForEach(confidentlyLinkedParents, id: \.ocf.fileName) { parent in
                        Section {
                            // Individual segments are selectable with tree indentation
                            ForEach(Array(parent.children.enumerated()), id: \.element.segment.fileName) { index, linkedSegment in
                                let isLast = index == parent.children.count - 1
                                TreeLinkedSegmentRowView(
                                    linkedSegment: linkedSegment, 
                                    isLast: isLast
                                )
                                .tag(linkedSegment.segment.fileName)
                            }
                        } header: {
                            OCFParentHeaderView(parent: parent, project: project)
                                .tag(parent.ocf.fileName)
                        }
                    }
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
                    HStack {
                        Text("Unmatched Items")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Spacer()
                        
                        // Xcode-style drawer toggle button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showUnmatchedDrawer.toggle()
                            }
                        } label: {
                            Image(systemName: showUnmatchedDrawer ? "inset.filled.righthalf.rectangle" : "inset.filled.righthalf.rectangle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showUnmatchedDrawer ? "Hide Unmatched Items" : "Show Unmatched Items")
                        .padding(.trailing)
                    }
                    
                    List(selection: $selectedUnmatchedFiles) {
                        if let linkingResult = linkingResult, !linkingResult.unmatchedOCFs.isEmpty {
                            Section {
                                ForEach(linkingResult.unmatchedOCFs, id: \.fileName) { ocf in
                                    UnmatchedFileRowView(file: ocf, type: .ocf)
                                        .tag(ocf.fileName)
                                }
                                
                                // Remove unmatched OCF files button
                                HStack {
                                    Spacer()
                                    Button("Remove Unmatched OCF Files from Project") {
                                        removeUnmatchedOCFFiles()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            } header: {
                                Text("Unmatched OCF Files (\(linkingResult.unmatchedOCFs.count))")
                            }
                        }
                        
                        if let linkingResult = linkingResult, !linkingResult.unmatchedSegments.isEmpty {
                            Section("Unmatched Segments (\(linkingResult.unmatchedSegments.count))") {
                                ForEach(linkingResult.unmatchedSegments, id: \.fileName) { segment in
                                    UnmatchedFileRowView(file: segment, type: .segment)
                                        .tag(segment.fileName)
                                }
                            }
                        }
                        
                        if !lowConfidenceSegments.isEmpty {
                            Section("Low Confidence Matches (\(lowConfidenceSegments.count))") {
                                ForEach(lowConfidenceSegments, id: \.segment.fileName) { linkedSegment in
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
        let updatedUnmatchedOCFs = currentLinkingResult.unmatchedOCFs.filter { !fileNamesToRemove.contains($0.fileName) }
        
        let updatedLinkingResult = LinkingResult(
            ocfParents: currentLinkingResult.ocfParents, // Keep all linked data
            unmatchedSegments: currentLinkingResult.unmatchedSegments, // Keep unchanged
            unmatchedOCFs: updatedUnmatchedOCFs // Remove the files we deleted
        )
        
        project.linkingResult = updatedLinkingResult
        project.updateModified()
        projectManager.saveProject(project)
        
        NSLog("🗑️ Removed \(fileNamesToRemove.count) unmatched OCF file(s) from project: \(fileNamesToRemove.joined(separator: ", "))")
    }
}

struct OCFParentHeaderView: View {
    let parent: OCFParent
    let project: Project
    
    var body: some View {
        HStack {
            Image(systemName: "camera")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(parent.ocf.fileName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                HStack {
                    Text("\(parent.childCount) linked segments")
                    Text("•")
                    if let fps = parent.ocf.frameRate {
                        Text("\(fps, specifier: "%.3f") fps")
                    }
                    if let startTC = parent.ocf.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Blank Rush Status Indicator
            if project.blankRushFileExists(for: parent.ocf.fileName) {
                Label("Blank Rush", systemImage: "film.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TreeLinkedSegmentRowView: View {
    let linkedSegment: LinkedSegment
    let isLast: Bool
    
    var confidenceColor: Color {
        switch linkedSegment.linkConfidence {
        case .high: return .green
        case .medium: return .orange  
        case .low: return .red
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
            
            Image(systemName: "scissors")
                .foregroundColor(.orange)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(linkedSegment.segment.fileName)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    Text(linkedSegment.linkMethod)
                    Text("•")
                    Text("\(linkedSegment.linkConfidence)".lowercased())
                    if let startTC = linkedSegment.segment.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.leading, 20)
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
            Image(systemName: type == .ocf ? "camera" : "scissors")
                .foregroundColor(type == .ocf ? .blue : .orange)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    if let fps = file.frameRate {
                        Text("\(fps, specifier: "%.3f") fps")
                    }
                    if let startTC = file.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
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
    
    var body: some View {
        HStack {
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.red)
                .frame(width: 16)
            
            Image(systemName: "scissors")
                .foregroundColor(.orange)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(linkedSegment.segment.fileName)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    Text(linkedSegment.linkMethod)
                    Text("•")
                    Text("low confidence")
                    if let startTC = linkedSegment.segment.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
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
                
                Image(systemName: "camera")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(parent.ocf.fileName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("\(parent.childCount) linked segments")
                        Text("•")
                        if let fps = parent.ocf.frameRate {
                            Text("\(fps, specifier: "%.3f") fps")
                        }
                        if let startTC = parent.ocf.sourceTimecode {
                            Text("•")
                            Text("TC: \(startTC)")
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
    
    var confidenceColor: Color {
        switch linkedSegment.linkConfidence {
        case .high: return .green
        case .medium: return .orange  
        case .low: return .red
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
            
            Image(systemName: "scissors")
                .foregroundColor(.orange)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(linkedSegment.segment.fileName)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    Text(linkedSegment.linkMethod)
                    Text("•")
                    Text("\(linkedSegment.linkConfidence)".lowercased())
                    if let startTC = linkedSegment.segment.sourceTimecode {
                        Text("•")
                        Text("TC: \(startTC)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}
