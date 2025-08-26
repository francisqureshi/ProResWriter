//
//  ProjectTab.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

struct ProjectTab: View {
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    
    @StateObject private var hierarchy = ProjectHierarchy()
    @State private var expandedItems: Set<String> = []
    @State private var selectedItems: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ProjectTabToolbar(
                project: project,
                projectManager: projectManager,
                hierarchy: hierarchy
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main Content
            if hierarchy.items.isEmpty {
                EmptyProjectView()
            } else {
                HierarchicalProjectView(
                    hierarchy: hierarchy,
                    expandedItems: $expandedItems,
                    selectedItems: $selectedItems
                )
            }
        }
        .onAppear {
            hierarchy.updateFromProject(project)
        }
        .onChange(of: project.linkingResult) { _ in
            hierarchy.updateFromProject(project)
        }
    }
}

// MARK: - Toolbar

struct ProjectTabToolbar: View {
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    @ObservedObject var hierarchy: ProjectHierarchy
    
    @State private var showingBlankRushProgress = false
    
    var body: some View {
        HStack {
            // Info Summary
            VStack(alignment: .leading, spacing: 2) {
                Text("Project Overview")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Label("\(hierarchy.items.count) OCF parents", systemImage: "folder")
                    
                    let totalSegments = hierarchy.items.compactMap { $0.children?.count }.reduce(0, +)
                    Label("\(totalSegments) segments", systemImage: "doc")
                    
                    if project.hasModifiedSegments {
                        Label("\(project.modifiedSegments.count) modified", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 12) {
                // Refresh Button
                Button("Refresh") {
                    project.refreshSegmentModificationDates()
                    hierarchy.updateFromProject(project)
                    projectManager.saveProject(project)
                }
                .buttonStyle(.bordered)
                
                // Generate Blank Rushes Button
                Button("Generate Blank Rushes") {
                    showingBlankRushProgress = true
                    Task {
                        await projectManager.createBlankRushes(for: project)
                        showingBlankRushProgress = false
                        hierarchy.updateFromProject(project)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!project.readyForBlankRush)
                
                // Print Process Button  
                Button("Print Process") {
                    // Would trigger print process workflow
                }
                .buttonStyle(.borderedProminent)
                .disabled(project.blankRushProgress.completed == 0)
            }
        }
        .sheet(isPresented: $showingBlankRushProgress) {
            BlankRushProgressView(project: project)
        }
    }
}

// MARK: - Hierarchical View

struct HierarchicalProjectView: View {
    @ObservedObject var hierarchy: ProjectHierarchy
    @Binding var expandedItems: Set<String>
    @Binding var selectedItems: Set<String>
    
    var body: some View {
        Table(selection: $selectedItems) {
            // Filename Column
            TableColumn("Name") { item in
                HierarchicalItemRow(
                    item: item,
                    isExpanded: expandedItems.contains(item.id)
                ) {
                    if expandedItems.contains(item.id) {
                        expandedItems.remove(item.id)
                    } else {
                        expandedItems.insert(item.id)
                    }
                }
            }
            .width(min: 250, ideal: 350, max: 500)
            
            // Status Column
            TableColumn("Status", value: \.statusIcon) { item in
                Text(item.statusIcon)
                    .font(.title3)
            }
            .width(60)
            
            // Metadata Column
            TableColumn("Details", value: \.metadata) { item in
                Text(item.metadata)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .width(min: 200, ideal: 300)
            
            // Timecode Range Column
            TableColumn("Timecode Range", value: \.timecodeRange) { item in
                Text(item.timecodeRange)
                    .font(.monospaced(.caption)())
                    .foregroundColor(.secondary)
            }
            .width(min: 150, ideal: 200)
            
        } rows: {
            // Create table rows with parent-child relationships
            ForEach(expandedHierarchyItems, id: \.id) { item in
                TableRow(item)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
    
    // Flattened hierarchy for table display
    private var expandedHierarchyItems: [any HierarchicalItem] {
        var result: [any HierarchicalItem] = []
        
        for item in hierarchy.items {
            result.append(item)
            
            if expandedItems.contains(item.id), let children = item.children {
                result.append(contentsOf: children)
            }
        }
        
        return result
    }
}

// MARK: - Row Views

struct HierarchicalItemRow: View {
    let item: any HierarchicalItem
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            // Indentation and expand/collapse button for parents
            if let children = item.children, !children.isEmpty {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else if item.children != nil {
                // Child items get indentation
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)
            }
            
            // Status icon
            Text(item.statusIcon)
                .font(.caption)
            
            // Item name
            Text(item.displayName)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
        }
    }
}

// MARK: - Empty State

struct EmptyProjectView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No linked media")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Import OCF files and segments, then use the Pairing tab to link them together.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Button("Go to Media Tab") {
                // Would switch to media tab
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Progress Views

struct BlankRushProgressView: View {
    @ObservedObject var project: Project
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Generating Blank Rushes")
                .font(.title)
            
            let (completed, total) = project.blankRushProgress
            ProgressView(value: Double(completed), total: Double(total))
                .progressViewStyle(.linear)
            
            Text("\(completed) of \(total) completed")
                .foregroundColor(.secondary)
            
            Button("Close") {
                dismiss()
            }
        }
        .padding(40)
        .frame(width: 400)
    }
}

// MARK: - Preview

#Preview {
    ProjectTab(
        project: Project(
            name: "Test Project",
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            blankRushDirectory: URL(fileURLWithPath: "/tmp")
        ),
        projectManager: ProjectManager()
    )
    .frame(width: 1000, height: 600)
}