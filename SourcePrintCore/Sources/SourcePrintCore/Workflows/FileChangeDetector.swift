import Foundation

/// Classifies detected files into categories based on their relationship to known files
public enum FileChangeDetector {

    /// Classify detected video files into new, returning, or changed categories
    ///
    /// - Parameters:
    ///   - detectedFiles: Files detected by watch folder
    ///   - existingSegments: Segments already imported in project
    ///   - offlineFiles: Set of files marked as offline
    ///   - offlineMetadata: Metadata for offline files (size, hash)
    ///   - trackedSizes: Current file sizes for online segments
    /// - Returns: Classification of all detected files
    public static func classifyFiles(
        detectedFiles: [URL],
        existingSegments: [MediaFileInfo],
        offlineFiles: Set<String>,
        offlineMetadata: [String: OfflineFileMetadata],
        trackedSizes: [String: Int64]
    ) -> FileClassification {

        let existingFileNames = Set(existingSegments.map { $0.fileName })

        var newFiles: [URL] = []
        var returningUnchanged: [URL] = []
        var returningChanged: [URL] = []
        var existingModified: [URL] = []

        for url in detectedFiles {
            let fileName = url.lastPathComponent

            if offlineFiles.contains(fileName) {
                // File is returning from offline state
                let classification = classifyReturningFile(
                    url: url,
                    fileName: fileName,
                    metadata: offlineMetadata[fileName]
                )

                switch classification {
                case .unchanged:
                    returningUnchanged.append(url)
                case .changed:
                    returningChanged.append(url)
                }

            } else if existingFileNames.contains(fileName) {
                // File already exists and is online - check if changed
                if let storedSize = trackedSizes[fileName] {
                    switch FileSystemOperations.getFileSize(for: url) {
                    case .success(let currentSize):
                        if currentSize != storedSize {
                            existingModified.append(url)
                            print("⚠️ Online file changed: \(fileName) (old: \(storedSize), new: \(currentSize) bytes)")
                        } else {
                            // Size unchanged - ignore (already imported)
                            print("📋 File already imported and unchanged: \(fileName)")
                        }
                    case .failure:
                        // Can't determine size - ignore
                        break
                    }
                }
            } else {
                // Truly new file
                newFiles.append(url)
            }
        }

        return FileClassification(
            newFiles: newFiles,
            returningUnchanged: returningUnchanged,
            returningChanged: returningChanged,
            existingModified: existingModified
        )
    }

    // MARK: - Private Helpers

    /// Classify a returning offline file as unchanged or changed
    private static func classifyReturningFile(
        url: URL,
        fileName: String,
        metadata: OfflineFileMetadata?
    ) -> ReturningFileStatus {

        guard let metadata = metadata else {
            // No metadata - treat as changed
            print("🔄 Offline file returned (no metadata): \(fileName)")
            return .changed
        }

        // Try size comparison first (fastest)
        switch FileSystemOperations.getFileSize(for: url) {
        case .success(let currentSize):
            if currentSize == metadata.fileSize {
                // Same size - likely unchanged
                print("🔄 Offline file returned unchanged: \(fileName) (size: \(currentSize) bytes)")
                return .unchanged
            } else {
                print("⚠️ Offline file returned but size changed: \(fileName) (old: \(metadata.fileSize), new: \(currentSize) bytes)")
                return .changed
            }

        case .failure:
            // Can't get size - try hash fallback
            return classifyUsingHash(url: url, fileName: fileName, metadata: metadata)
        }
    }

    /// Use hash comparison as fallback when size comparison fails
    private static func classifyUsingHash(
        url: URL,
        fileName: String,
        metadata: OfflineFileMetadata
    ) -> ReturningFileStatus {

        guard let storedHash = metadata.partialHash else {
            print("🔐 No stored hash for \(fileName) - treating as changed")
            return .changed
        }

        switch FileSystemOperations.calculatePartialHash(for: url) {
        case .success(let currentHash):
            if currentHash == storedHash {
                print("🔄 Hash match - file unchanged: \(fileName)")
                return .unchanged
            } else {
                print("⚠️ Hash mismatch - file changed: \(fileName)")
                return .changed
            }

        case .failure:
            print("⚠️ Hash computation failed - treating as changed: \(fileName)")
            return .changed
        }
    }

    private enum ReturningFileStatus {
        case unchanged
        case changed
    }
}
