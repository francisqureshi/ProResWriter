//
//  WelcomeView.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var projectManager: ProjectManager
    @State private var showingNewProjectSheet = false
    
    var body: some View {
        VStack(spacing: 32) {
            // App Icon and Title
            VStack(spacing: 16) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)
                
                VStack(spacing: 8) {
                    Text("ProResWriter")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Professional post-production workflow automation")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            // Feature Highlights
            VStack(alignment: .leading, spacing: 16) {
                WelcomeFeatureRow(
                    icon: "camera.viewfinder",
                    title: "Import & Analyze",
                    description: "Import OCF files and graded segments with automatic metadata analysis"
                )
                
                WelcomeFeatureRow(
                    icon: "link.badge.plus",
                    title: "Intelligent Pairing",
                    description: "Automatically match segments to original camera files using timecode and metadata"
                )
                
                WelcomeFeatureRow(
                    icon: "film.fill",
                    title: "Blank Rush Generation",
                    description: "Create ProRes 4444 blank rushes with timecode burn-in for review"
                )
                
                WelcomeFeatureRow(
                    icon: "square.and.arrow.up",
                    title: "Professional Output",
                    description: "Export frame-accurate compositions with broadcast-standard quality"
                )
            }
            .padding(.horizontal, 40)
            
            // Actions
            VStack(spacing: 12) {
                Button("Create New Project") {
                    showingNewProjectSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                if !projectManager.recentProjects.isEmpty {
                    HStack {
                        Text("Recent Projects:")
                            .foregroundColor(.secondary)
                        
                        ForEach(projectManager.recentProjects.prefix(3), id: \.name) { project in
                            Button(project.name) {
                                projectManager.openProject(project)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet(projectManager: projectManager)
        }
    }
}

struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView(projectManager: ProjectManager())
        .frame(width: 800, height: 600)
}