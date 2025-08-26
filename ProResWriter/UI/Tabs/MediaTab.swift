//
//  MediaTab.swift
//  ProResWriter
//
//  Created by Claude on 26/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct MediaTab: View {
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    
    @State private var selectedMediaType: MediaType = .ocf
    @State private var isImporting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Media Type Selector
            MediaTypeSelector(selectedType: $selectedMediaType)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Split View: OCF and Segments
            HSplitView {
                // OCF Files Section
                MediaSection(
                    title: "OCF Files",
                    mediaFiles: project.ocfFiles,
                    isActive: selectedMediaType == .ocf,
                    onImport: { urls in
                        importOCFFiles(from: urls)
                    }
                )
                
                // Segments Section
                MediaSection(
                    title: "Segments",
                    mediaFiles: project.segments,
                    isActive: selectedMediaType == .segments,
                    onImport: { urls in
                        importSegments(from: urls)
                    }
                )
            }
        }
        .disabled(isImporting)
        .overlay {
            if isImporting {
                ImportingOverlay()
            }
        }
    }
    
    // MARK: - Import Functions
    
    private func importOCFFiles(from urls: [URL]) {
        guard let directoryURL = urls.first else { return }
        
        isImporting = true
        Task {
            let files = await projectManager.importOCFFiles(for: project, from: directoryURL)
            await MainActor.run {
                isImporting = false
                print("✅ Imported \(files.count) OCF files")
            }
        }
    }
    
    private func importSegments(from urls: [URL]) {
        guard let directoryURL = urls.first else { return }
        
        isImporting = true
        Task {
            let files = await projectManager.importSegments(for: project, from: directoryURL)
            await MainActor.run {
                isImporting = false
                print("✅ Imported \(files.count) segments")
            }
        }
    }
}

// MARK: - Media Type Selector

enum MediaType: String, CaseIterable {
    case ocf = "OCF"
    case segments = "Segments"
    
    var description: String {
        switch self {
        case .ocf: return "Original Camera Files - Import from camera card or footage directories"
        case .segments: return "Graded Segments - Import rendered clips from color grading or editing"
        }
    }
    
    var iconName: String {
        switch self {
        case .ocf: return "camera.fill"
        case .segments: return "film.fill"
        }
    }
}

struct MediaTypeSelector: View {
    @Binding var selectedType: MediaType
    
    var body: some View {
        HStack {
            Picker("Media Type", selection: $selectedType) {
                ForEach(MediaType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.iconName)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            Spacer()
            
            Text(selectedType.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Media Section

struct MediaSection: View {
    let title: String
    let mediaFiles: [MediaFileInfo]
    let isActive: Bool
    let onImport: ([URL]) -> Void
    
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Section Header
            HStack {
                Label(title, systemImage: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.headline)
                    .foregroundColor(isActive ? .blue : .secondary)
                
                Spacer()
                
                Text("\(mediaFiles.count) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Import") {
                    showingFilePicker = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // File List or Drop Zone
            if mediaFiles.isEmpty {
                MediaDropZone(title: title) { urls in
                    onImport(urls)
                }
            } else {
                MediaFileList(mediaFiles: mediaFiles)
            }
        }
        .background(isActive ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                onImport(urls)
            case .failure(let error):
                print("❌ File picker error: \(error)")
            }
        }
    }
}

// MARK: - Drop Zone

struct MediaDropZone: View {
    let title: String
    let onDrop: ([URL]) -> Void
    
    @State private var isDropTargeted = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Drop \(title) Folder Here")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("or click Import to browse")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDropTargeted ? .blue : .secondary,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDropTargeted ? .blue.opacity(0.1) : .clear)
                )
        )
        .padding()
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) {
        let dispatchGroup = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                dispatchGroup.enter()
                provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        urls.append(url)
                    }
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if !urls.isEmpty {
                onDrop(urls)
            }
        }
    }
}

// MARK: - File List

struct MediaFileList: View {
    let mediaFiles: [MediaFileInfo]
    
    var body: some View {
        List {
            ForEach(mediaFiles, id: \.fileName) { file in
                MediaFileRow(mediaFile: file)
            }
        }
        .listStyle(.plain)
    }
}

struct MediaFileRow: View {
    let mediaFile: MediaFileInfo
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mediaFile.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let resolution = mediaFile.displayResolution ?? mediaFile.resolution {
                        Text("\(Int(resolution.width))×\(Int(resolution.height))")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Text(mediaFile.frameRateDescription)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    
                    if let frameCount = mediaFile.durationInFrames {
                        Text("\(frameCount) frames")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                if let timecode = mediaFile.sourceTimecode {
                    Text("TC: \(timecode)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }
            }
            
            Spacer()
            
            // Status indicators
            VStack {
                Text(mediaFile.technicalSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Import Overlay

struct ImportingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Importing Media Files...")
                    .font(.headline)
                
                Text("Analyzing metadata and frame counts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Preview

#Preview {
    MediaTab(
        project: Project(
            name: "Test Project",
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            blankRushDirectory: URL(fileURLWithPath: "/tmp")
        ),
        projectManager: ProjectManager()
    )
    .frame(width: 1000, height: 600)
}