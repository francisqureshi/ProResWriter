//
//  ProjectManager.swift
//  ProResWriter
//
//  Created by Claude on 25/08/2025.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ProResWriterCore

// MARK: - Project Manager

class ProjectManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var projects: [Project] = []
    @Published var currentProject: Project?
    @Published var recentProjects: [Project] = []
    
    // MARK: - File Management
    private let documentsDirectory: URL
    private let projectsDirectory: URL
    
    // MARK: - Initialization
    init() {
        NSLog("🚀 ProjectManager init called!")
        // Set up project storage directory
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        projectsDirectory = documentsDirectory.appendingPathComponent("ProResWriter Projects")
        
        print("📁 Projects directory: \(projectsDirectory.path)")
        
        // Ensure projects directory exists
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        
        // Load existing projects
        loadProjects()
        print("📊 Loaded \(projects.count) projects, \(recentProjects.count) recent")
    }
    
    // MARK: - Project Creation
    func createNewProject(name: String, outputDirectory: URL, blankRushDirectory: URL) -> Project {
        let project = Project(
            name: name,
            outputDirectory: outputDirectory,
            blankRushDirectory: blankRushDirectory
        )
        
        projects.append(project)
        currentProject = project
        updateRecentProjects(project)
        
        // Auto-save new project
        saveProject(project)
        
        return project
    }
    
    // MARK: - Project Loading/Saving
    private func loadProjects() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "w2" }) else {
            return
        }
        
        for url in urls {
            if let project = loadProject(from: url) {
                projects.append(project)
                
                // Add to recent projects (sorted by lastModified)
                if recentProjects.count < 5 {
                    recentProjects.append(project)
                }
            }
        }
        
        // Sort recent projects by last modified date
        recentProjects.sort { $0.lastModified > $1.lastModified }
    }
    
    private func loadProject(from url: URL) -> Project? {
        do {
            NSLog("📖 Loading project from: \(url.path)")
            let data = try Data(contentsOf: url)
            NSLog("📊 File data size: \(data.count) bytes")
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let project = try decoder.decode(Project.self, from: data)
            NSLog("✅ Successfully decoded project: \(project.name)")
            
            // Scan for existing blank rushes after loading
            project.scanForExistingBlankRushes()
            
            return project
        } catch {
            NSLog("❌ Failed to load project from \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    func saveProject(_ project: Project) {
        let filename = "\(project.name.replacingOccurrences(of: " ", with: "_")).w2"
        let url = projectsDirectory.appendingPathComponent(filename)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(project)
            try data.write(to: url)
            
            print("✅ Saved project: \(project.name)")
        } catch {
            print("❌ Failed to save project \(project.name): \(error)")
        }
    }
    
    func saveCurrentProject() {
        guard let project = currentProject else { return }
        project.updateModified()
        saveProject(project)
        updateRecentProjects(project)
    }
    
    // MARK: - Project Management
    func openProject(_ project: Project) {
        NSLog("📂 Opening project: \(project.name)")
        NSLog("📊 Project has \(project.ocfFiles.count) OCF files and \(project.segments.count) segments")
        
        // Set as current project
        currentProject = project
        updateRecentProjects(project)
        
        // Trigger UI update
        objectWillChange.send()
        
        NSLog("✅ Current project set to: \(currentProject?.name ?? "nil")")
        NSLog("🔄 UI update triggered")
    }
    
    func openProjectFile() {
        NSLog("🎬 openProjectFile() called!")
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data] // Try allowing all data files first
        panel.directoryURL = projectsDirectory
        
        NSLog("🔍 Opening file picker at: \(projectsDirectory.path)")
        
        let result = panel.runModal()
        NSLog("📋 File picker result: \(result == .OK ? "OK" : "Cancelled")")
        
        if result == .OK, let url = panel.url {
            NSLog("📁 Selected file: \(url.path)")
            NSLog("📂 File extension: \(url.pathExtension)")
            
            if let project = loadProject(from: url) {
                NSLog("✅ Successfully loaded project: \(project.name)")
                
                // Check if already loaded
                if !projects.contains(where: { $0.name == project.name }) {
                    projects.append(project)
                    NSLog("➕ Added project to list")
                } else {
                    NSLog("ℹ️ Project already in list")
                }
                
                openProject(project)
                NSLog("🎯 Called openProject()")
            } else {
                NSLog("❌ Failed to load project from file")
            }
        } else {
            NSLog("❌ File picker cancelled or failed")
        }
    }
    
    func closeProject() {
        if let project = currentProject {
            saveProject(project)
        }
        currentProject = nil
    }
    
    func deleteProject(_ project: Project) {
        // Remove from arrays
        projects.removeAll { $0.name == project.name }
        recentProjects.removeAll { $0.name == project.name }
        
        // Close if current
        if currentProject?.name == project.name {
            currentProject = nil
        }
        
        // Delete file
        let filename = "\(project.name.replacingOccurrences(of: " ", with: "_")).w2"
        let url = projectsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
    
    private func updateRecentProjects(_ project: Project) {
        // Remove if already in recent
        recentProjects.removeAll { $0.name == project.name }
        
        // Add to front
        recentProjects.insert(project, at: 0)
        
        // Keep only 5 most recent
        if recentProjects.count > 5 {
            recentProjects.removeLast()
        }
    }
    
    // MARK: - Import Integration
    func importOCFFiles(for project: Project, from directory: URL) async -> [MediaFileInfo] {
        let importProcess = ImportProcess()
        
        do {
            let files = try await importProcess.importOriginalCameraFiles(from: directory)
            project.addOCFFiles(files)
            saveProject(project)
            return files
        } catch {
            print("❌ Failed to import OCF files: \(error)")
            return []
        }
    }
    
    func importSegments(for project: Project, from directory: URL) async -> [MediaFileInfo] {
        let importProcess = ImportProcess()
        
        do {
            let files = try await importProcess.importGradedSegments(from: directory)
            project.addSegments(files)
            saveProject(project)
            return files
        } catch {
            print("❌ Failed to import segments: \(error)")
            return []
        }
    }
    
    func performLinking(for project: Project) {
        guard !project.ocfFiles.isEmpty && !project.segments.isEmpty else {
            print("⚠️ Need both OCF files and segments to perform linking")
            return
        }
        
        let linker = SegmentOCFLinker()
        let result = linker.linkSegments(project.segments, withOCFParents: project.ocfFiles)
        
        project.updateLinkingResult(result)
        saveProject(project)
        
        print("✅ Linking completed: \(result.summary)")
    }
    
    func createBlankRushes(for project: Project) async {
        guard let linkingResult = project.linkingResult else { return }
        
        let blankRushIntermediate = BlankRushIntermediate(
            projectDirectory: project.blankRushDirectory.path
        )
        
        // Update status to in progress for all parents
        for parent in linkingResult.parentsWithChildren {
            project.updateBlankRushStatus(ocfFileName: parent.ocf.fileName, status: .inProgress)
        }
        saveProject(project)
        
        let results = await blankRushIntermediate.createBlankRushes(from: linkingResult)
        
        // Update statuses based on results
        for result in results {
            let status: BlankRushStatus
            if result.success {
                status = .completed(date: Date(), url: result.blankRushURL)
            } else {
                status = .failed(error: result.error ?? "Unknown error")
            }
            project.updateBlankRushStatus(ocfFileName: result.originalOCF.fileName, status: status)
        }
        
        saveProject(project)
    }
}