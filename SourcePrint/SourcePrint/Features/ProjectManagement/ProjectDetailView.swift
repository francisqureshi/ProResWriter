//
//  ProjectDetailView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        TabView {
            ProjectOverviewTab(project: project)
                .tabItem {
                    Label("Overview", systemImage: "list.bullet")
                }
            
            MediaImportTab(project: project)
                .environmentObject(projectManager)
                .tabItem {
                    Label("Media", systemImage: "folder")
                }
            
            LinkingTab(project: project)
                .environmentObject(projectManager)
                .tabItem {
                    Label("Linking", systemImage: "link")
                }
            
            if #available(macOS 15, *) {
                RenderTab(project: project)
                    .environmentObject(projectManager)
                    .tabItem {
                        Label("Render", systemImage: "play.rectangle")
                    }
            } else {
                Text("Render functionality requires macOS 15 or later")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.secondary)
                    .tabItem {
                        Label("Render", systemImage: "play.rectangle")
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
    }
}