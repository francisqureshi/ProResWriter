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
            ToolbarItem(placement: .navigation) {
                Button("New Project", systemImage: "plus") {
                    showingNewProject = true
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
                            projectManager.openProject(project)
                        }
                }
            }
            
            Section("All Projects") {
                ForEach(projectManager.projects, id: \.name) { project in
                    ProjectRowView(project: project)
                        .onTapGesture {
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
            
            Text("Media Import - Coming Soon")
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

#Preview {
    ContentView()
        .environmentObject(ProjectManager())
}
