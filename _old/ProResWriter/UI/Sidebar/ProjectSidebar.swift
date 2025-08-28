//
//  ProjectSidebar.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedItem: SidebarItem?
    
    @State private var showingNewProjectSheet = false
    
    var body: some View {
        List(selection: $selectedItem) {
            // Header Section
            Section {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    SidebarRow(
                        title: item.rawValue,
                        iconName: item.iconName,
                        isSelected: selectedItem == item
                    )
                    .tag(item)
                }
            }
            
            // Projects Section
            Section("Projects") {
                ForEach(projectManager.projects, id: \.name) { project in
                    ProjectRow(
                        project: project,
                        isCurrentProject: projectManager.currentProject?.name == project.name
                    ) {
                        projectManager.openProject(project)
                    }
                    .contextMenu {
                        ProjectContextMenu(
                            project: project,
                            projectManager: projectManager
                        )
                    }
                }
                
                // New Project Button
                Button(action: { showingNewProjectSheet = true }) {
                    Label("New Project", systemImage: "plus.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Recent Projects Section
            if !projectManager.recentProjects.isEmpty {
                Section("Recent") {
                    ForEach(projectManager.recentProjects.prefix(5), id: \.name) { project in
                        ProjectRow(
                            project: project,
                            isCurrentProject: false,
                            showLastModified: true
                        ) {
                            projectManager.openProject(project)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ProResWriter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNewProjectSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet(projectManager: projectManager)
        }
    }
}

// MARK: - Supporting Views

struct SidebarRow: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    
    var body: some View {
        Label(title, systemImage: iconName)
            .foregroundColor(isSelected ? .primary : .secondary)
    }
}

struct ProjectRow: View {
    let project: Project
    let isCurrentProject: Bool
    var showLastModified: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(isCurrentProject ? .blue : .primary)
                    
                    if isCurrentProject {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                }
                
                if showLastModified {
                    Text(project.lastModified, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Quick status indicators
                HStack(spacing: 8) {
                    if project.hasLinkedMedia {
                        Label("\(project.linkingResult?.totalLinkedSegments ?? 0)", systemImage: "link")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    let (completed, total) = project.blankRushProgress
                    if total > 0 {
                        Label("\(completed)/\(total)", systemImage: "film")
                            .font(.caption2)
                            .foregroundColor(completed == total ? .green : .orange)
                    }
                    
                    Spacer()
                }
                .opacity(0.7)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct ProjectContextMenu: View {
    let project: Project
    let projectManager: ProjectManager
    
    var body: some View {
        Button("Open") {
            projectManager.openProject(project)
        }
        
        Divider()
        
        Button("Refresh Segments") {
            project.refreshSegmentModificationDates()
            projectManager.saveProject(project)
        }
        
        Button("Show in Finder") {
            // Would show project directory in Finder
        }
        
        Divider()
        
        Button("Delete", role: .destructive) {
            projectManager.deleteProject(project)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitView {
        ProjectSidebar(
            projectManager: ProjectManager(),
            selectedItem: .constant(.projects)
        )
    } detail: {
        Text("Select a project")
    }
    .frame(width: 1000, height: 600)
}