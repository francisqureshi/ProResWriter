import Foundation

// MARK: - Delegate Protocol

/// Protocol for watch folder event notifications
public protocol WatchFolderDelegate: AnyObject {
    func watchFolder(_ service: WatchFolderService, didDetectNewFiles files: [URL], isVFX: Bool)
    func watchFolder(_ service: WatchFolderService, didDetectDeletedFiles fileNames: [String], isVFX: Bool)
    func watchFolder(_ service: WatchFolderService, didDetectModifiedFiles fileNames: [String], isVFX: Bool)
    func watchFolder(_ service: WatchFolderService, didEncounterError error: WatchFolderError)
}

// MARK: - Watch Folder Service

/// Watch folder service for monitoring video file changes
/// Wraps FileMonitorWatchFolder with business logic layer
public class WatchFolderService {

    // MARK: - Properties

    public weak var delegate: WatchFolderDelegate?

    private var fileMonitor: FileMonitorWatchFolder?
    private let gradePath: String?
    private let vfxPath: String?
    private var isMonitoring: Bool = false

    // MARK: - Initialization

    public init(gradePath: String?, vfxPath: String?) {
        self.gradePath = gradePath
        self.vfxPath = vfxPath
    }

    // MARK: - Public API

    /// Start monitoring watch folders
    public func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ Watch folder already monitoring")
            return
        }

        guard gradePath != nil || vfxPath != nil else {
            delegate?.watchFolder(self, didEncounterError: .noPathsConfigured)
            return
        }

        print("🚀 Starting watch folder monitoring...")
        if let gradePath = gradePath { print("📁 Grade folder: \(gradePath)") }
        if let vfxPath = vfxPath { print("🎬 VFX folder: \(vfxPath)") }

        fileMonitor = FileMonitorWatchFolder()

        // Set up callbacks
        fileMonitor?.onVideoFilesDetected = { [weak self] videoFiles, isVFX in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.delegate?.watchFolder(self, didDetectNewFiles: videoFiles, isVFX: isVFX)
            }
        }

        fileMonitor?.onVideoFilesDeleted = { [weak self] fileNames, isVFX in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.delegate?.watchFolder(self, didDetectDeletedFiles: fileNames, isVFX: isVFX)
            }
        }

        fileMonitor?.onVideoFilesModified = { [weak self] fileNames, isVFX in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.delegate?.watchFolder(self, didDetectModifiedFiles: fileNames, isVFX: isVFX)
            }
        }

        fileMonitor?.startWatching(gradePath: gradePath, vfxPath: vfxPath)
        isMonitoring = true
    }

    /// Stop monitoring watch folders
    public func stopMonitoring() {
        print("🛑 Stopping watch folder monitoring")
        fileMonitor?.stopWatching()
        fileMonitor = nil
        isMonitoring = false
    }

    /// Check if currently monitoring
    public var isActive: Bool {
        return isMonitoring
    }

    // MARK: - Startup Change Detection

    /// Detect changes that occurred while app was not monitoring
    /// Useful to call on app startup
    ///
    /// - Parameters:
    ///   - knownSegments: Segments already imported
    ///   - trackedSizes: Previously recorded file sizes
    /// - Returns: Set of detected changes
    public func detectChangesOnStartup(
        knownSegments: [MediaFileInfo],
        trackedSizes: [String: Int64]
    ) -> FileChangeSet {
        print("🔍 Checking for file changes that occurred while app was closed...")

        var modifiedFiles: [String] = []
        var deletedFiles: [String] = []
        var sizeChanges: [String: (old: Int64, new: Int64)] = [:]

        for segment in knownSegments {
            let fileName = segment.fileName
            let fileURL = segment.url

            // Check if this segment is in a watch folder
            let isInWatchFolder = isFileInWatchFolder(fileURL)
            guard isInWatchFolder else { continue }

            // Check if file still exists
            if FileSystemOperations.fileExists(at: fileURL) {
                // File exists - check if size changed
                if let storedSize = trackedSizes[fileName] {
                    switch FileSystemOperations.getFileSize(for: fileURL) {
                    case .success(let currentSize):
                        if currentSize != storedSize {
                            modifiedFiles.append(fileName)
                            sizeChanges[fileName] = (old: storedSize, new: currentSize)
                            print("⚠️ File changed while app was closed: \(fileName) (old: \(storedSize), new: \(currentSize) bytes)")
                        }
                    case .failure:
                        continue
                    }
                }
            } else {
                // File was deleted while app was closed
                deletedFiles.append(fileName)
                print("⚠️ File deleted while app was closed: \(fileName)")
            }
        }

        let changeCount = modifiedFiles.count + deletedFiles.count
        if changeCount > 0 {
            print("✅ Found \(changeCount) file(s) that changed while app was closed")
        } else {
            print("✅ No changes detected in watch folders")
        }

        return FileChangeSet(
            modifiedFiles: modifiedFiles,
            deletedFiles: deletedFiles,
            sizeChanges: sizeChanges
        )
    }

    /// Scan watch folders for new files that were added while app was closed
    /// Detects files present in watch folders but not yet imported as segments
    ///
    /// - Parameter knownSegments: Segments already imported
    /// - Returns: Tuple of new grade files and new VFX files
    public func scanForNewFiles(
        knownSegments: [MediaFileInfo]
    ) async -> (gradeFiles: [URL], vfxFiles: [URL]) {
        print("🔍 Scanning watch folders for new files added while app was closed...")

        let knownFileNames = Set(knownSegments.map { $0.fileName })
        var gradeFiles: [URL] = []
        var vfxFiles: [URL] = []

        // Scan grade folder
        if let gradePath = gradePath {
            let gradeURL = URL(fileURLWithPath: gradePath)
            do {
                let allFiles = try await VideoFileDiscovery.discoverVideoFiles(in: gradeURL)
                for file in allFiles {
                    if !knownFileNames.contains(file.lastPathComponent) {
                        gradeFiles.append(file)
                    }
                }
                if !gradeFiles.isEmpty {
                    print("✅ Found \(gradeFiles.count) new grade file(s) added while app was closed")
                }
            } catch {
                print("⚠️ Failed to scan grade folder: \(error.localizedDescription)")
            }
        }

        // Scan VFX folder
        if let vfxPath = vfxPath {
            let vfxURL = URL(fileURLWithPath: vfxPath)
            do {
                let allFiles = try await VideoFileDiscovery.discoverVideoFiles(in: vfxURL)
                for file in allFiles {
                    if !knownFileNames.contains(file.lastPathComponent) {
                        vfxFiles.append(file)
                    }
                }
                if !vfxFiles.isEmpty {
                    print("✅ Found \(vfxFiles.count) new VFX file(s) added while app was closed")
                }
            } catch {
                print("⚠️ Failed to scan VFX folder: \(error.localizedDescription)")
            }
        }

        let totalNew = gradeFiles.count + vfxFiles.count
        if totalNew == 0 {
            print("✅ No new files found in watch folders")
        }

        return (gradeFiles, vfxFiles)
    }

    // MARK: - Private Helpers

    /// Check if file URL is within configured watch folders
    private func isFileInWatchFolder(_ url: URL) -> Bool {
        let path = url.path
        if let gradePath = gradePath, path.hasPrefix(gradePath) {
            return true
        }
        if let vfxPath = vfxPath, path.hasPrefix(vfxPath) {
            return true
        }
        return false
    }
}

// MARK: - Error Types

public enum WatchFolderError: Error, LocalizedError {
    case noPathsConfigured
    case monitoringFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noPathsConfigured:
            return "No watch folder paths configured"
        case .monitoringFailed(let reason):
            return "Watch folder monitoring failed: \(reason)"
        }
    }
}
