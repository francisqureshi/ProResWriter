//
//  ContentView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 28/08/2025.
//

import SwiftUI
import ProResWriterCore

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
                    
                    Text("Professional Media Workflow Management")
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
    @State private var showingFilePicker = false
    @State private var importingOCF = false
    @State private var isAnalyzing = false
    @State private var analysisProgress = ""
    @State private var selectedOCFFiles: Set<String> = []
    @State private var selectedSegments: Set<String> = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Import Actions
            HStack(spacing: 16) {
                VStack {
                    Button("Import OCF Files") {
                        importingOCF = true
                        showingFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                    
                    Text("Original Camera Files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Button("Import Segments") {
                        importingOCF = false
                        showingFilePicker = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzing)
                    
                    Text("Graded/Edited Footage")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importMediaFiles(urls: urls, isOCF: importingOCF)
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }
    
    private func importMediaFiles(urls: [URL], isOCF: Bool) {
        isAnalyzing = true
        analysisProgress = "Analyzing \(urls.count) file(s)..."
        
        Task {
            do {
                var mediaFiles: [MediaFileInfo] = []
                
                for (index, url) in urls.enumerated() {
                    await MainActor.run {
                        analysisProgress = "Analyzing file \(index + 1)/\(urls.count): \(url.lastPathComponent)"
                    }
                    
                    let mediaFile = try await MediaAnalyzer().analyzeMediaFile(at: url, type: isOCF ? .originalCameraFile : .gradedSegment)
                    mediaFiles.append(mediaFile)
                }
                
                await MainActor.run {
                    if isOCF {
                        project.addOCFFiles(mediaFiles)
                    } else {
                        project.addSegments(mediaFiles)
                    }
                    
                    projectManager.saveProject(project)
                    isAnalyzing = false
                    analysisProgress = ""
                }
                
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    analysisProgress = "Analysis failed: \(error.localizedDescription)"
                }
            }
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
                    
                    if let result = project.linkingResult {
                        Text("\(result.summary)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                    }
                }
                
                if isLinking {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(linkingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                NSLog("✅ Linking completed: \(result.summary)")
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

#Preview {
    ContentView()
        .environmentObject(ProjectManager())
}
