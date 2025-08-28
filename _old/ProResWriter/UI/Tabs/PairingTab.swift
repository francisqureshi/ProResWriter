//
//  PairingTab.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct PairingTab: View {
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    
    @State private var isLinking = false
    @State private var showingConfidenceFilter = false
    @State private var confidenceFilter: ConfidenceFilter = .all
    
    var body: some View {
        VStack(spacing: 0) {
            // Pairing Controls
            PairingControlsView(
                project: project,
                projectManager: projectManager,
                isLinking: $isLinking,
                confidenceFilter: $confidenceFilter
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main Content
            if isLinking {
                LinkingProgressView()
            } else if let linkingResult = project.linkingResult {
                PairingResultsView(
                    linkingResult: linkingResult,
                    project: project,
                    confidenceFilter: confidenceFilter
                )
            } else {
                PairingSetupView(
                    project: project,
                    onStartLinking: {
                        performLinking()
                    }
                )
            }
        }
    }
    
    private func performLinking() {
        isLinking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            projectManager.performLinking(for: project)
            
            DispatchQueue.main.async {
                isLinking = false
            }
        }
    }
}

// MARK: - Controls

struct PairingControlsView: View {
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    @Binding var isLinking: Bool
    @Binding var confidenceFilter: ConfidenceFilter
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OCF-Segment Pairing")
                    .font(.headline)
                
