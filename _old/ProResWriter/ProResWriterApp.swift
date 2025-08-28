//
//  ProResWriterApp.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI

@main
struct ProResWriterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    // Would trigger new project creation
                }
                .keyboardShortcut("n")
            }
            
            // View Menu
            CommandGroup(after: .toolbar) {
                Menu("View") {
                    Button("Show Sidebar") {
                        // Would toggle sidebar
                    }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    
                    Divider()
                    
                    Button("Refresh Project") {
                        // Would refresh current project
                    }
                    .keyboardShortcut("r")
                }
            }
            
            // Workflow Menu
            CommandMenu("Workflow") {
                Button("Import OCF Files...") {
                    // Would trigger OCF import
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Import Segments...") {
                    // Would trigger segment import
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Run Auto-Pairing") {
                    // Would trigger linking
                }
                .keyboardShortcut("l")
                
                Button("Generate Blank Rushes") {
                    // Would trigger blank rush generation
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Button("Start Print Process") {
                    // Would trigger final render
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - App Configuration

extension ProResWriterApp {
    init() {
        // Configure app appearance
        setupAppearance()
    }
    
    private func setupAppearance() {
        // Ensure we're using the system appearance
        NSApp.appearance = nil
    }
}