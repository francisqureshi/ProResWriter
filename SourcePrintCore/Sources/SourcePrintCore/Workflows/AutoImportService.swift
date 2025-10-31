import Foundation

/// Result of auto-import processing containing all state changes
public struct AutoImportResult {
    /// Files that should be imported
    public let filesToImport: [URL]

    /// Files that should be marked as offline
    public let offlineFiles: Set<String>

    /// Metadata for offline files
    public let offlineMetadata: [String: OfflineFileMetadata]

    /// Files that were modified
    public let modifiedFiles: Set<String>

    /// Updated modification dates
    public let modificationDates: [String: Date]

    /// Updated file sizes
    public let updatedFileSizes: [String: Int64]

    /// OCFs that need re-printing
    public let ocfsNeedingReprint: Set<String>

    /// Print status updates for OCFs
    public let printStatusUpdates: [String: (needsReprint: Bool, reason: String?, lastPrintDate: Date?)]

    /// Files that returned from offline (unchanged)
    public let returningUnchanged: Set<String>

    public init(
        filesToImport: [URL] = [],
        offlineFiles: Set<String> = [],
        offlineMetadata: [String: OfflineFileMetadata] = [:],
        modifiedFiles: Set<String> = [],
        modificationDates: [String: Date] = [:],
        updatedFileSizes: [String: Int64] = [:],
        ocfsNeedingReprint: Set<String> = [],
        printStatusUpdates: [String: (needsReprint: Bool, reason: String?, lastPrintDate: Date?)] = [:],
        returningUnchanged: Set<String> = []
    ) {
        self.filesToImport = filesToImport
        self.offlineFiles = offlineFiles
        self.offlineMetadata = offlineMetadata
        self.modifiedFiles = modifiedFiles
        self.modificationDates = modificationDates
        self.updatedFileSizes = updatedFileSizes
        self.ocfsNeedingReprint = ocfsNeedingReprint
        self.printStatusUpdates = printStatusUpdates
        self.returningUnchanged = returningUnchanged
    }
}

/// Service for processing auto-import file detection and classification
public class AutoImportService {

    /// Process detected new files and classify them
    ///
    /// - Parameters:
    ///   - files: Detected files from watch folder
    ///   - isVFX: Whether files are from VFX folder
    ///   - existingSegments: Currently imported segments
    ///   - offlineFiles: Set of offline file names
    ///   - offlineMetadata: Metadata for offline files
    ///   - trackedSizes: Tracked file sizes
    ///   - linkingResult: Current linking result
    ///   - autoImportEnabled: Whether auto-import is enabled
    /// - Returns: Result with files to import and state changes
    public static func processDetectedFiles(
        files: [URL],
        isVFX: Bool,
        existingSegments: [MediaFileInfo],
        offlineFiles: Set<String>,
        offlineMetadata: [String: OfflineFileMetadata],
        trackedSizes: [String: Int64],
        linkingResult: LinkingResult?,
        autoImportEnabled: Bool
    ) -> AutoImportResult {
        guard autoImportEnabled else {
            NSLog("⚠️ Auto-import disabled, ignoring detected files")
            return AutoImportResult()
        }

        // Use FileChangeDetector for classification
        let classification = FileChangeDetector.classifyFiles(
            detectedFiles: files,
            existingSegments: existingSegments,
            offlineFiles: offlineFiles,
            offlineMetadata: offlineMetadata,
            trackedSizes: trackedSizes
        )

        var offlineFilesToRemove = Set<String>()
        var offlineMetadataToRemove = Set<String>()
        var modifiedFiles = Set<String>()
        var modificationDates: [String: Date] = [:]
        var updatedFileSizes: [String: Int64] = [:]
        var ocfsNeedingReprint = Set<String>()
        var printStatusUpdates: [String: (Bool, String?, Date?)] = [:]
        var returningUnchanged = Set<String>()

        // Handle returning offline files (same size - just remove offline status)
        for url in classification.returningUnchanged {
            let fileName = url.lastPathComponent
            offlineFilesToRemove.insert(fileName)
            offlineMetadataToRemove.insert(fileName)
            returningUnchanged.insert(fileName)
            NSLog("✅ File %@ is back online", fileName)
        }

        // Combine returning changed files and existing modified files
        let changedFiles = classification.returningChanged + classification.existingModified

        // Handle changed files (different size - treat as modified)
        for url in changedFiles {
            let fileName = url.lastPathComponent
            offlineFilesToRemove.insert(fileName)
            offlineMetadataToRemove.insert(fileName)
            modifiedFiles.insert(fileName)
            modificationDates[fileName] = Date()

            // Update file size metadata with new size
            if case .success(let newSize) = FileSystemOperations.getFileSize(for: url) {
                updatedFileSizes[fileName] = newSize
                NSLog("📊 Updated size for changed file: %@ (new size: %lld bytes)", fileName, newSize)
            }

            NSLog("✅ File %@ is back online and marked as modified", fileName)

            // Mark affected OCFs for re-print
            if let linkingResult = linkingResult {
                for ocfParent in linkingResult.ocfParents {
                    for child in ocfParent.children {
                        if child.segment.fileName == fileName {
                            ocfsNeedingReprint.insert(ocfParent.ocf.fileName)
                            printStatusUpdates[ocfParent.ocf.fileName] = (true, "segmentModified", Date())
                        }
                    }
                }
            }
        }

        // Import truly new files
        if classification.newFiles.isEmpty {
            if classification.returningUnchanged.isEmpty && changedFiles.isEmpty {
                NSLog("⚠️ All detected files already imported, ignoring %d file(s)", files.count)
            }
        } else {
            NSLog("🎬 Auto-importing %d new %@ files...", classification.newFiles.count, isVFX ? "VFX" : "grade")
        }

        return AutoImportResult(
            filesToImport: classification.newFiles,
            offlineFiles: offlineFilesToRemove,
            offlineMetadata: offlineMetadataToRemove.reduce(into: [:]) { result, key in
                result[key] = nil  // Mark for removal
            },
            modifiedFiles: modifiedFiles,
            modificationDates: modificationDates,
            updatedFileSizes: updatedFileSizes,
            ocfsNeedingReprint: ocfsNeedingReprint,
            printStatusUpdates: printStatusUpdates,
            returningUnchanged: returningUnchanged
        )
    }

