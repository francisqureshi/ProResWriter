//
//  ProjectOverviewTab.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct ProjectOverviewTab: View {
    @ObservedObject var project: Project
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack {
                    Spacer()

                    VStack(alignment: .leading, spacing: 20) {
                        ProjectStatsView(project: project)

                        ProjectDirectoriesView(project: project)

                        ProjectMetricsView(project: project)

                        Spacer(minLength: 20)
                    }
                    .frame(width: geometry.size.width * 0.4)
                    .padding()

                    Spacer()
                }
            }
        }
    }
}

struct ProjectStatsView: View {
    let project: Project

    var body: some View {
        GroupBox("Project Status") {
            HStack {
                VStack(alignment: .leading) {
                    Text("Project: \(project.name)")
                        .font(.headline)
                    Text("File: \(project.fileURL?.lastPathComponent ?? "Unsaved")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
    }
}

struct ProjectDirectoriesView: View {
    @ObservedObject var project: Project

    var body: some View {
        GroupBox("Project Directories") {
            VStack(alignment: .leading, spacing: 12) {
                DirectoryRowView(
                    title: "Output Directory",
                    directory: project.outputDirectory,
                    icon: "folder.badge.gearshape"
                ) { newDirectory in
                    project.outputDirectory = newDirectory
                }

                Divider()

                DirectoryRowView(
                    title: "Blank Rush Directory",
                    directory: project.blankRushDirectory,
                    icon: "film.circle"
                ) { newDirectory in
                    project.blankRushDirectory = newDirectory
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct DirectoryRowView: View {
    let title: String
    let directory: URL
    let icon: String
    let onDirectoryChange: (URL) -> Void

    @State private var isShowingFilePicker = false

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(.primary)
                .frame(minWidth: 160, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(directory.path)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !FileManager.default.fileExists(atPath: directory.path) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Directory does not exist")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            Button("Change...") {
                isShowingFilePicker = true
            }
            .buttonStyle(CompressorButtonStyle())
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    onDirectoryChange(selectedURL)
                }
            case .failure(let error):
                NSLog("Failed to select directory: \(error)")
            }
        }
    }
}

struct ProjectMetricsView: View {
    let project: Project

    var body: some View {
        GroupBox("Project Metrics") {
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(label: "OCF Files", value: "\(project.ocfFiles.count)")
                    MetricRow(label: "Segments", value: "\(project.segments.count)")
                    if let linkingResult = project.linkingResult {
                        MetricRow(label: "Linked Segments", value: "\(linkingResult.totalLinkedSegments)")
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(label: "Project Created", value: DateFormatter.short.string(from: project.createdDate))
                    MetricRow(label: "Last Modified", value: DateFormatter.short.string(from: project.lastModified))
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(minWidth: 100, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}