//
//  LinkingColumnTableView.swift
//  SourcePrint
//
//  Professional NLE-style column table for linking results
//

import ProResWriterCore
import SwiftUI

struct LinkedResultsColumnTableView: View {
    @ObservedObject var project: Project
    @EnvironmentObject var projectManager: ProjectManager

    // Column widths - user adjustable and responsive
    @State private var clipNameWidth: CGFloat = 200
    @State private var typeWidth: CGFloat = 80
    @State private var confidenceWidth: CGFloat = 100
    @State private var startTCWidth: CGFloat = 100
    @State private var endTCWidth: CGFloat = 100
    @State private var durationWidth: CGFloat = 90
    @State private var framesWidth: CGFloat = 80
    @State private var resolutionWidth: CGFloat = 100
    @State private var fpsWidth: CGFloat = 80
    @State private var statusWidth: CGFloat = 120

    // Expanded state for each OCF parent
    @State private var expandedOCFs: Set<String> = []

    // Selection state
    @State private var selectedRowId: UUID? = nil

    // Minimum column widths
    private let minClipNameWidth: CGFloat = 150
    private let minTypeWidth: CGFloat = 60
    private let minConfidenceWidth: CGFloat = 80
    private let minStartTCWidth: CGFloat = 80
    private let minEndTCWidth: CGFloat = 80
    private let minDurationWidth: CGFloat = 70
    private let minFramesWidth: CGFloat = 60
    private let minResolutionWidth: CGFloat = 80
    private let minFPSWidth: CGFloat = 60
    private let minStatusWidth: CGFloat = 100

    private var linkingResult: LinkingResult? {
        project.linkingResult
    }

