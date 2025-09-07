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
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
        .onReceive(NotificationCenter.default.publisher(for: .showNewProject)) { _ in
            showingNewProject = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
        }
        .onAppear {
            // Set initial sidebar visibility from stored preference
            columnVisibility = sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { oldValue, newValue in
            // Save sidebar visibility preference when user toggles it
            sidebarVisible = (newValue == .all)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProjectManager())
}