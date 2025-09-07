//
//  MediaFileTableView.swift
//  SourcePrint
//
//  Professional NLE-style table view for media files with sortable columns
//

import ProResWriterCore
import SwiftUI

struct MediaFileTableView: View {
    let files: [MediaFileInfo]
    let type: MediaType
    let selectedFiles: Binding<Set<String>>
    let onVFXToggle: ((String, Bool) -> Void)?
    let onRemoveFiles: ([String]) -> Void

    @State private var sortOrder = [KeyPathComparator(\MediaFileInfo.fileName)]
    @State private var selection = Set<String>()

    enum MediaType {
        case ocf, segment

        var displayName: String {
            switch self {
            case .ocf: return "Original Camera Files"
            case .segment: return "Graded Segments"
            }
        }

        var icon: String {
            switch self {
            case .ocf: return "camera"
            case .segment: return "scissors"
            }
        }

        var color: Color {
            switch self {
            case .ocf: return .blue
            case .segment: return .orange
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            tableView
        }
        .onDeleteCommand {
            if !selection.isEmpty {
                onRemoveFiles(Array(selection))
            }
        }
    }

    private var headerView: some View {
        HStack {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
            Text("\(type.displayName) (\(files.count))")
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var tableView: some View {
        List(files, id: \.fileName, selection: $selection) { file in
            MediaFileTableRowView(
                file: file,
                type: type,
                onVFXToggle: onVFXToggle
            )
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: String.self) { items in
            if items.count == 1, let fileName = items.first,
                let file = files.first(where: { $0.fileName == fileName }),
                type == .segment
            {
                Button {
                    onVFXToggle?(file.fileName, !file.isVFX)
                } label: {
                    Label(
                        file.isVFX ? "Unmark as VFX Shot" : "Mark as VFX Shot",
                        systemImage: file.isVFX ? "wand.and.stars.slash" : "wand.and.stars")
                }

                Divider()
            }

            Button("Remove from Project", systemImage: "trash") {
                onRemoveFiles(Array(items))
            }
            .foregroundColor(.red)
            .disabled(items.isEmpty)
        } primaryAction: { items in
            // Double-click action could be added here
        }
        .onChange(of: selection) { oldValue, newValue in
            selectedFiles.wrappedValue = newValue
        }
    }
}

struct MediaFileTableRowView: View {
    let file: MediaFileInfo
    let type: MediaFileTableView.MediaType
    let onVFXToggle: ((String, Bool) -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            // Main row with file name and key info
            HStack(spacing: 12) {
                // File icon and VFX indicator
                HStack(spacing: 4) {
                    Image(systemName: type.icon)
                        .foregroundColor(type.color)
                        .frame(width: 16)

                    if file.isVFX && type == .segment {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.purple)
                            .frame(width: 14)
                    }
                }
                .frame(width: 36, alignment: .leading)

                // File name
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(file.fileName)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)

                        Spacer()

                        if file.isVFX && type == .segment {
                            Text("VFX")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .cornerRadius(3)
                        }
                    }

                    // Metadata row
                    HStack(spacing: 1) {
                        // Duration
                        if let frames = file.durationInFrames, let fps = file.frameRate {
                            Text("\(Double(frames) / Double(fps), specifier: "%.2f")s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Frame rate
                        if let fps = file.frameRate {
                            Text("\(fps, specifier: "%.3f")fps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Resolution
                        if let resolution = file.displayResolution {
                            Text("\(Int(resolution.width))×\(Int(resolution.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Timecode
                        if let timecode = file.sourceTimecode {
                            Text(timecode)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Media type badge
                        Text(mediaTypeDisplayName(file.mediaType))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func mediaTypeDisplayName(_ mediaType: MediaType) -> String {
        switch mediaType {
        case .originalCameraFile:
            return "OCF"
        case .gradedSegment:
            return "Segment"
        }
    }
}

#Preview {
    // Create sample MediaFileInfo for preview
    let sampleFiles = [
        MediaFileInfo(
            fileName: "C20250825_0303.mov",
            url: URL(fileURLWithPath: "/path/to/file1.mov"),
            resolution: CGSize(width: 3840, height: 2160),
            displayResolution: CGSize(width: 3840, height: 2160),
            sampleAspectRatio: "1:1",
            frameRate: 25.0,
            sourceTimecode: "20:16:31:13",
            endTimecode: "20:17:16:01",
            durationInFrames: 1320,
            isDropFrame: false,
            reelName: nil,
            isInterlaced: false,
            fieldOrder: "progressive",
            mediaType: .originalCameraFile
        ),
        MediaFileInfo(
            fileName: "Segment_001_VFX.mov",
            url: URL(fileURLWithPath: "/path/to/file2.mov"),
            resolution: CGSize(width: 3840, height: 2160),
            displayResolution: CGSize(width: 3840, height: 2160),
            sampleAspectRatio: "1:1",
            frameRate: 59.94,
            sourceTimecode: "01:00:00:00",
            endTimecode: "01:00:10:00",
            durationInFrames: 600,
            isDropFrame: true,
            reelName: nil,
            isInterlaced: false,
            fieldOrder: "progressive",
            mediaType: .gradedSegment,
            isVFXShot: true
        ),
    ]

    MediaFileTableView(
        files: sampleFiles,
        type: .segment,
        selectedFiles: .constant([]),
        onVFXToggle: { fileName, isVFX in
            print("Toggle VFX for \(fileName): \(isVFX)")
        },
        onRemoveFiles: { fileNames in
            print("Remove files: \(fileNames)")
        }
    )
    .frame(height: 400)
}

