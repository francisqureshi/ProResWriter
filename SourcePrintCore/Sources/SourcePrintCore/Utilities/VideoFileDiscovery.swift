import Foundation

/// Video file discovery utility for recursive directory traversal
public enum VideoFileDiscovery {

    // Supported video file extensions
    public static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mxf", "avi", "mkv", "avp",
    ]

    /// Recursively discover all video files in a directory
    ///
    /// - Parameters:
    ///   - directoryURL: Root directory to scan
    ///   - skipHidden: Whether to skip hidden files (default: true)
    /// - Returns: Sorted array of video file URLs
    public static func discoverVideoFiles(
        in directoryURL: URL,
        skipHidden: Bool = true
    ) async throws -> [URL] {
        var videoFiles: [URL] = []

        let fileManager = FileManager.default

        // First check if directory exists and is accessible
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw VideoFileDiscoveryError.directoryNotAccessible(directoryURL)
        }

        let options: FileManager.DirectoryEnumerationOptions =
            skipHidden
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsPackageDescendants]

        guard
            let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: options
            )
        else {
            throw VideoFileDiscoveryError.directoryNotAccessible(directoryURL)
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])

                // Only process regular files (not directories)
                if resourceValues.isRegularFile == true && isVideoFile(fileURL) {
                    videoFiles.append(fileURL)
                }
            } catch {
                // Log error but continue processing other files
                print("⚠️ Error checking file \(fileURL.lastPathComponent): \(error)")
            }
        }

        return videoFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Check if file extension indicates a video file
    ///
    /// - Parameter url: File URL to check
    /// - Returns: True if file has video extension
    public static func isVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    /// Discover video files in multiple directories
    ///
    /// - Parameters:
    ///   - directoryURLs: Array of directory URLs to scan
    ///   - skipHidden: Whether to skip hidden files (default: true)
    /// - Returns: Combined sorted array of video file URLs
    public static func discoverVideoFiles(
        in directoryURLs: [URL],
        skipHidden: Bool = true
    ) async throws -> [URL] {
        var allVideoFiles: [URL] = []

        for directoryURL in directoryURLs {
            let files = try await discoverVideoFiles(in: directoryURL, skipHidden: skipHidden)
            allVideoFiles.append(contentsOf: files)
        }

        return allVideoFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - Error Types

public enum VideoFileDiscoveryError: Error, LocalizedError {
    case directoryNotAccessible(URL)
    case noVideoFilesFound(URL)

    public var errorDescription: String? {
        switch self {
        case .directoryNotAccessible(let url):
            return "Cannot access directory: \(url.path)"
        case .noVideoFilesFound(let url):
            return "No video files found in: \(url.path)"
        }
    }
}
