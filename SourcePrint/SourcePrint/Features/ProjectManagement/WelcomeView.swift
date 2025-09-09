//
//  WelcomeView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import ProResWriterCore
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showingNewProject = false

    var body: some View {
        TabView {
            VStack(spacing: 24) {
                Image(systemName: "film.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(AppTheme.accent)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem {
                Label("SourcePrint", systemImage: "house")
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet()
                .environmentObject(projectManager)
        }
    }
}

