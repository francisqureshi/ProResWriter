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
    
    var body: some View {
        List(selection: .constant(projectManager.currentProject?.id)) {
            Section("Recent Projects") {
                ForEach(projectManager.recentProjects, id: \.name) { project in
                    ProjectRowView(project: project)
                        .onTapGesture {
                            print("🎯 Sidebar project clicked: \(project.name)")
                            projectManager.openProject(project)
                        }
                }
            }
            
            Section("All Projects") {
                ForEach(projectManager.projects, id: \.name) { project in
                    ProjectRowView(project: project)
                        .onTapGesture {
                            print("🎯 Sidebar project clicked: \(project.name)")
                            projectManager.openProject(project)
                        }
                }
            }
        }
        .navigationTitle("Projects")
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
                
                if !projectManager.recentProjects.isEmpty {
                    Text("or select a recent project from the sidebar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
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
            
            Text("Segment Linking - Coming Soon")
                .tabItem {
                    Label("Linking", systemImage: "link")
                }
        }
        .navigationTitle(project.name)
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
                    
                    List(project.ocfFiles, id: \.fileName) { file in
                        MediaFileRowView(file: file, type: .ocf)
                    }
                }
                .frame(minWidth: 300)
                
                // Segments
                VStack(alignment: .leading) {
                    Text("Segments (\(project.segments.count))")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List(project.segments, id: \.fileName) { file in
                        MediaFileRowView(file: file, type: .segment)
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

#Preview {
    ContentView()
        .environmentObject(ProjectManager())
}