                if let linkingResult = project.linkingResult {
                    HStack(spacing: 16) {
                        Label("\(linkingResult.totalLinkedSegments) linked", systemImage: "link")
                            .foregroundColor(.green)
                        
                        Label("\(linkingResult.unmatchedSegments.count) unmatched", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        
                        Label("\(linkingResult.unmatchedOCFs.count) unused OCF", systemImage: "folder")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Confidence Filter
                if project.linkingResult != nil {
                    Picker("Filter", selection: $confidenceFilter) {
                        ForEach(ConfidenceFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Re-run Linking Button
                Button(isLinking ? "Linking..." : "Run Auto-Pairing") {
                    performLinking()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLinking || project.ocfFiles.isEmpty || project.segments.isEmpty)
            }
        }
    }
    
    private func performLinking() {
        isLinking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            projectManager.performLinking(for: project)
            
            DispatchQueue.main.async {
                isLinking = false
            }
        }
    }
}

// MARK: - Setup View

struct PairingSetupView: View {
    @ObservedObject var project: Project
    let onStartLinking: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Ready to Pair Media")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("ProResWriter will automatically match your graded segments with their original camera files using:")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                PairingFeatureRow(
                    icon: "textformat",
                    title: "Filename Pattern Matching",
                    description: "Match segments to OCF using consistent naming"
                )
                
                PairingFeatureRow(
                    icon: "clock",
                    title: "Timecode Range Validation",
                    description: "Verify segments fit within OCF timecode ranges"
                )
                
                PairingFeatureRow(
                    icon: "viewfinder",
                    title: "Technical Specification Matching",
                    description: "Compare resolution, frame rate, and format details"
                )
                
                PairingFeatureRow(
                    icon: "target",
                    title: "Confidence Scoring",
                    description: "Rate match quality for manual review"
                )
            }
            .padding(.horizontal, 40)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Current Project:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Label("\(project.ocfFiles.count) OCF files", systemImage: "camera")
                        Label("\(project.segments.count) segments", systemImage: "film")
                    }
                    .font(.caption)
                }
                
                Spacer()
                
                Button("Start Auto-Pairing") {
                    onStartLinking()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(project.ocfFiles.isEmpty || project.segments.isEmpty)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PairingFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Results View

struct PairingResultsView: View {
    let linkingResult: LinkingResult
    @ObservedObject var project: Project
    let confidenceFilter: ConfidenceFilter
    
    var body: some View {
        HSplitView {
            // Matched Pairs
            VStack(alignment: .leading, spacing: 0) {
                Text("Matched Pairs")
                    .font(.headline)
                    .padding()
                
                Divider()
                
                List {
                    ForEach(filteredParents, id: \.ocf.fileName) { parent in
                        MatchedPairRow(parent: parent, project: project)
                    }
                }
                .listStyle(.plain)
            }
            
            // Unmatched Items
            VStack(alignment: .leading, spacing: 0) {
                Text("Unmatched Items")
                    .font(.headline)
                    .padding()
                
                Divider()
                
                List {
                    if !linkingResult.unmatchedSegments.isEmpty {
                        Section("Unmatched Segments") {
                            ForEach(linkingResult.unmatchedSegments, id: \.fileName) { segment in
                                UnmatchedSegmentRow(segment: segment)
                            }
                        }
                    }
                    
                    if !linkingResult.unmatchedOCFs.isEmpty {
                        Section("Unused OCF Files") {
                            ForEach(linkingResult.unmatchedOCFs, id: \.fileName) { ocf in
                                UnmatchedOCFRow(ocf: ocf)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var filteredParents: [OCFParent] {
        linkingResult.parentsWithChildren.filter { parent in
            confidenceFilter.shouldInclude(parent: parent)
        }
    }
}

// MARK: - Row Views

struct MatchedPairRow: View {
    let parent: OCFParent
    @ObservedObject var project: Project
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // OCF Parent Header
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                // Blank Rush Status
                let status = project.blankRushStatus[parent.ocf.fileName] ?? .notCreated
                Text(status.statusIcon)
                
                Text(parent.ocf.fileName)
                    .font(.headline)
                
                Spacer()
                
                Text("\(parent.childCount) segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Child Segments (when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(parent.children, id: \.segment.fileName) { child in
                        HStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 20)
                            
                            Text(confidenceIcon(for: child.linkConfidence))
                                .font(.caption)
                            
                            Text(child.segment.fileName)
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Text(child.linkConfidence.description)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(confidenceColor(for: child.linkConfidence).opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func confidenceIcon(for confidence: LinkConfidence) -> String {
        switch confidence {
        case .high: return "🟢"
        case .medium: return "🟡"
        case .low: return "🔴"
        }
    }
    
    private func confidenceColor(for confidence: LinkConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

struct UnmatchedSegmentRow: View {
    let segment: MediaFileInfo
    
    var body: some View {
        HStack {
            Image(systemName: "film.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.fileName)
                    .font(.headline)
                
                if let timecode = segment.sourceTimecode {
                    Text("TC: \(timecode)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct UnmatchedOCFRow: View {
    let ocf: MediaFileInfo
    
    var body: some View {
        HStack {
            Image(systemName: "camera.fill")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(ocf.fileName)
                    .font(.headline)
                
                if let timecode = ocf.sourceTimecode {
                    Text("TC: \(timecode)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Progress View

struct LinkingProgressView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analyzing Media Relationships...")
                .font(.headline)
            
            Text("Comparing filenames, timecodes, and technical specifications")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Types

enum ConfidenceFilter: String, CaseIterable {
    case all = "all"
    case highOnly = "high"
    case needsReview = "review"
    
    var title: String {
        switch self {
        case .all: return "All Matches"
        case .highOnly: return "High Confidence Only"
        case .needsReview: return "Needs Review"
        }
    }
    
    func shouldInclude(parent: OCFParent) -> Bool {
        switch self {
        case .all:
            return true
        case .highOnly:
            return parent.children.allSatisfy { $0.linkConfidence == .high }
        case .needsReview:
            return parent.children.contains { $0.linkConfidence == .low || $0.linkConfidence == .medium }
        }
    }
}

// MARK: - Preview

#Preview {
    PairingTab(
        project: Project(
            name: "Test Project",
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            blankRushDirectory: URL(fileURLWithPath: "/tmp")
        ),
        projectManager: ProjectManager()
    )
    .frame(width: 1000, height: 600)
}