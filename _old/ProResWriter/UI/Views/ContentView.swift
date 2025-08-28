//
//  ContentView.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var projectManager = ProjectManager()
    @State private var selectedSidebarItem: SidebarItem? = .projects
    
    var body: some View {
        NavigationSplitView {
            // Finder-like Sidebar
            ProjectSidebar(
                projectManager: projectManager,
                selectedItem: $selectedSidebarItem
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Main Content Area
            if let currentProject = projectManager.currentProject {
                ProjectMainView(
                    project: currentProject,
                    projectManager: projectManager
                )
            } else {
                WelcomeView(projectManager: projectManager)
            }
        }
        .onAppear {
            // Initialize project manager
        }
    }
}

// MARK: - Sidebar Items

enum SidebarItem: String, CaseIterable {
    case projects = "Projects"
    case recent = "Recent"
    
    var iconName: String {
        switch self {
        case .projects: return "folder.fill"
        case .recent: return "clock.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}