//
//  NewProjectSheet.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import SourcePrintCore

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