    /// Process deleted files from watch folder
    ///
    /// - Parameters:
    ///   - fileNames: Names of deleted files
    ///   - isVFX: Whether files are from VFX folder
    ///   - existingSegments: Currently imported segments
    ///   - trackedSizes: Tracked file sizes
    ///   - linkingResult: Current linking result
    /// - Returns: Result with offline files to mark and state changes
    public static func processDeletedFiles(
        fileNames: [String],
        isVFX: Bool,
        existingSegments: [MediaFileInfo],
        trackedSizes: [String: Int64],
        linkingResult: LinkingResult?
    ) -> AutoImportResult {
        NSLog("📤 Marking %d deleted %@ files as offline...", fileNames.count, isVFX ? "VFX" : "grade")

        var offlineFiles = Set<String>()
        var offlineMetadata: [String: OfflineFileMetadata] = [:]
        var ocfsNeedingReprint = Set<String>()
        var printStatusUpdates: [String: (Bool, String?, Date?)] = [:]
        var markedCount = 0

        for fileName in fileNames {
            if existingSegments.contains(where: { $0.fileName == fileName }) {
                offlineFiles.insert(fileName)

                // Store metadata using pre-stored file size
                if let fileSize = trackedSizes[fileName] {
                    let metadata = OfflineFileMetadata(
                        fileName: fileName,
                        fileSize: fileSize,
                        offlineDate: Date(),
                        partialHash: nil  // Hash will be computed on return if needed
                    )
                    offlineMetadata[fileName] = metadata
                    NSLog("📊 Stored metadata for offline file: %@ (size: %lld bytes)", fileName, fileSize)
                } else {
                    NSLog("⚠️ No pre-stored size for %@ - will use hash fallback on return", fileName)
                }

                markedCount += 1
            }
        }

        if markedCount > 0 {
            NSLog("✅ Marked %d deleted %@ files as offline", markedCount, isVFX ? "VFX" : "grade")

            // Mark affected OCFs for re-print
            if let linkingResult = linkingResult {
                for fileName in fileNames where offlineFiles.contains(fileName) {
                    for ocfParent in linkingResult.ocfParents {
                        for child in ocfParent.children {
                            if child.segment.fileName == fileName {
                                ocfsNeedingReprint.insert(ocfParent.ocf.fileName)
                                printStatusUpdates[ocfParent.ocf.fileName] = (true, "segmentOffline", Date())
                                NSLog("⚠️ OCF %@ needs reprint due to offline segment", ocfParent.ocf.fileName)
                            }
                        }
                    }
                }
            }
        } else {
            NSLog("⚠️ No matching files found to mark offline for deleted %@ files", isVFX ? "VFX" : "grade")
        }

        return AutoImportResult(
            offlineFiles: offlineFiles,
            offlineMetadata: offlineMetadata,
            ocfsNeedingReprint: ocfsNeedingReprint,
            printStatusUpdates: printStatusUpdates
        )
    }

