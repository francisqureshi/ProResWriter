//
//  OCFParentContextMenu.swift
//  SourcePrint
//
//  Context menu for OCF parent cards
//

import ProResWriterCore
import SwiftUI

struct OCFParentContextMenu: View {
    let parent: OCFParent
    @ObservedObject var project: Project
    @ObservedObject var projectManager: ProjectManager
    let selectedParents: [OCFParent]
    let allParents: [OCFParent]
    
    // Determine which parents to operate on - selected parents if multiple are selected, otherwise just the clicked parent
    private var operatingParents: [OCFParent] {
        return selectedParents.count > 1 ? selectedParents : [parent]
    }
    
    private var isBlankRushReady: Bool {
        if operatingParents.count == 1 {
            return project.blankRushFileExists(for: parent.ocf.fileName)
        } else {
            // For multiple selection, check if ANY have blank rushes ready
            return operatingParents.contains { project.blankRushFileExists(for: $0.ocf.fileName) }
        }
    }
    
    private var isAlreadyInQueue: Bool {
        if operatingParents.count == 1 {
            return project.renderQueue.contains { $0.ocfFileName == parent.ocf.fileName && $0.status != .completed }
        } else {
            // For multiple selection, check if ALL are already in queue
            return operatingParents.allSatisfy { parent in
                project.renderQueue.contains { $0.ocfFileName == parent.ocf.fileName && $0.status != .completed }
            }
        }
    }
    
    private var eligibleParentsForQueue: [OCFParent] {
        return operatingParents.filter { parent in
            project.blankRushFileExists(for: parent.ocf.fileName) &&
            !project.renderQueue.contains { $0.ocfFileName == parent.ocf.fileName && $0.status != .completed }
        }
    }
    
    private var hasModifiedSegments: Bool {
        // Check if any segments for this OCF have been modified since last print
        guard let printStatus = project.printStatus[parent.ocf.fileName],
              case .printed(let lastPrintDate, _) = printStatus else {
            return false
        }
        
        for child in parent.children {
            let segmentFileName = child.segment.fileName
            if let fileModDate = getFileModificationDate(for: child.segment.url),
               fileModDate > lastPrintDate {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        Group {
            // Add to Render Queue
            Button(operatingParents.count > 1 ? "Add \(operatingParents.count) Items to Render Queue" : "Add to Render Queue") {
                addToRenderQueue()
            }
            .disabled(eligibleParentsForQueue.isEmpty)
            
            if eligibleParentsForQueue.count != operatingParents.count && operatingParents.count > 1 {
                Text("\(eligibleParentsForQueue.count)/\(operatingParents.count) items eligible")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Blank Rush Management
            if operatingParents.count == 1 {
                if project.blankRushFileExists(for: parent.ocf.fileName) {
                    Button("Regenerate Blank Rush", systemImage: "film.fill") {
                        regenerateBlankRush()
                    }
                }
            }

            // Only show print status actions for single item context menus
            if operatingParents.count == 1 {
                Divider()
                
                // Print status actions
                if let printStatus = project.printStatus[parent.ocf.fileName] {
                switch printStatus {
                case .printed:
                    if hasModifiedSegments {
                        Button("Mark for Re-print (Segments Modified)", systemImage: "exclamationmark.circle") {
                            project.printStatus[parent.ocf.fileName] = .needsReprint(
                                lastPrintDate: Date(),
                                reason: .segmentModified
                            )
                            projectManager.saveProject(project)
                        }
                    } else {
                        Button("Force Re-print", systemImage: "arrow.clockwise") {
                            project.printStatus[parent.ocf.fileName] = .needsReprint(
                                lastPrintDate: Date(),
                                reason: .manualRequest
                            )
                            projectManager.saveProject(project)
                        }
                    }
                    
                case .needsReprint:
                    Button("Clear Re-print Flag", systemImage: "checkmark.circle") {
                        // Find the last successful print date
                        if let lastSuccessfulPrint = project.printHistory
                            .filter({ $0.success && $0.outputURL.lastPathComponent.contains((parent.ocf.fileName as NSString).deletingPathExtension) })
                            .max(by: { $0.date < $1.date }) {
                            project.printStatus[parent.ocf.fileName] = .printed(date: lastSuccessfulPrint.date, outputURL: lastSuccessfulPrint.outputURL)
                        } else {
                            project.printStatus.removeValue(forKey: parent.ocf.fileName)
                        }
                        projectManager.saveProject(project)
                    }
                    
                case .notPrinted:
                    EmptyView()
                }
                }
            }
        }
    }
    
    private func addToRenderQueue() {
        let parentsToAdd = eligibleParentsForQueue
        var addedCount = 0

        for parent in parentsToAdd {
            let queueItem = RenderQueueItem(ocfFileName: parent.ocf.fileName)
            project.renderQueue.append(queueItem)
            addedCount += 1
        }

        projectManager.saveProject(project)

        if addedCount == 1 {
            NSLog("➕ Added \(parentsToAdd.first!.ocf.fileName) to render queue")
        } else {
            NSLog("➕ Added \(addedCount) items to render queue")
        }
    }

    private func regenerateBlankRush() {
        NSLog("🔄 Regenerating blank rush for \(parent.ocf.fileName)")

        // Mark as in progress
        project.blankRushStatus[parent.ocf.fileName] = .inProgress
        projectManager.saveProject(project)

        // Create single-file linking result for this OCF
        let singleOCFResult = LinkingResult(
            ocfParents: [parent],
            unmatchedSegments: [],
            unmatchedOCFs: []
        )

        Task {
            let blankRushCreator = BlankRushIntermediate(projectDirectory: project.blankRushDirectory.path)

            // Create blank rush
            let results = await blankRushCreator.createBlankRushes(from: singleOCFResult) { clipName, current, total, fps in
                // No progress UI needed for context menu action
            }

            await MainActor.run {
                if let result = results.first {
                    if result.success {
                        project.blankRushStatus[result.originalOCF.fileName] = .completed(date: Date(), url: result.blankRushURL)
                        projectManager.saveProject(project)
                        NSLog("✅ Regenerated blank rush for \(parent.ocf.fileName): \(result.blankRushURL.lastPathComponent)")
                    } else {
                        let errorMessage = result.error ?? "Unknown error"
                        project.blankRushStatus[result.originalOCF.fileName] = .failed(error: errorMessage)
                        projectManager.saveProject(project)
                        NSLog("❌ Failed to regenerate blank rush for \(parent.ocf.fileName): \(errorMessage)")
                    }
                }
            }
        }
    }

    private func getFileModificationDate(for url: URL) -> Date? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            return nil
        }
    }
}

