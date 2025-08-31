//
//  ContentView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 28/08/2025.
//

import SwiftUI
import ProResWriterCore
import AVFoundation
import CoreMedia

struct ContentView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showingNewProject = false
    
    var body: some View {
        NavigationSplitView {
            ProjectSidebar()
                .environmentObject(projectManager)
        } detail: {
            if let currentProject = projectManager.currentProject {
                ProjectDetailView(project: currentProject)
                    .environmentObject(projectManager)
            } else {
                WelcomeView()
                    .environmentObject(projectManager)
            }
        }
        .navigationTitle("SourcePrint")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("New Project", systemImage: "plus") {
                    showingNewProject = true
                }
                
                Button("Open Project", systemImage: "folder") {
                    NSLog("🎯 Open Project button clicked!")
                    projectManager.openProjectFile()
                }
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet()
                .environmentObject(projectManager)
        }
    }
}

struct ProjectSidebar: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var selection: UUID?
    
    var body: some View {
        List(selection: $selection) {
            Section("Projects") {
                ForEach(projectManager.projects, id: \.id) { project in
                    ProjectRowView(project: project)
                        .tag(project.id)
                }
            }
        }
        .navigationTitle("Projects")
        .onChange(of: selection) { oldValue, newValue in
            if let selectedId = newValue,
               let selectedProject = projectManager.projects.first(where: { $0.id == selectedId }) {
                print("🎯 Sidebar project selected: \(selectedProject.name)")
                projectManager.openProject(selectedProject)
            }
        }
        .onAppear {
            selection = projectManager.currentProject?.id
        }
        .onChange(of: projectManager.currentProject?.id) { oldValue, newValue in
            selection = newValue
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            
            HStack {
                Text(DateFormatter.short.string(from: project.lastModified))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if project.hasLinkedMedia {
                    Label("\(project.linkingResult?.totalLinkedSegments ?? 0)", systemImage: "link")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showingNewProject = false
    
    var body: some View {
        TabView {
            // Welcome content in Overview tab
            VStack(spacing: 24) {
                Image(systemName: "film.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Welcome to SourcePrint")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Source Matched Roundtrip Media Workflow")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    Button("Create New Project") {
                        showingNewProject = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("or select a project from the sidebar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Overview", systemImage: "list.bullet")
            }
            
            // Placeholder Media tab
            VStack {
                Text("Select a project to import media files")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .tabItem {
                Label("Media", systemImage: "folder")
            }
            
            // Placeholder Linking tab  
            VStack {
                Text("Select a project to manage segment linking")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .tabItem {
                Label("Linking", systemImage: "link")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet()
                .environmentObject(projectManager)
        }
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        TabView {
            ProjectOverviewTab(project: project)
                .tabItem {
                    Label("Overview", systemImage: "list.bullet")
                }
            
            MediaImportTab(project: project)
                .environmentObject(projectManager)
                .tabItem {
                    Label("Media", systemImage: "folder")
                }
            
            LinkingTab(project: project)
                .environmentObject(projectManager)
                .tabItem {
                    Label("Linking", systemImage: "link")
                }
            
            if #available(macOS 15, *) {
                RenderTab(project: project)
                    .environmentObject(projectManager)
                    .tabItem {
                        Label("Render", systemImage: "play.rectangle")
                    }
            } else {
                Text("Render functionality requires macOS 15 or later")
                    .tabItem {
                        Label("Render", systemImage: "play.rectangle")
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProjectOverviewTab: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProjectStatsView(project: project)
            
            Text("Project loaded successfully!")
                .font(.title2)
            
            Text("OCF Files: \(project.ocfFiles.count)")
            Text("Segments: \(project.segments.count)")
            if let linkingResult = project.linkingResult {
                Text("Linked Segments: \(linkingResult.totalLinkedSegments)")
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ProjectStatsView: View {
    let project: Project
    
    var body: some View {
        GroupBox("Project Status") {
            HStack {
                VStack(alignment: .leading) {
                    Text("Created: \(DateFormatter.short.string(from: project.createdDate))")
                    Text("Modified: \(DateFormatter.short.string(from: project.lastModified))")
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    if project.readyForBlankRush {
                        Label("Ready for Blank Rush", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = ""
    @State private var outputDirectory: URL?
    @State private var blankRushDirectory: URL?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Project Information") {
                    TextField("Project Name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Directories") {
                    DirectoryPickerRow(
                        title: "Output Directory",
                        url: $outputDirectory,
                        placeholder: "Choose output directory..."
                    )
                    
                    DirectoryPickerRow(
                        title: "Blank Rush Directory", 
                        url: $blankRushDirectory,
                        placeholder: "Choose blank rush directory..."
                    )
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(!isValidProject)
                }
            }
        }
        .frame(width: 500, height: 300)
    }
    
    private var isValidProject: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        outputDirectory != nil &&
        blankRushDirectory != nil
    }
    
    private func createProject() {
        guard let outputDir = outputDirectory,
              let blankRushDir = blankRushDirectory else { return }
        
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = projectManager.createNewProject(
            name: trimmedName,
            outputDirectory: outputDir,
            blankRushDirectory: blankRushDir
        )
        
        dismiss()
    }
}

struct DirectoryPickerRow: View {
    let title: String
    @Binding var url: URL?
    let placeholder: String
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            
            Button(url?.lastPathComponent ?? placeholder) {
                selectDirectory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(url == nil ? .secondary : .primary)
        }
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            url = panel.url
        }
    }
}

struct MediaImportTab: View {
    let project: Project
    @EnvironmentObject var projectManager: ProjectManager
    @State private var importingOCF = false
    @State private var isAnalyzing = false
    @State private var analysisProgress = ""
    @State private var selectedOCFFiles: Set<String> = []
    @State private var selectedSegments: Set<String> = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Import Actions
            HStack(spacing: 40) {
                VStack {
                    Text("Original Camera Files")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    Button("Import OCF Files...") {
                        importingOCF = true
                        showImportPicker()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                }
                
                VStack {
                    Text("Graded/Edited Footage")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Button("Import Segments...") {
                        importingOCF = false
                        showImportPicker()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                }
            }
            .padding()
            
            if isAnalyzing {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(analysisProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Media Lists
            HSplitView {
                // OCF Files
                VStack(alignment: .leading) {
                    Text("OCF Files (\(project.ocfFiles.count))")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List(project.ocfFiles, id: \.fileName, selection: $selectedOCFFiles) { file in
                        MediaFileRowView(file: file, type: .ocf)
                            .tag(file.fileName)
                    }
                }
                .frame(minWidth: 300)
                
                // Segments
                VStack(alignment: .leading) {
                    Text("Segments (\(project.segments.count))")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List(project.segments, id: \.fileName, selection: $selectedSegments) { file in
                        MediaFileRowView(file: file, type: .segment)
                            .tag(file.fileName)
                    }
                }
                .frame(minWidth: 300)
            }
        }
    }
    
    private func showImportPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie]
        panel.title = importingOCF ? "Import OCF Files or Folders" : "Import Segment Files or Folders"
        panel.message = "Select video files and/or folders. Folders will be scanned recursively for video files."
        
        if panel.runModal() == .OK {
            let selectedURLs = panel.urls
            guard !selectedURLs.isEmpty else { return }
            
            // Automatically handle mixed selection of files and folders
            Task {
                var allVideoFiles: [URL] = []
                
                for url in selectedURLs {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            // It's a folder - scan recursively
                            let folderVideoFiles = await scanFolderForVideoFiles(url)
                            allVideoFiles.append(contentsOf: folderVideoFiles)
                        } else {
                            // It's a file - add directly if it's a video file
                            let fileExtension = url.pathExtension.lowercased()
                            let videoExtensions = ["mov", "mp4", "m4v", "mxf", "prores"]
                            if videoExtensions.contains(fileExtension) {
                                allVideoFiles.append(url)
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    if !allVideoFiles.isEmpty {
                        importMediaFiles(urls: allVideoFiles, isOCF: importingOCF)
                    } else {
                        print("No video files found in selection")
                    }
                }
            }
        }
    }
    
    private func scanFolderForVideoFiles(_ folderURL: URL) async -> [URL] {
        return await withTaskGroup(of: [URL].self) { taskGroup in
            taskGroup.addTask {
                await self.getAllVideoFiles(from: folderURL)
            }
            
            var allFiles: [URL] = []
            for await files in taskGroup {
                allFiles.append(contentsOf: files)
            }
            return allFiles
        }
    }
    
    private func getAllVideoFiles(from directoryURL: URL) async -> [URL] {
        var videoFiles: [URL] = []
        let videoExtensions = ["mov", "mp4", "m4v", "mxf", "prores"]
        
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return videoFiles
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    let fileExtension = fileURL.pathExtension.lowercased()
                    if videoExtensions.contains(fileExtension) {
                        videoFiles.append(fileURL)
                    }
                }
            } catch {
                print("Error processing file \(fileURL): \(error)")
            }
        }
        
        return videoFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    private func importMediaFiles(urls: [URL], isOCF: Bool) {
        isAnalyzing = true
        analysisProgress = "Analyzing \(urls.count) file(s)..."
        
        Task {
            let mediaFiles = await analyzeMediaFilesInParallel(urls: urls, isOCF: isOCF)
            
            await MainActor.run {
                if isOCF {
                    project.addOCFFiles(mediaFiles)
                } else {
                    project.addSegments(mediaFiles)
                }
                
                projectManager.saveProject(project)
                isAnalyzing = false
                analysisProgress = ""
                NSLog("✅ Imported \(mediaFiles.count) \(isOCF ? "OCF" : "segment") files")
            }
        }
    }
    
    private func analyzeMediaFilesInParallel(urls: [URL], isOCF: Bool) async -> [MediaFileInfo] {
        // For I/O-bound tasks like media analysis, we can use much higher concurrency
        let maxConcurrentTasks = min(urls.count, 50)  // Increased from CPU core count to 50
        var completedCount = 0
        let totalCount = urls.count
        var lastUpdateTime = CFAbsoluteTimeGetCurrent()
        let updateInterval: CFTimeInterval = 0.5  // Update UI every 0.5 seconds
        
        return await withTaskGroup(of: (Int, MediaFileInfo?).self, returning: [MediaFileInfo].self) { taskGroup in
            var urlIndex = 0
            
            // Start initial batch of tasks
            for _ in 0..<min(maxConcurrentTasks, urls.count) {
                let index = urlIndex
                let url = urls[index]
                urlIndex += 1
                
                taskGroup.addTask {
                    do {
                        let mediaFile = try await MediaAnalyzer().analyzeMediaFile(
                            at: url, 
                            type: isOCF ? .originalCameraFile : .gradedSegment
                        )
                        return (index, mediaFile)
                    } catch {
                        NSLog("❌ Failed to analyze \(url.lastPathComponent): \(error)")
                        return (index, nil)
                    }
                }
            }
            
            // Collect results and maintain steady concurrency
            var results: [(Int, MediaFileInfo?)] = []
            results.reserveCapacity(totalCount)  // Pre-allocate array capacity
            
            for await result in taskGroup {
                results.append(result)
                completedCount += 1
                
                // Add next task if we have more URLs to process
                if urlIndex < urls.count {
                    let index = urlIndex
                    let url = urls[index]
                    urlIndex += 1
                    
                    taskGroup.addTask {
                        do {
                            let mediaFile = try await MediaAnalyzer().analyzeMediaFile(
                                at: url, 
                                type: isOCF ? .originalCameraFile : .gradedSegment
                            )
                            return (index, mediaFile)
                        } catch {
                            NSLog("❌ Failed to analyze \(url.lastPathComponent): \(error)")
                            return (index, nil)
                        }
                    }
                }
                
                // Throttled UI updates
                let currentTime = CFAbsoluteTimeGetCurrent()
                if currentTime - lastUpdateTime >= updateInterval || completedCount == totalCount {
                    lastUpdateTime = currentTime
                    
                    await MainActor.run {
                        let (_, mediaFile) = result
                        if let mediaFile = mediaFile {
                            analysisProgress = "Analyzing files... \(completedCount)/\(totalCount) completed - \(mediaFile.fileName)"
                        } else {
                            analysisProgress = "Analyzing files... \(completedCount)/\(totalCount) completed"
                        }
                    }
                }
            }
            
            // Sort by original index and filter out failed analyses
            return results
                .sorted { $0.0 < $1.0 }
                .compactMap { $0.1 }
        }
    }
}

struct MediaFileRowView: View {
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
                    if let frames = file.durationInFrames, let fps = file.frameRate {
                        Text("\(Double(frames) / Double(fps), specifier: "%.2f")s")
                    } else {
                        Text("Unknown duration")
                    }
                    Text("•")
                    Text("\(file.durationInFrames ?? 0) frames")
                    Text("•")
                    Text("\(file.frameRate ?? 0, specifier: "%.3f") fps")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if let startTC = file.sourceTimecode {
                    Text("TC: \(startTC)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text("\(file.mediaType)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}

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
                LinkingResultsView(linkingResult: linkingResult)
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

struct LinkingResultsView: View {
    let linkingResult: LinkingResult
    @State private var selectedLinkedFiles: Set<String> = []
    @State private var selectedUnmatchedFiles: Set<String> = []
    
    // Computed properties to separate high/medium confidence from low confidence segments
    var confidentlyLinkedParents: [OCFParent] {
        return linkingResult.ocfParents.compactMap { parent in
            let goodSegments = parent.children.filter { segment in
                segment.linkConfidence == .high || segment.linkConfidence == .medium
            }
            return goodSegments.isEmpty ? nil : OCFParent(ocf: parent.ocf, children: goodSegments)
        }
    }
    
    var lowConfidenceSegments: [LinkedSegment] {
        return linkingResult.ocfParents.flatMap { parent in
            parent.children.filter { segment in
                segment.linkConfidence == .low
            }
        }
    }
    
    var totalConfidentSegments: Int {
        return confidentlyLinkedParents.reduce(0) { $0 + $1.childCount }
    }
    
    var body: some View {
        HSplitView {
            // Confidently Linked OCF Parents and Children
            VStack(alignment: .leading) {
                Text("Linked Files (\(totalConfidentSegments) segments)")
                    .font(.headline)
                    .padding(.horizontal)
                
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
                            OCFParentHeaderView(parent: parent)
                                .tag(parent.ocf.fileName)
                        }
                    }
                }
            }
            .frame(minWidth: 400)
            
            // Unmatched Items + Low Confidence
            VStack(alignment: .leading) {
                Text("Unmatched Items")
                    .font(.headline)
                    .padding(.horizontal)
                
                List(selection: $selectedUnmatchedFiles) {
                    if !linkingResult.unmatchedOCFs.isEmpty {
                        Section("Unmatched OCF Files (\(linkingResult.unmatchedOCFs.count))") {
                            ForEach(linkingResult.unmatchedOCFs, id: \.fileName) { ocf in
                                UnmatchedFileRowView(file: ocf, type: .ocf)
                                    .tag(ocf.fileName)
                            }
                        }
                    }
                    
                    if !linkingResult.unmatchedSegments.isEmpty {
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
        }
    }
}

struct OCFParentHeaderView: View {
    let parent: OCFParent
    
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
        }
        .padding(.vertical, 4)
    }
}

struct OCFParentRowView: View {
    let parent: OCFParent
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

// MARK: - Render Tab

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
        guard let linkingResult = project.linkingResult else { return false }
        
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
                    // Generate output filename
                    let baseName = (ocfParent.ocf.fileName as NSString).deletingPathExtension
                    let outputFileName = "\(baseName)_Print_\(DateFormatter.filenameSafe.string(from: Date())).mov"
                    let outputURL = project.outputDirectory.appendingPathComponent(outputFileName)
                    
                    // Create compositor and analyze base video
                    let compositor = ProResVideoCompositor()
                    let baseAsset = AVURLAsset(url: blankRushURL)
                    let baseTrack = try await compositor.getVideoTrack(from: baseAsset)
                    let baseProperties = try await compositor.getVideoProperties(from: baseTrack)
                    
                    // Convert linked children to GradedSegments
                    var gradedSegments: [GradedSegment] = []
                    for child in ocfParent.children {
                        let segmentInfo = child.segment
                        
                        if let segmentTC = segmentInfo.sourceTimecode,
                           let baseTC = baseProperties.sourceTimecode,
                           let startTime = compositor.timecodeToCMTime(segmentTC, frameRate: baseProperties.frameRate, baseTimecode: baseTC),
                           let duration = segmentInfo.durationInFrames {
                            
                            let segmentDuration = CMTime(
                                seconds: Double(duration) / Double(baseProperties.frameRate),
                                preferredTimescale: CMTimeScale(baseProperties.frameRate * 1000)
                            )
                            
                            let gradedSegment = GradedSegment(
                                url: segmentInfo.url,
                                startTime: startTime,
                                duration: segmentDuration,
                                sourceStartTime: .zero
                            )
                            gradedSegments.append(gradedSegment)
                        }
                    }
                    
                    guard !gradedSegments.isEmpty else {
                        NSLog("❌ No valid graded segments for \(ocfParent.ocf.fileName)")
                        continue
                    }
                    
                    // Setup compositor settings
                    let settings = CompositorSettings(
                        outputURL: outputURL,
                        baseVideoURL: blankRushURL,
                        gradedSegments: gradedSegments,
                        proResType: .proRes4444
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
                            segmentCount: gradedSegments.count,
                            duration: compositionDuration,
                            success: true
                        )
                        allPrintRecords.append(printRecord)
                        NSLog("✅ Composition completed: \(finalOutputURL.lastPathComponent)")
                        
                    case .failure(let error):
                        let printRecord = PrintRecord(
                            date: Date(),
                            outputURL: outputURL,
                            segmentCount: gradedSegments.count,
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

#Preview {
    ContentView()
        .environmentObject(ProjectManager())
}