    // Flattened data for table display with collapsible structure
    private var tableData: [LinkingTableRow] {
        guard let linkingResult = linkingResult else { return [] }

        var rows: [LinkingTableRow] = []

        // Add only confidently linked segments (high and medium confidence)
        for parent in linkingResult.ocfParents {
            let goodSegments = parent.children.filter { segment in
                segment.linkConfidence == .high || segment.linkConfidence == .medium
            }

            if !goodSegments.isEmpty {
                // Add OCF parent header
                rows.append(
                    LinkingTableRow(
                        type: .ocfParent,
                        ocfParent: parent,
                        linkedSegment: nil,
                        unmatchedFile: nil,
                        project: project
                    ))

                // Add linked segments only if this OCF is expanded
                let ocfKey = parent.ocf.fileName
                if expandedOCFs.contains(ocfKey) {
                    for segment in goodSegments {
                        rows.append(
                            LinkingTableRow(
                                type: .linkedSegment,
                                ocfParent: nil,
                                linkedSegment: segment,
                                unmatchedFile: nil,
                                project: project
                            ))
                    }
                }
            }
        }

        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header section (always visible at top)
            HStack {
                Text("Linked Files")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Table content
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Headers - match MediaFileColumnTableView structure exactly
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

                            // Confidence Column
                            HStack(spacing: 0) {
                                Text("Confidence")
                                    .font(.system(size: 11, weight: .medium, design: .default))
                                    .foregroundColor(.secondary)
                                    .frame(width: confidenceWidth, alignment: .leading)
                                    .padding(.horizontal, 4)

                                ResizeDivider { delta in
                                    confidenceWidth = max(
                                        confidenceWidth + delta, minConfidenceWidth)
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

                            // Resolution Column
                            HStack(spacing: 0) {
                                Text("Resolution")
                                    .font(.system(size: 11, weight: .medium, design: .default))
                                    .foregroundColor(.secondary)
                                    .frame(width: resolutionWidth, alignment: .leading)
                                    .padding(.horizontal, 4)

                                ResizeDivider { delta in
                                    resolutionWidth = max(
                                        resolutionWidth + delta, minResolutionWidth)
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
                                    fpsWidth = max(fpsWidth + delta, minFPSWidth)
                                }
                            }

                            // Status Column (last, no divider)
                            Text("Status")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundColor(.secondary)
                                .frame(width: statusWidth, alignment: .leading)
                                .padding(.horizontal, 4)

                            // Filler column to eliminate right gutter
                            Rectangle()
                                .fill(Color.clear)
                                .frame(minWidth: 100, maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 22)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .border(Color(nsColor: .separatorColor), width: 0.5)

                        // Rows
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tableData.enumerated()), id: \.element.id) { index, row in
                                LinkingTableRowView(
                                    row: row,
                                    clipNameWidth: clipNameWidth,
                                    typeWidth: typeWidth,
                                    confidenceWidth: confidenceWidth,
                                    startTCWidth: startTCWidth,
                                    endTCWidth: endTCWidth,
                                    durationWidth: durationWidth,
                                    framesWidth: framesWidth,
                                    resolutionWidth: resolutionWidth,
                                    fpsWidth: fpsWidth,
                                    statusWidth: statusWidth,
                                    isEven: index % 2 == 0,
                                    expandedOCFs: $expandedOCFs,
                                    isSelected: selectedRowId == row.id
                                )
                                .background(
                                    selectedRowId == row.id
                                        ? Color.accentColor.opacity(0.2) : Color.clear
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRowId = row.id
                                }

                                if index < tableData.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(minWidth: geometry.size.width, maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .focusable()
        .focusEffectDisabled()  // Disable the focus ring around the whole table
        .onKeyPress(.rightArrow) {
            if let selectedRowId = selectedRowId,
                let selectedRow = tableData.first(where: { $0.id == selectedRowId })
            {
                handleRightArrowPress(for: selectedRow)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.leftArrow) {
            if let selectedRowId = selectedRowId,
                let selectedRow = tableData.first(where: { $0.id == selectedRowId })
            {
                handleLeftArrowPress(for: selectedRow)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            selectPreviousRow()
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectNextRow()
            return .handled
        }
    }

    private func totalColumnWidths() -> CGFloat {
        return clipNameWidth + typeWidth + confidenceWidth + startTCWidth + endTCWidth
            + durationWidth + framesWidth + resolutionWidth + fpsWidth + statusWidth
    }

    // Keyboard navigation handlers
    private func handleRightArrowPress(for row: LinkingTableRow) {
        guard row.type == .ocfParent,
            let ocfFileName = row.ocfParent?.ocf.fileName
        else { return }

        // Expand the OCF if it's collapsed
        if !expandedOCFs.contains(ocfFileName) {
            expandedOCFs.insert(ocfFileName)
        }
    }

    private func handleLeftArrowPress(for row: LinkingTableRow) {
        guard row.type == .ocfParent,
            let ocfFileName = row.ocfParent?.ocf.fileName
        else { return }

        // Collapse the OCF if it's expanded
        if expandedOCFs.contains(ocfFileName) {
            expandedOCFs.remove(ocfFileName)
        }
    }

    // Navigation functions like Finder
    private func selectPreviousRow() {
        guard let currentSelectedId = selectedRowId,
            let currentIndex = tableData.firstIndex(where: { $0.id == currentSelectedId }),
            currentIndex > 0
        else {
            // If nothing selected or at top, select first row
            if !tableData.isEmpty {
                selectedRowId = tableData[0].id
            }
            return
        }

        selectedRowId = tableData[currentIndex - 1].id
    }

    private func selectNextRow() {
        guard let currentSelectedId = selectedRowId,
            let currentIndex = tableData.firstIndex(where: { $0.id == currentSelectedId }),
            currentIndex < tableData.count - 1
        else {
            // If nothing selected or at bottom, select last row
            if !tableData.isEmpty {
                selectedRowId = tableData[tableData.count - 1].id
            }
            return
        }

        selectedRowId = tableData[currentIndex + 1].id
    }
}

struct LinkingTableRow: Identifiable {
    let id = UUID()
    let type: RowType
    let ocfParent: OCFParent?
    let linkedSegment: LinkedSegment?
    let unmatchedFile: MediaFileInfo?
    let project: Project

    enum RowType {
        case ocfParent
        case linkedSegment
    }
}

struct LinkingTableRowView: View {
    let row: LinkingTableRow
    let clipNameWidth: CGFloat
    let typeWidth: CGFloat
    let confidenceWidth: CGFloat
    let startTCWidth: CGFloat
    let endTCWidth: CGFloat
    let durationWidth: CGFloat
    let framesWidth: CGFloat
    let resolutionWidth: CGFloat
    let fpsWidth: CGFloat
    let statusWidth: CGFloat
    let isEven: Bool
    @Binding var expandedOCFs: Set<String>
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Clip Name Column with disclosure triangles
            HStack(spacing: 4) {
                // Disclosure triangle for OCF parents, indentation for segments
                switch row.type {
                case .ocfParent:
                    Button(action: {
                        toggleOCFExpansion()
                    }) {
                        Image(systemName: isOCFExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                case .linkedSegment:
                    Color.clear.frame(width: 20)  // Indentation for child segments
                }

                // Icon
                switch row.type {
                case .ocfParent:
                    Image(systemName: "film.fill")
                        .foregroundColor(AppTheme.ocfColor)
                        .frame(width: 16)
                case .linkedSegment:
                    Image(systemName: "film")
                        .foregroundColor(AppTheme.segmentColor)
                        .frame(width: 16)
                }

                // Clip name
                Text(clipNameText)
                    .font(.monoNumbers(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .frame(width: clipNameWidth, alignment: .leading)
            .padding(.horizontal, 4)

            // Type Column
            Text(typeText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: typeWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // Confidence Column
            HStack(spacing: 4) {
                switch row.linkedSegment?.linkConfidence {
                case .high:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(width: 12)
                case .medium:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppTheme.segmentColor)
                        .frame(width: 12)
                case .low:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.red)
                        .frame(width: 12)
                default:
                    Color.clear.frame(width: 12)
                }

                Text(confidenceText)
                    .font(.system(size: 12))
                    .foregroundColor(confidenceColor)

                Spacer()
            }
            .frame(width: confidenceWidth, alignment: .leading)
            .padding(.horizontal, 4)

            // Start TC Column
            Text(startTCText)
                .font(.monoNumbers(size: 12))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: startTCWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // End TC Column
            Text(endTCText)
                .font(.monoNumbers(size: 12))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: endTCWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // Duration Column
            Text(durationText)
                .font(.monoNumbers(size: 12))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: durationWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // Frames Column
            Text(framesText)
                .font(.monoNumbers(size: 12))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: framesWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // Resolution Column
            Text(resolutionText)
                .font(.monoNumbers(size: 12))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: resolutionWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // FPS Column
            Text(fpsText)
                .font(.monoNumbers(size: 12))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: fpsWidth, alignment: .leading)
                .padding(.horizontal, 4)

            // Status Column
            HStack(spacing: 4) {
                switch row.type {
                case .ocfParent:
                    if row.project.blankRushFileExists(for: row.ocfParent?.ocf.fileName ?? "") {
                        Image(systemName: "film.fill")
                            .foregroundColor(.green)
                            .frame(width: 12)
                    } else {
                        Color.clear.frame(width: 12)
                    }
                case .linkedSegment:
                    if row.linkedSegment?.segment.isVFX == true {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.purple)
                            .frame(width: 12)
                    } else {
                        Color.clear.frame(width: 12)
                    }
                }

                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .frame(width: statusWidth, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    // Helper computed properties for data display
    private var clipNameText: String {
        switch row.type {
        case .ocfParent:
            return row.ocfParent?.ocf.fileName ?? ""
        case .linkedSegment:
            return row.linkedSegment?.segment.fileName ?? ""
        }
    }

    private var typeText: String {
        switch row.type {
        case .ocfParent:
            return "OCF"
        case .linkedSegment:
            return "Segment"
        }
    }

    private var confidenceText: String {
        switch row.type {
        case .ocfParent:
            if let parent = row.ocfParent {
                return "\(parent.childCount) linked"
            }
            return ""
        case .linkedSegment:
            return "\(row.linkedSegment?.linkConfidence ?? .none)".capitalized
        }
    }

    private var confidenceColor: Color {
        switch row.linkedSegment?.linkConfidence {
        case .high: return AppTheme.success
        case .medium: return AppTheme.warning
        case .low: return AppTheme.error
        default: return .secondary
        }
    }

    private var startTCText: String {
        switch row.type {
        case .ocfParent:
            return row.ocfParent?.ocf.sourceTimecode ?? ""
        case .linkedSegment:
            return row.linkedSegment?.segment.sourceTimecode ?? ""
        }
    }

    private var endTCText: String {
        switch row.type {
        case .ocfParent:
            return row.ocfParent?.ocf.endTimecode ?? ""
        case .linkedSegment:
            return row.linkedSegment?.segment.endTimecode ?? ""
        }
    }

    private var durationText: String {
        switch row.type {
        case .ocfParent:
            if let frames = row.ocfParent?.ocf.durationInFrames,
                let fps = row.ocfParent?.ocf.frameRate, fps > 0
            {
                let seconds = Float(frames) / fps
                return String(format: "%.2fs", seconds)
            }
            return ""
        case .linkedSegment:
            if let frames = row.linkedSegment?.segment.durationInFrames,
                let fps = row.linkedSegment?.segment.frameRate, fps > 0
            {
                let seconds = Float(frames) / fps
                return String(format: "%.2fs", seconds)
            }
            return ""
        }
    }

    private var framesText: String {
        switch row.type {
        case .ocfParent:
            if let frames = row.ocfParent?.ocf.durationInFrames {
                return "\(frames)"
            }
            return ""
        case .linkedSegment:
            if let frames = row.linkedSegment?.segment.durationInFrames {
                return "\(frames)"
            }
            return ""
        }
    }

    private var resolutionText: String {
        switch row.type {
        case .ocfParent:
            if let resolution = row.ocfParent?.ocf.resolution {
                return "\(Int(resolution.width))×\(Int(resolution.height))"
            }
            return ""
        case .linkedSegment:
            if let resolution = row.linkedSegment?.segment.resolution {
                return "\(Int(resolution.width))×\(Int(resolution.height))"
            }
            return ""
        }
    }

    private var fpsText: String {
        switch row.type {
        case .ocfParent:
            if let fps = row.ocfParent?.ocf.frameRate {
                return String(format: "%.3f", fps)
            }
            return ""
        case .linkedSegment:
            if let fps = row.linkedSegment?.segment.frameRate {
                return String(format: "%.3f", fps)
            }
            return ""
        }
    }

    private var statusText: String {
        switch row.type {
        case .ocfParent:
            if row.project.blankRushFileExists(for: row.ocfParent?.ocf.fileName ?? "") {
                return "Blank Rush Ready"
            }
            return "Ready for Rush"
        case .linkedSegment:
            if row.linkedSegment?.segment.isVFX == true {
                return "VFX Shot"
            }
            return "Linked"
        }
    }

    // Helper computed properties for disclosure triangle
    private var isOCFExpanded: Bool {
        guard let ocfFileName = row.ocfParent?.ocf.fileName else { return false }
        return expandedOCFs.contains(ocfFileName)
    }

    private func toggleOCFExpansion() {
        guard let ocfFileName = row.ocfParent?.ocf.fileName else { return }

        if expandedOCFs.contains(ocfFileName) {
            expandedOCFs.remove(ocfFileName)
        } else {
            expandedOCFs.insert(ocfFileName)
        }
    }
}
