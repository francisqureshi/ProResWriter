//
//  SourcePrintApp.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 28/08/2025.
//

import SwiftUI
import ProResWriterCore

extension Notification.Name {
    static let showNewProject = Notification.Name("showNewProject")
    static let toggleSidebar = Notification.Name("toggleSidebar")
}

@main
struct SourcePrintApp: App {
    @StateObject private var projectManager = ProjectManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectManager)
                .preferredColorScheme(.dark)
                .background(Color.appBackground)
                .tint(Color.appAccent)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    // This will trigger the new project sheet in ContentView
                    NotificationCenter.default.post(name: .showNewProject, object: nil)
                }
                .keyboardShortcut("n")
            }
            
            CommandGroup(after: .newItem) {
                Button("Open Project...") {
                    projectManager.openProjectFile()
                }
                .keyboardShortcut("o")
                
                Menu("Open Recent") {
                    if projectManager.recentProjects.isEmpty {
                        Text("No Recent Projects")
                            .disabled(true)
                    } else {
                        ForEach(projectManager.recentProjects.indices, id: \.self) { index in
                            let project = projectManager.recentProjects[index]
                            Button(project.name) {
                                projectManager.openRecentProject(project)
                            }
                        }
                        
                        Divider()
                        
                        Button("Clear Menu") {
                            projectManager.clearRecentProjects()
                        }
                    }
                }
                .disabled(projectManager.recentProjects.isEmpty)
                
                Divider()
                
                Button("Save Project") {
                    if let currentProject = projectManager.currentProject {
                        projectManager.saveProject(currentProject)
                    }
                }
                .keyboardShortcut("s")
                .disabled(projectManager.currentProject == nil)
                
                Button("Save Project As...") {
                    if let currentProject = projectManager.currentProject {
                        projectManager.saveProjectAs(currentProject)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(projectManager.currentProject == nil)
            }
            
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
    }
}
