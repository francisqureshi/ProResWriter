//
//  SimpleProject.swift  
//  SourcePrint
//
//  Created by Claude on 30/08/2025.
//

import Foundation
import SwiftUI
import SourcePrintCore

// MARK: - Simplified Project Model for Initial Build

@MainActor
class SimpleProject: ObservableObject {
    @Published var name: String
    @Published var ocfFiles: [MediaFileInfo] = []
    @Published var segments: [MediaFileInfo] = []
    @Published var linkingResult: LinkingResult?
    
    init(name: String) {
        self.name = name
    }
}

@MainActor 
class SimpleProjectManager: ObservableObject {
    @Published var currentProject: SimpleProject?
    
    func createProject(name: String) {
        currentProject = SimpleProject(name: name)
    }
}