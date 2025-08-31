//
//  LinkingTab.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct LinkingTab: View {
    let project: Project
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isLinking = false
    @State private var linkingProgress = ""
    @State private var progressValue: Double = 0.0
    @State private var progressTotal: Double = 100.0
    @State private var currentFPS: Double = 0.0
    @State private var currentClipName: String = ""
    @State private var currentFileIndex: Int = 0
    @State private var totalFileCount: Int = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Linking Controls
            VStack {
                HStack {
                    Button("Run Auto-Linking") {
                        performLinking()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(project.ocfFiles.isEmpty || project.segments.isEmpty || isLinking)
                    
                    Button("Generate Blank Rushes") {
                        generateBlankRushes()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!project.readyForBlankRush || isLinking)
                    
                    if let result = project.linkingResult {
                        Text("\(result.summary)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                    }
                }
                
                if isLinking {
                    VStack(spacing: 8) {
                        ProgressView(
                            value: progressValue, 
                            total: progressTotal,
                            label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(linkingProgress)
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
                                            Text("📎 \(currentClipName)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                            Spacer()
                                            if currentFPS > 0 {
                                                Text("\(String(format: "%.1f", currentFPS)) fps")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .monospacedDigit()
                                            }
                                        }
                                    }
                                }
                            },
                            currentValueLabel: {
                                Text("\(Int((progressValue / progressTotal) * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .progressViewStyle(.linear)
                        .animation(.easeInOut(duration: 0.2), value: progressValue)
                    }
                }
            }
            .padding()
            
            // Linking Results Display
            if let linkingResult = project.linkingResult {
                LinkingResultsView(linkingResult: linkingResult, project: project)
            } else {
                VStack {
                    Image(systemName: "link.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No linking results yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Import OCF files and segments, then run auto-linking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func performLinking() {
        guard !project.ocfFiles.isEmpty && !project.segments.isEmpty else {
            NSLog("⚠️ Cannot link: need both OCF files and segments")
            return
        }
        
        isLinking = true
        linkingProgress = "Analyzing \(project.segments.count) segments against \(project.ocfFiles.count) OCF files..."
        
        Task {
            await MainActor.run {
                linkingProgress = "Running SegmentOCFLinker..."
            }
            
            let linker = SegmentOCFLinker()
            let result = linker.linkSegments(project.segments, withOCFParents: project.ocfFiles)
            
            await MainActor.run {
                project.updateLinkingResult(result)
                projectManager.saveProject(project)
                isLinking = false
                linkingProgress = ""
                progressValue = 0.0
                currentFPS = 0.0
                currentClipName = ""
                currentFileIndex = 0
                totalFileCount = 0
                NSLog("✅ Linking completed: \(result.summary)")
            }
        }
    }
    
    private func generateBlankRushes() {
        guard let linkingResult = project.linkingResult else {
            NSLog("⚠️ Cannot generate blank rushes: no linking result")
            return
        }
        
        let ocfsToProcess = linkingResult.parentsWithChildren
        guard !ocfsToProcess.isEmpty else {
            NSLog("⚠️ No OCF files with children to process")
            return
        }
        
        isLinking = true
        progressTotal = 100.0
        totalFileCount = ocfsToProcess.count
        currentFileIndex = 0
        
        Task {
            let blankRushCreator = BlankRushIntermediate(projectDirectory: project.blankRushDirectory.path)
            var allResults: [BlankRushResult] = []
            
            for (index, parent) in ocfsToProcess.enumerated() {
                await MainActor.run {
                    currentFileIndex = index + 1
                    currentClipName = (parent.ocf.fileName as NSString).deletingPathExtension
                    linkingProgress = "Creating ProRes 4444 blank rush..."
                    progressValue = 0.0
                    currentFPS = 0.0
                }
                
                // Create single file's linking result for this OCF
                let singleOCFResult = LinkingResult(
                    ocfParents: [parent],
                    unmatchedSegments: [],
                    unmatchedOCFs: []
                )
                
                // Process this single OCF with real progress callback
                let results = await blankRushCreator.createBlankRushes(from: singleOCFResult) { clipName, current, total, fps in
                    await MainActor.run {
                        self.currentClipName = clipName
                        self.progressValue = current
                        self.progressTotal = total
                        self.currentFPS = fps
                    }
                }
                
                await MainActor.run {
                    progressValue = 100.0
                    currentFPS = 0.0
                    
                    // Update project status for this file
                    if let result = results.first {
                        if result.success {
                            project.blankRushStatus[result.originalOCF.fileName] = .completed(date: Date(), url: result.blankRushURL)
                        } else {
                            project.blankRushStatus[result.originalOCF.fileName] = .failed(error: result.error ?? "Unknown error")
                        }
                        allResults.append(result)
                    }
                }
                
                // Brief pause between files
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            await MainActor.run {
                projectManager.saveProject(project)
                isLinking = false
                linkingProgress = ""
                progressValue = 0.0
                currentClipName = ""
                currentFileIndex = 0
                totalFileCount = 0
                currentFPS = 0.0
                
                let successCount = allResults.filter { $0.success }.count
                NSLog("✅ Blank Rush generation completed: \(successCount)/\(allResults.count) successful")
            }
        }
    }
}