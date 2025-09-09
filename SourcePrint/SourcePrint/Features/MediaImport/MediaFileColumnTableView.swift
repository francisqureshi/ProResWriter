//
//  MediaFileColumnTableView.swift
//  SourcePrint
//
//  Professional NLE-style column table view like Resolve/FCPX
//

import SwiftUI
import ProResWriterCore

struct MediaFileColumnTableView: View {
    let files: [MediaFileInfo]
    let type: MediaType
    let selectedFiles: Binding<Set<String>>
    let onVFXToggle: ((String, Bool) -> Void)?
    let onRemoveFiles: ([String]) -> Void
    let onImportAction: (() -> Void)?
    let isAnalyzing: Bool
    
    @State private var selection = Set<String>()
    
    // Column width state - user adjustable and responsive
    @State private var clipNameWidth: CGFloat = 200
    @State private var startTCWidth: CGFloat = 100
    @State private var endTCWidth: CGFloat = 100
    @State private var durationWidth: CGFloat = 80
    @State private var framesWidth: CGFloat = 70
    @State private var typeWidth: CGFloat = 80
    @State private var resolutionWidth: CGFloat = 100
    @State private var fpsWidth: CGFloat = 60
    @State private var totalWidth: CGFloat = 0
    
    // Minimum column widths to prevent over-shrinking
    private let minClipNameWidth: CGFloat = 120
    private let minStartTCWidth: CGFloat = 80
    private let minEndTCWidth: CGFloat = 80
    private let minDurationWidth: CGFloat = 60
    private let minFramesWidth: CGFloat = 50
    private let minTypeWidth: CGFloat = 60
    private let minResolutionWidth: CGFloat = 80
    private let minFpsWidth: CGFloat = 40
    
