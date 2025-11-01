//
//  ProjectSidebar.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import SourcePrintCore

struct ProjectSidebar: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var selection: UUID?

    var body: some View {
        sidebarList
    }

    @ViewBuilder
    private var sidebarList: some View {
        let list = List(selection: $selection) {
            Section("Projects") {
                ForEach(projectManager.projects, id: \.id) { project in
                    ProjectRowView(project: project)
                        .tag(project.id)
                }
            }
        }

        list
            .listStyle(SidebarListStyle())
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundSecondary)
            .navigationTitle("Projects")
            .onChange(of: selection, handleSelectionChange)
            .onAppear(perform: handleAppear)
            .onChange(of: projectManager.currentProject?.id, handleProjectChange)
    }

    private func handleSelectionChange(oldValue: UUID?, newValue: UUID?) {
        if let selectedId = newValue,
           let selectedProject = projectManager.projects.first(where: { $0.id == selectedId }) {
            print("🎯 Sidebar project selected: \(selectedProject.model.name)")
            projectManager.openProject(selectedProject)
        }
    }

    private func handleAppear() {
        selection = projectManager.currentProject?.id
    }

    private func handleProjectChange(oldValue: UUID?, newValue: UUID?) {
        selection = newValue
    }
}

struct ProjectRowView: View {
    let project: ProjectViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.model.name)
                .font(.headline)

            HStack {
                Text(DateFormatter.short.string(from: project.model.lastModified))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if project.hasLinkedMedia {
                    Label("\(project.model.linkingResult?.totalLinkedSegments ?? 0)", systemImage: "link")
                        .font(.caption)
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .padding(.vertical, 2)
    }
}