//
//  WelcomeView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct WelcomeView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showingNewProject = false
    
    var body: some View {
        TabView {
            // Welcome content in Overview tab
            VStack(spacing: 24) {
                Image(systemName: "film.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Welcome to SourcePrint")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Source Matched Roundtrip Media Workflow")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    Button("Create New Project") {
                        showingNewProject = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("or select a project from the sidebar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("Overview", systemImage: "list.bullet")
            }
            
            // Placeholder Media tab
            VStack {
                Text("Select a project to import media files")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .tabItem {
                Label("Media", systemImage: "folder")
            }
            
            // Placeholder Linking tab  
            VStack {
                Text("Select a project to manage segment linking")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .tabItem {
                Label("Linking", systemImage: "link")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet()
                .environmentObject(projectManager)
        }
    }
}