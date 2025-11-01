//
//  ProjectDetailView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import SourcePrintCore

struct ProjectDetailView: View {
    let project: ProjectViewModel
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
    }
}