    /// Process modified files from watch folder
    ///
    /// - Parameters:
    ///   - fileNames: Names of modified files
    ///   - isVFX: Whether files are from VFX folder
    ///   - existingSegments: Currently imported segments
    ///   - linkingResult: Current linking result
    /// - Returns: Result with modification dates and OCFs needing reprint
    public static func processModifiedFiles(
        fileNames: [String],
        isVFX: Bool,
        existingSegments: [MediaFileInfo],
        linkingResult: LinkingResult?
    ) -> AutoImportResult {
        NSLog("📝 Handling %d modified %@ files...", fileNames.count, isVFX ? "VFX" : "grade")

        var modifiedFiles = Set<String>()
        var modificationDates: [String: Date] = [:]
        var updatedFileSizes: [String: Int64] = [:]
        var ocfsNeedingReprint = Set<String>()
        var printStatusUpdates: [String: (Bool, String?, Date?)] = [:]

        for fileName in fileNames {
            // Find segment by filename
            if let segment = existingSegments.first(where: { $0.fileName == fileName }) {
                NSLog("📝 Found modified segment: %@", fileName)

                // Update the segment's modification date to mark it as changed
                modifiedFiles.insert(fileName)
                modificationDates[fileName] = Date()

                // Update file size for modified segment
                if case .success(let fileSize) = FileSystemOperations.getFileSize(for: segment.url) {
                    updatedFileSizes[fileName] = fileSize
                    NSLog("📊 Updated size for modified segment: %@ (size: %lld bytes)", fileName, fileSize)
                }

                // Find linked OCF files that use this segment
                if let linkingResult = linkingResult {
                    for ocfParent in linkingResult.ocfParents {
                        for child in ocfParent.children {
                            if child.segment.fileName == fileName {
                                ocfsNeedingReprint.insert(ocfParent.ocf.fileName)
                                printStatusUpdates[ocfParent.ocf.fileName] = (true, "segmentModified", Date())
                                NSLog("📝 Segment %@ affects OCF: %@", fileName, ocfParent.ocf.fileName)
                            }
                        }
                    }
                }
            }
        }

        if !ocfsNeedingReprint.isEmpty {
            NSLog(
                "✅ Marked %d OCFs as needing re-print due to %d modified %@ files",
                ocfsNeedingReprint.count, fileNames.count, isVFX ? "VFX" : "grade")
        }

        return AutoImportResult(
            modifiedFiles: modifiedFiles,
            modificationDates: modificationDates,
            updatedFileSizes: updatedFileSizes,
            ocfsNeedingReprint: ocfsNeedingReprint,
            printStatusUpdates: printStatusUpdates
        )
    }

    /// Process startup changes (combines modification detection and new file scanning)
    ///
    /// - Parameters:
    ///   - service: WatchFolderService instance
    ///   - existingSegments: Currently imported segments
    ///   - trackedSizes: Tracked file sizes
    ///   - linkingResult: Current linking result
    ///   - autoImportEnabled: Whether auto-import is enabled
    /// - Returns: Result with all detected changes and files to import
    public static func processStartupChanges(
        service: WatchFolderService,
        existingSegments: [MediaFileInfo],
        trackedSizes: [String: Int64],
        linkingResult: LinkingResult?,
        autoImportEnabled: Bool
    ) async -> (modifications: AutoImportResult, newFiles: (gradeFiles: [URL], vfxFiles: [URL])) {
        // 1. Detect changes to known segments (modifications and deletions)
        let changes = service.detectChangesOnStartup(
            knownSegments: existingSegments,
            trackedSizes: trackedSizes
        )

        var modifiedFiles = Set<String>()
        var modificationDates: [String: Date] = [:]
        var updatedFileSizes: [String: Int64] = [:]
        var offlineFiles = Set<String>()
        var offlineMetadata: [String: OfflineFileMetadata] = [:]
        var ocfsNeedingReprint = Set<String>()
        var printStatusUpdates: [String: (Bool, String?, Date?)] = [:]

        // Handle modified files
        for fileName in changes.modifiedFiles {
            modifiedFiles.insert(fileName)
            modificationDates[fileName] = Date()

            // Update size
            if let sizeChange = changes.sizeChanges[fileName] {
                updatedFileSizes[fileName] = sizeChange.new
            }

            // Mark affected OCFs for re-print
            if let linkingResult = linkingResult {
                for ocfParent in linkingResult.ocfParents {
                    for child in ocfParent.children {
                        if child.segment.fileName == fileName {
                            ocfsNeedingReprint.insert(ocfParent.ocf.fileName)
                            printStatusUpdates[ocfParent.ocf.fileName] = (true, "segmentModified", Date())
                        }
                    }
                }
            }
        }

        // Handle deleted files
        for fileName in changes.deletedFiles {
            offlineFiles.insert(fileName)

            // Store metadata
            if let storedSize = trackedSizes[fileName] {
                let metadata = OfflineFileMetadata(
                    fileName: fileName,
                    fileSize: storedSize,
                    offlineDate: Date(),
                    partialHash: nil
                )
                offlineMetadata[fileName] = metadata
            }
        }

        let modificationsResult = AutoImportResult(
            offlineFiles: offlineFiles,
            offlineMetadata: offlineMetadata,
            modifiedFiles: modifiedFiles,
            modificationDates: modificationDates,
            updatedFileSizes: updatedFileSizes,
            ocfsNeedingReprint: ocfsNeedingReprint,
            printStatusUpdates: printStatusUpdates
        )

        // 2. Scan for NEW files added while app was closed
        let newFiles = await service.scanForNewFiles(knownSegments: existingSegments)

        return (modificationsResult, newFiles)
    }
}
