//
//  CompressorStyleOCFCard.swift
//  SourcePrint
//
//  Main OCF card component with Apple Compressor styling
//

import ProResWriterCore
import SwiftUI
import AVFoundation
import CoreMedia

struct CompressorStyleOCFCard: View {
    let parent: OCFParent
    let ocfIndex: Int
    let project: Project
    let timelineVisualizationData: [String: TimelineVisualization]
    @Binding var selectedLinkedFiles: Set<String>
    @Binding var selectedOCFParents: Set<String>
    @Binding var focusedOCFIndex: Int
    @Binding var navigationContext: LinkingResultsView.NavigationContext
    let projectManager: ProjectManager
    let getSelectedParents: () -> [OCFParent]
    let allParents: [OCFParent]
    let currentlyRenderingOCF: String?  // Global lock to prevent concurrent rendering


    @State private var isExpanded: Bool = true  // Default to expanded
    @State private var isRendering = false
    @State private var renderProgress = ""
    @State private var renderStartTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var renderTimer: Timer?

    private var isSelected: Bool {
        selectedOCFParents.contains(parent.ocf.fileName)
    }

    private func handleCardSelection() {
        // Update navigation state
        focusedOCFIndex = ocfIndex
        navigationContext = .ocfList
        selectedLinkedFiles.removeAll()

        // Check if shift key is pressed for range selection
        let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
        let isShiftPressed = modifierFlags.contains(.shift)

        if isShiftPressed {
            handleRangeSelection()
        } else {
            // Simple toggle
            if selectedOCFParents.contains(parent.ocf.fileName) {
                selectedOCFParents.remove(parent.ocf.fileName)
            } else {
                selectedOCFParents.insert(parent.ocf.fileName)
            }
        }
    }

    private func handleRangeSelection() {
        // Find the last selected item to use as range start
        guard let lastSelectedFileName = selectedOCFParents.first,
              let lastIndex = allParents.firstIndex(where: { $0.ocf.fileName == lastSelectedFileName }),
              let currentIndex = allParents.firstIndex(where: { $0.ocf.fileName == parent.ocf.fileName }) else {
            // No previous selection, just select this one
            selectedOCFParents.insert(parent.ocf.fileName)
            return
        }

        let startIndex = min(lastIndex, currentIndex)
        let endIndex = max(lastIndex, currentIndex)

        // Select all items in the range
        for i in startIndex...endIndex {
            selectedOCFParents.insert(allParents[i].ocf.fileName)
        }
    }

