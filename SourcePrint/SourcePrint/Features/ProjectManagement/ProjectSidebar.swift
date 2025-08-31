//
//  ProjectSidebar.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

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