    // Computed total column width for horizontal scrolling
    private var totalColumnWidth: CGFloat {
        clipNameWidth + startTCWidth + endTCWidth + durationWidth + 
        framesWidth + typeWidth + resolutionWidth + fpsWidth
    }
    
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
            case .ocf: return "film.fill"
            case .segment: return "film"
            }
        }
        
        var color: Color {
            switch self {
            case .ocf: return AppTheme.ocfColor
            case .segment: return AppTheme.segmentColor
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeadersView
                        fileRowsView
                    }
                    .frame(minWidth: geometry.size.width, maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
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
            
            if let importAction = onImportAction {
                Button("Import \(type == .ocf ? "OCF Files" : "Segments")...") {
                    importAction()
                }
                .buttonStyle(CompressorButtonStyle(prominent: true))
                .disabled(isAnalyzing)
            }
        }
        .padding()
        .background(AppTheme.backgroundSecondary)
    }
    
    private var columnHeadersView: some View {
        HStack(spacing: 0) {
            // Clip Name Column
            HStack(spacing: 0) {
                Text("Clip Name")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: clipNameWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    clipNameWidth = max(clipNameWidth + delta, minClipNameWidth)
                }
            }
            
            // Start TC Column
            HStack(spacing: 0) {
                Text("Start TC")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: startTCWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    startTCWidth = max(startTCWidth + delta, minStartTCWidth)
                }
            }
            
            // End TC Column
            HStack(spacing: 0) {
                Text("End TC")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: endTCWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    endTCWidth = max(endTCWidth + delta, minEndTCWidth)
                }
            }
            
            // Duration Column
            HStack(spacing: 0) {
                Text("Duration")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: durationWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    durationWidth = max(durationWidth + delta, minDurationWidth)
                }
            }
            
            // Frames Column
            HStack(spacing: 0) {
                Text("Frames")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: framesWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    framesWidth = max(framesWidth + delta, minFramesWidth)
                }
            }
            
            // Type Column
            HStack(spacing: 0) {
                Text("Type")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: typeWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    typeWidth = max(typeWidth + delta, minTypeWidth)
                }
            }
            
            // Resolution Column
            HStack(spacing: 0) {
                Text("Resolution")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: resolutionWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    resolutionWidth = max(resolutionWidth + delta, minResolutionWidth)
                }
            }
            
            // FPS Column
            HStack(spacing: 0) {
                Text("FPS")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: fpsWidth, alignment: .leading)
                    .padding(.horizontal, 4)
                
                ResizeDivider { delta in
                    fpsWidth = max(fpsWidth + delta, minFpsWidth)
                }
            }
            
            // Filler Column (expands to fill remaining space)
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(minWidth: 100, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: 22) // Full width, fixed height for compact header
        .background(Color(nsColor: .controlBackgroundColor))
        .border(Color(nsColor: .separatorColor), width: 0.5)
    }
    
    private var fileRowsView: some View {
        List(files, id: \.fileName, selection: $selection) { file in
            MediaFileColumnRowView(
                file: file,
                type: type,
                onVFXToggle: onVFXToggle,
                columnWidths: ColumnWidths(
                    clipName: clipNameWidth,
                    startTC: startTCWidth,
                    endTC: endTCWidth,
                    duration: durationWidth,
                    frames: framesWidth,
                    type: typeWidth,
                    resolution: resolutionWidth,
                    fps: fpsWidth
                )
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .frame(maxWidth: .infinity)
        .contextMenu(forSelectionType: String.self) { items in
            if items.count == 1, let fileName = items.first,
               let file = files.first(where: { $0.fileName == fileName }),
               type == .segment {
                Button {
                    onVFXToggle?(file.fileName, !file.isVFX)
                } label: {
                    Label(file.isVFX ? "Unmark as VFX Shot" : "Mark as VFX Shot",
                          systemImage: file.isVFX ? "wand.and.stars.slash" : "wand.and.stars")
                }
                
                Divider()
            }
            
            Button("Remove from Project", systemImage: "trash") {
                onRemoveFiles(Array(items))
            }
            .foregroundColor(.red)
            .disabled(items.isEmpty)
        }
        .onChange(of: selection) { oldValue, newValue in
            selectedFiles.wrappedValue = newValue
        }
    }
    
}

// MARK: - ColumnWidths Data Structure

struct ColumnWidths {
    let clipName: CGFloat
    let startTC: CGFloat
    let endTC: CGFloat
    let duration: CGFloat
    let frames: CGFloat
    let type: CGFloat
    let resolution: CGFloat
    let fps: CGFloat
}

// MARK: - ResizeDivider Component

struct ResizeDivider: View {
    let onDrag: (CGFloat) -> Void
    @State private var isDragging = false
    @State private var startLocation: CGPoint = .zero
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Main separator line
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 16)
            
            // Drag handle icon - only visible on hover or drag
            if isHovering || isDragging {
                VStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 2, height: 3)
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 2, height: 3)
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 2, height: 3)
                }
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 8, height: 12)
                )
            }
        }
        .overlay(
            Rectangle()
                .fill(Color.clear)
                .frame(width: 20, height: 24) // Even wider hit target
                .cursor(.resizeLeftRight)
        )
        .contentShape(Rectangle().size(width: 20, height: 24))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .gesture(
            DragGesture(coordinateSpace: .local)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        startLocation = value.startLocation
                    }
                    let delta = value.translation.width
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct MediaFileColumnRowView: View {
    let file: MediaFileInfo
    let type: MediaFileColumnTableView.MediaType
    let onVFXToggle: ((String, Bool) -> Void)?
    let columnWidths: ColumnWidths
    
    var body: some View {
        HStack(spacing: 0) {
            // Clip Name Column
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                    .frame(width: 16)
                
                if file.isVFX && type == .segment {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple)
                        .frame(width: 14)
                }
                
                Text(file.fileName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if file.isVFX && type == .segment {
                    Text("VFX")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(3)
                }
                
                Spacer()
            }
            .frame(width: columnWidths.clipName, alignment: .leading)
            .padding(.horizontal, 4)
            
            // Start TC Column
            Text(file.sourceTimecode ?? "—")
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundColor(file.sourceTimecode != nil ? .primary : .secondary)
                .frame(width: columnWidths.startTC, alignment: .leading)
                .padding(.horizontal, 4)
            
            // End TC Column
            Text(file.endTimecode ?? "—")
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundColor(file.endTimecode != nil ? .primary : .secondary)
                .frame(width: columnWidths.endTC, alignment: .leading)
                .padding(.horizontal, 4)
            
            // Duration Column
            Group {
                if let frames = file.durationInFrames, let fps = file.frameRate {
                    Text("\(Double(frames) / Double(fps), specifier: "%.2f")s")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: columnWidths.duration, alignment: .leading)
            .padding(.horizontal, 4)
            
            // Frames Column
            Text(String(format: "%d", file.durationInFrames ?? 0))
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: columnWidths.frames, alignment: .leading)
                .padding(.horizontal, 4)
            
            // Type Column
            Text(mediaTypeDisplayName(file.mediaType))
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(3)
                .frame(width: columnWidths.type, alignment: .leading)
                .padding(.horizontal, 4)
            
            // Resolution Column
            Group {
                if let resolution = file.displayResolution {
                    Text(String(format: "%dx%d", Int(resolution.width), Int(resolution.height)))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .lineLimit(1)
                } else if let resolution = file.resolution {
                    Text(String(format: "%dx%d", Int(resolution.width), Int(resolution.height)))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: columnWidths.resolution, alignment: .leading)
            .padding(.horizontal, 4)
            
            // FPS Column
            Text("\(file.frameRate ?? 0, specifier: "%.3f")")
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columnWidths.fps, alignment: .leading)
                .padding(.horizontal, 4)
            
            // Filler Column (expands to fill remaining space)
            Rectangle()
                .fill(Color.clear)
                .frame(minWidth: 100, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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
        )
    ]
    
    MediaFileColumnTableView(
        files: sampleFiles,
        type: .segment,
        selectedFiles: .constant([]),
        onVFXToggle: { fileName, isVFX in
            print("Toggle VFX for \(fileName): \(isVFX)")
        },
        onRemoveFiles: { fileNames in
            print("Remove files: \(fileNames)")
        },
        onImportAction: {
            print("Import action triggered")
        },
        isAnalyzing: false
    )
    .frame(height: 400)
}
