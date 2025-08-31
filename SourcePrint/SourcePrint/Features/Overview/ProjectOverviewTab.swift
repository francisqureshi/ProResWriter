//
//  ProjectOverviewTab.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct ProjectOverviewTab: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProjectStatsView(project: project)
            
            Text("Project loaded successfully!")
                .font(.title2)
            
            Text("OCF Files: \(project.ocfFiles.count)")
            Text("Segments: \(project.segments.count)")
            if let linkingResult = project.linkingResult {
                Text("Linked Segments: \(linkingResult.totalLinkedSegments)")
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ProjectStatsView: View {
    let project: Project
    
    var body: some View {
        GroupBox("Project Status") {
            HStack {
                VStack(alignment: .leading) {
                    Text("Created: \(DateFormatter.short.string(from: project.createdDate))")
                    Text("Modified: \(DateFormatter.short.string(from: project.lastModified))")
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    if project.readyForBlankRush {
                        Label("Ready for Blank Rush", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
}