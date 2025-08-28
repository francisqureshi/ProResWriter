//
//  ProjectMainView.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct ProjectMainView: View {
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    
    @State private var selectedTab: ProjectTab = .project
    
    var body: some View {
        VStack(spacing: 0) {
            // Project Header
            ProjectHeaderView(project: project)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Tab Interface
            TabView(selection: $selectedTab) {
                ProjectTab(
                    project: project,
                    projectManager: projectManager
                )
                .tabItem {
                    Label("Project", systemImage: "folder.badge.gearshape")
                }
                .tag(ProjectTab.project)
                
                MediaTab(
                    project: project,
                    projectManager: projectManager
                )
                .tabItem {
                    Label("Media", systemImage: "externaldrive.badge.plus")
                }
                .tag(ProjectTab.media)
                
                PairingTab(
                    project: project,
                    projectManager: projectManager
                )
                .tabItem {
                    Label("Pairing", systemImage: "link.badge.plus")
                }
                .tag(ProjectTab.pairing)
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle(projectSubtitle)
    }
    
    private var projectSubtitle: String {
        var parts: [String] = []
        
        if project.ocfFiles.count > 0 {
            parts.append("\(project.ocfFiles.count) OCF files")
        }
        
        if project.segments.count > 0 {
            parts.append("\(project.segments.count) segments")
        }
        
        if let linkingResult = project.linkingResult {
            parts.append("\(linkingResult.totalLinkedSegments) linked")
        }
        
        return parts.joined(separator: " • ")
    }
}

// MARK: - Project Header

struct ProjectHeaderView: View {
    @ObservedObject var project: Project
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Status Indicators
                    ProjectStatusIndicators(project: project)
                }
                
                HStack {
                    Text("Last modified: \(project.lastModified, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if project.hasModifiedSegments {
                        Text("• Modified segments detected")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

struct ProjectStatusIndicators: View {
    @ObservedObject var project: Project
    
    var body: some View {
        HStack(spacing: 12) {
            // Linking Status
            if project.hasLinkedMedia {
                Label("\(project.linkingResult?.totalLinkedSegments ?? 0)", systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Blank Rush Progress
            let (completed, total) = project.blankRushProgress
            if total > 0 {
                let color: Color = completed == total ? .green : .orange
                Label("\(completed)/\(total)", systemImage: "film.fill")
                    .font(.caption)
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Modified Segments Warning
            if project.hasModifiedSegments {
                let count = project.modifiedSegments.count
                Label("\(count)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Tab Enum

enum ProjectTab: String, CaseIterable {
    case project = "project"
    case media = "media" 
    case pairing = "pairing"
    
    var title: String {
        switch self {
        case .project: return "Project"
        case .media: return "Media"
        case .pairing: return "Pairing"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectMainView(
            project: Project(
                name: "Test Project",
                outputDirectory: URL(fileURLWithPath: "/tmp"),
                blankRushDirectory: URL(fileURLWithPath: "/tmp")
            ),
            projectManager: ProjectManager()
        )
    }
    .frame(width: 1000, height: 700)
}