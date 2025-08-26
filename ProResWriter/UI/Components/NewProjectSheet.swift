//
//  NewProjectSheet.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct NewProjectSheet: View {
    @ObservedObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = ""
    @State private var outputDirectory = ""
    @State private var blankRushDirectory = ""
    @State private var showingOutputPicker = false
    @State private var showingBlankRushPicker = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("New ProResWriter Project")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Create a new project to manage your OCF files and graded segments")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                // Project Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Name")
                        .font(.headline)
                    
                    TextField("Enter project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Output Directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output Directory")
                        .font(.headline)
                    
                    HStack {
                        TextField("Choose output directory", text: $outputDirectory)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button("Browse") {
                            showingOutputPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text("Where final rendered videos will be saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Blank Rush Directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blank Rush Directory")
                        .font(.headline)
                    
                    HStack {
                        TextField("Choose blank rush directory", text: $blankRushDirectory)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button("Browse") {
                            showingBlankRushPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text("Where blank rush proxy files will be stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Create Project") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(32)
        .frame(width: 500, height: 450)
        .fileImporter(
            isPresented: $showingOutputPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectorySelection(result, for: \.outputDirectory)
        }
        .fileImporter(
            isPresented: $showingBlankRushPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectorySelection(result, for: \.blankRushDirectory)
        }
        .onAppear {
            // Set default project name with timestamp
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            projectName = "ProResWriter Project \(formatter.string(from: Date()))"
        }
    }
    
    private var isValid: Bool {
        !projectName.isEmpty && 
        !outputDirectory.isEmpty && 
        !blankRushDirectory.isEmpty
    }
    
    private func handleDirectorySelection(_ result: Result<[URL], Error>, for keyPath: WritableKeyPath<NewProjectSheet, String>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                if keyPath == \Self.outputDirectory {
                    outputDirectory = url.path
                } else if keyPath == \Self.blankRushDirectory {
                    blankRushDirectory = url.path
                }
            }
        case .failure(let error):
            print("❌ Directory selection error: \(error)")
        }
    }
    
    private func createProject() {
        let outputURL = URL(fileURLWithPath: outputDirectory)
        let blankRushURL = URL(fileURLWithPath: blankRushDirectory)
        
        let project = projectManager.createNewProject(
            name: projectName,
            outputDirectory: outputURL,
            blankRushDirectory: blankRushURL
        )
        
        print("✅ Created project: \(project.name)")
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NewProjectSheet(projectManager: ProjectManager())
}