    private func startRendering() {
        guard !isRendering else { return }

        // Check global rendering lock - only proceed if this card is the one that should render
        if let rendering = currentlyRenderingOCF, rendering != parent.ocf.fileName {
            NSLog("⏸️ Skipping %@ - another OCF is currently rendering (%@)", parent.ocf.fileName, rendering)
            return
        }

        // Check if blank rush exists
        let blankRushStatus = project.blankRushStatus[parent.ocf.fileName] ?? .notCreated

        switch blankRushStatus {
        case .completed(_, let blankRushURL):
            // Verify blank rush file actually exists on disk
            if FileManager.default.fileExists(atPath: blankRushURL.path) {
                // Blank rush exists - proceed directly to render
                beginRender(with: blankRushURL)
            } else {
                // Status says completed but file is missing - regenerate
                NSLog("⚠️ Blank rush file missing for \(parent.ocf.fileName) - regenerating")
                project.blankRushStatus[parent.ocf.fileName] = .notCreated
                // Don't save here - will save after blank rush creation completes
                startRendering() // Retry - will hit .notCreated case
            }

        case .notCreated:
            // No blank rush - create it first, then render
            NSLog("📝 No blank rush exists for \(parent.ocf.fileName) - creating automatically")
            isRendering = true
            renderStartTime = Date()
            elapsedTime = 0
            renderProgress = "Creating blank rush..."

            // Start timer
            renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
                if let startTime = renderStartTime {
                    elapsedTime = Date().timeIntervalSince(startTime)
                }
            }

            Task {
                if let blankRushURL = await generateBlankRushForOCF() {
                    // Blank rush created successfully - proceed to render
                    await MainActor.run {
                        renderProgress = "Blank rush ready - rendering..."
                    }
                    await renderOCF(blankRushURL: blankRushURL)
                } else {
                    // Blank rush creation failed
                    await MainActor.run {
                        stopRendering()
                        NSLog("❌ Failed to create blank rush for \(parent.ocf.fileName)")
                    }
                }
            }

        case .inProgress:
            // Check if blank rush file exists from previous incomplete creation
            let expectedURL = project.blankRushDirectory.appendingPathComponent("\(parent.ocf.fileName)_blank.mov")

            if FileManager.default.fileExists(atPath: expectedURL.path) {
                // File exists - verify it's a valid video file using MediaAnalyzer
                NSLog("🔍 Validating stuck .inProgress blank rush for \(parent.ocf.fileName)...")
                Task {
                    let isValid = await isValidBlankRush(at: expectedURL)

                    await MainActor.run {
                        if isValid {
                            // File is valid - mark as completed and use it
                            NSLog("✅ Found valid blank rush file for stuck .inProgress status: \(parent.ocf.fileName)")
                            project.blankRushStatus[parent.ocf.fileName] = .completed(date: Date(), url: expectedURL)
                            // Save will happen after render completes
                            beginRender(with: expectedURL)
                        } else {
                            // File is invalid/corrupted - reset and regenerate
                            NSLog("⚠️ Invalid blank rush file for .inProgress status - regenerating: \(parent.ocf.fileName)")
                            project.blankRushStatus[parent.ocf.fileName] = .notCreated
                            // Save will happen after blank rush creation completes
                            startRendering()
                        }
                    }
                }
            } else {
                // Status is .inProgress but file doesn't exist - reset to .notCreated
                NSLog("⚠️ Blank rush stuck in .inProgress but file missing for \(parent.ocf.fileName) - resetting")
                project.blankRushStatus[parent.ocf.fileName] = .notCreated
                // Save will happen after blank rush creation completes
                startRendering() // Retry - will hit .notCreated case
            }

        case .failed(let error):
            // Allow retry by resetting to .notCreated
            NSLog("⚠️ Previous blank rush creation failed for \(parent.ocf.fileName): \(error) - retrying")
            project.blankRushStatus[parent.ocf.fileName] = .notCreated
            // Save will happen after blank rush creation completes
            startRendering()
        }
    }

    /// Validate that a blank rush file is actually a valid, readable video file
    private func isValidBlankRush(at url: URL) async -> Bool {
        do {
            // Use MediaAnalyzer to verify it's a valid video file
            let _ = try await MediaAnalyzer().analyzeMediaFile(at: url, type: .gradedSegment)
            return true
        } catch {
            NSLog("⚠️ Blank rush validation failed for \(url.lastPathComponent): \(error)")
            return false
        }
    }

    private func beginRender(with blankRushURL: URL) {
        isRendering = true
        renderStartTime = Date()
        elapsedTime = 0
        renderProgress = "Rendering..."

        // Start timer
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            if let startTime = renderStartTime {
                elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        Task {
            await renderOCF(blankRushURL: blankRushURL)
        }
    }

    private func stopRendering() {
        renderTimer?.invalidate()
        renderTimer = nil
        isRendering = false
        renderProgress = ""
        renderStartTime = nil
        elapsedTime = 0
    }

    @MainActor
    private func generateBlankRushForOCF() async -> URL? {
        renderProgress = "Creating blank rush..."

        // Mark as in progress
        project.blankRushStatus[parent.ocf.fileName] = .inProgress
        // Don't save here - status updates will be saved after completion

        // Create single-file linking result for this OCF
        let singleOCFResult = LinkingResult(
            ocfParents: [parent],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )

        let blankRushCreator = BlankRushIntermediate(projectDirectory: project.blankRushDirectory.path)

        // Create blank rush with progress callback
        let results = await blankRushCreator.createBlankRushes(from: singleOCFResult) { clipName, current, total, fps in
            await MainActor.run {
                self.renderProgress = "Creating blank rush... \(Int((current/total) * 100))%"
            }
        }

        // Process result
        if let result = results.first {
            if result.success {
                project.blankRushStatus[result.originalOCF.fileName] = .completed(date: Date(), url: result.blankRushURL)
                // Save will happen after render completes
                NSLog("✅ Created blank rush for \(parent.ocf.fileName): \(result.blankRushURL.lastPathComponent)")
                return result.blankRushURL
            } else {
                let errorMessage = result.error ?? "Unknown error"
                project.blankRushStatus[result.originalOCF.fileName] = .failed(error: errorMessage)
                // Save will happen when status is checked
                NSLog("❌ Failed to create blank rush for \(parent.ocf.fileName): \(errorMessage)")
                return nil
            }
        }

        return nil
    }

    @MainActor
    private func renderOCF(blankRushURL: URL) async {
        renderProgress = "Creating composition..."

        do {
            // Generate output filename
            let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
            let outputFileName = "\(baseName).mov"
            let outputURL = project.outputDirectory.appendingPathComponent(outputFileName)

            // Create SwiftFFmpeg compositor
            let compositor = SwiftFFmpegProResCompositor()

            // Convert linked children to FFmpegGradedSegments
            var ffmpegGradedSegments: [FFmpegGradedSegment] = []
            for child in parent.children {
                let segmentInfo = child.segment

                if let segmentTC = segmentInfo.sourceTimecode,
                   let baseTC = parent.ocf.sourceTimecode,
                   let segmentFrameRate = segmentInfo.frameRate,
                   let segmentFrameRateFloat = segmentInfo.frameRateFloat,
                   let duration = segmentInfo.durationInFrames {

                    let smpte = SMPTE(fps: Double(segmentFrameRateFloat), dropFrame: segmentInfo.isDropFrame ?? false)

                    do {
                        let segmentFrames = try smpte.getFrames(tc: segmentTC)
                        let baseFrames = try smpte.getFrames(tc: baseTC)
                        let relativeFrames = segmentFrames - baseFrames

                        let startTime = CMTime(
                            value: CMTimeValue(relativeFrames),
                            timescale: CMTimeScale(segmentFrameRateFloat)
                        )

                        let segmentDuration = CMTime(
                            seconds: Double(duration) / Double(segmentFrameRateFloat),
                            preferredTimescale: CMTimeScale(segmentFrameRateFloat * 1000)
                        )

                        let ffmpegSegment = FFmpegGradedSegment(
                            url: segmentInfo.url,
                            startTime: startTime,
                            duration: segmentDuration,
                            sourceStartTime: .zero,
                            isVFXShot: segmentInfo.isVFXShot ?? false,
                            sourceTimecode: segmentInfo.sourceTimecode,
                            frameRate: segmentFrameRateFloat,
                            frameRateRational: segmentFrameRate,
                            isDropFrame: segmentInfo.isDropFrame
                        )
                        ffmpegGradedSegments.append(ffmpegSegment)
                    } catch {
                        NSLog("⚠️ SMPTE calculation failed for \(segmentInfo.fileName): \(error)")
                        continue
                    }
                }
            }

            guard !ffmpegGradedSegments.isEmpty else {
                NSLog("❌ No valid FFmpeg graded segments for \(parent.ocf.fileName)")
                await MainActor.run {
                    stopRendering()
                }
                return
            }

            // Setup compositor settings
            let settings = FFmpegCompositorSettings(
                outputURL: outputURL,
                baseVideoURL: blankRushURL,
                gradedSegments: ffmpegGradedSegments,
                proResProfile: "4"
            )

            compositor.progressHandler = nil

            // Process composition
            let compositionStartTime = Date()
            let result = await withCheckedContinuation { continuation in
                compositor.completionHandler = { result in
                    continuation.resume(returning: result)
                }
                compositor.composeVideo(with: settings)
            }

            let compositionDuration = Date().timeIntervalSince(compositionStartTime)

            await MainActor.run {
                switch result {
                case .success(let finalOutputURL):
                    let printRecord = PrintRecord(
                        date: Date(),
                        outputURL: finalOutputURL,
                        segmentCount: ffmpegGradedSegments.count,
                        duration: compositionDuration,
                        success: true
                    )
                    project.addPrintRecord(printRecord)
                    project.printStatus[parent.ocf.fileName] = .printed(date: Date(), outputURL: finalOutputURL)

                    // Clear modification dates for printed segments
                    for child in parent.children {
                        if project.segmentModificationDates[child.segment.fileName] != nil {
                            project.segmentModificationDates.removeValue(forKey: child.segment.fileName)
                        }
                    }

                    projectManager.saveProject(project)
                    NSLog("✅ Composition completed: \(finalOutputURL.lastPathComponent)")

                case .failure(let error):
                    let printRecord = PrintRecord(
                        date: Date(),
                        outputURL: outputURL,
                        segmentCount: ffmpegGradedSegments.count,
                        duration: compositionDuration,
                        success: false
                    )
                    project.addPrintRecord(printRecord)
                    projectManager.saveProject(project)
                    NSLog("❌ Composition failed: \(error)")
                }

                stopRendering()
            }

        } catch {
            await MainActor.run {
                NSLog("❌ Print process error for \(parent.ocf.fileName): \(error)")
                stopRendering()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compressor-style header (title bar)
            HStack {
                // OCF filename as main title (clickable)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        // Save expansion state to project
                        project.ocfCardExpansionState[parent.ocf.fileName] = isExpanded
                        projectManager.saveProject(project)
                    }
                }) {
                    Text(parent.ocf.fileName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                    Spacer()

                    // Status indicators (from original header)
                    HStack(spacing: 8) {
                        // Print Status
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                if let printStatus = project.printStatus[parent.ocf.fileName] {
                                    Image(systemName: printStatus.icon)
                                        .foregroundColor(printStatus.color)
                                    Text(printStatus.displayName)
                                        .font(.caption)
                                        .foregroundColor(printStatus.color)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                    Text("Not Printed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Render State Display
                        if isRendering {
                            Button(action: {
                                stopRendering()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundColor(.red)
                                    Text(String(format: "%.1fs", elapsedTime))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: {
                                startRendering()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text("Render")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // Chevron indicator with fixed width and larger click area
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                                // Save expansion state to project
                                project.ocfCardExpansionState[parent.ocf.fileName] = isExpanded
                                projectManager.saveProject(project)
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.3) : Color.appBackgroundSecondary)
            .onTapGesture {
                handleCardSelection()
            }

            // Render Progress Bar (shown when rendering, whether expanded or collapsed)
            if isRendering {
                VStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    Text(renderProgress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.appBackgroundSecondary)
            }

            // Card body (expandable content)
            if isExpanded {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Timeline
                        if let timelineData = timelineVisualizationData[parent.ocf.fileName] {
                            TimelineChartView(
                                visualizationData: timelineData,
                                ocfFileName: parent.ocf.fileName,
                                selectedSegmentFileName: selectedLinkedFiles.first
                            )
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }

                        // Render Log Section
                        RenderLogSection(
                            project: project,
                            ocfFileName: parent.ocf.fileName
                        )

                        // Linked segments container - keyboard navigation handled at LinkingResultsView level
                        VStack(spacing: 0) {
                            ForEach(Array(sortedByTimecode(parent.children).enumerated()), id: \.element.segment.fileName) { index, linkedSegment in
                                TreeLinkedSegmentRowView(
                                    linkedSegment: linkedSegment,
                                    isLast: linkedSegment.segment.fileName
                                        == sortedByTimecode(parent.children).last?.segment.fileName,
                                    project: project
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .onTapGesture {
                                    // Update navigation state
                                    focusedOCFIndex = ocfIndex
                                    navigationContext = .segmentList
                                    selectedLinkedFiles = [linkedSegment.segment.fileName]
                                    selectedOCFParents = [parent.ocf.fileName]
                                }
                                .background(
                                    selectedLinkedFiles.contains(linkedSegment.segment.fileName)
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                                )
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.appBackgroundTertiary.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 0)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.appBackgroundSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onReceive(NotificationCenter.default.publisher(for: .expandSelectedCards)) { _ in
            if isSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
                // Save expansion state to project
                project.ocfCardExpansionState[parent.ocf.fileName] = true
                projectManager.saveProject(project)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseSelectedCards)) { _ in
            if isSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
                // Save expansion state to project
                project.ocfCardExpansionState[parent.ocf.fileName] = false
                projectManager.saveProject(project)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseAllCards)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = false
            }
            // Update state but don't save (batch collapse shouldn't trigger multiple saves)
            project.ocfCardExpansionState[parent.ocf.fileName] = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .renderOCF)) { notification in
            if let userInfo = notification.userInfo,
               let ocfFileName = userInfo["ocfFileName"] as? String,
               ocfFileName == parent.ocf.fileName {
                startRendering()
            }
        }
        .onAppear {
            // Initialize expansion state from project (default to true if not set)
            isExpanded = project.ocfCardExpansionState[parent.ocf.fileName] ?? true
        }
    }
}
