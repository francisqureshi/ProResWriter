//
//  SourcePrintApp.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 28/08/2025.
//

import SwiftUI
import ProResWriterCore

@main
struct SourcePrintApp: App {
    @StateObject private var projectManager = ProjectManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectManager)
        }
    }
}
