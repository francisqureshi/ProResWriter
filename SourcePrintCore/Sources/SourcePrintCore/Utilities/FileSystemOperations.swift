import Foundation
import CryptoKit

/// File system utilities for media file operations
/// Pure functions with no UI dependencies
public enum FileSystemOperations {

    // MARK: - File Metadata

    /// Get file modification date from file system
    /// - Parameter url: File URL to query
    /// - Returns: Result containing modification date or error
    public static func getModificationDate(for url: URL) -> Result<Date, FileSystemError> {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = resourceValues.contentModificationDate else {
                return .failure(.metadataUnavailable(url: url, key: "contentModificationDate"))
            }
            return .success(date)
        } catch {
            return .failure(.accessError(url: url, underlyingError: error))
        }
    }

    /// Get file size in bytes
    /// - Parameter url: File URL to query
    /// - Returns: Result containing file size in bytes or error
    public static func getFileSize(for url: URL) -> Result<Int64, FileSystemError> {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = resourceValues.fileSize else {
                return .failure(.metadataUnavailable(url: url, key: "fileSize"))
            }
            return .success(Int64(size))
        } catch {
            return .failure(.accessError(url: url, underlyingError: error))
        }
    }

    // MARK: - Hash Calculation

    /// Calculate partial hash (first 1MB + last 1MB) for large file comparison
    /// This strategy provides fast comparison while maintaining uniqueness
    ///
    /// - Parameter url: File URL to hash
    /// - Returns: Result containing SHA256 hash string (hex format) or error
    public static func calculatePartialHash(for url: URL) -> Result<String, FileSystemError> {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return .failure(.accessError(url: url, underlyingError: nil))
        }
        defer { try? fileHandle.close() }

        do {
            let chunkSize = 1024 * 1024  // 1MB
            var hasher = SHA256()

            // Get file size
            let fileSize = try fileHandle.seekToEnd()
            try fileHandle.seek(toOffset: 0)

            // Hash first chunk (or entire file if smaller)
            let firstChunkSize = min(UInt64(chunkSize), fileSize)
            if let firstData = try? fileHandle.read(upToCount: Int(firstChunkSize)) {
                hasher.update(data: firstData)
            } else {
                return .failure(.hashError(url: url, reason: "Failed to read first chunk"))
            }

            // Hash last chunk if file is large enough
            if fileSize > UInt64(chunkSize * 2) {
                try fileHandle.seek(toOffset: fileSize - UInt64(chunkSize))
                if let lastData = try? fileHandle.read(upToCount: chunkSize) {
                    hasher.update(data: lastData)
                } else {
                    return .failure(.hashError(url: url, reason: "Failed to read last chunk"))
                }
            }

            let digest = hasher.finalize()
            let hashString = digest.map { String(format: "%02x", $0) }.joined()
            return .success(hashString)
        } catch {
            return .failure(.hashError(url: url, reason: error.localizedDescription))
        }
    }

    // MARK: - File Validation

    /// Check if file exists at given URL
    /// - Parameter url: File URL to check
    /// - Returns: True if file exists
    public static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Check if path is a directory
    /// - Parameter url: File URL to check
    /// - Returns: True if path is a directory
    public static func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}

// MARK: - Error Types

public enum FileSystemError: Error, LocalizedError {
    case accessError(url: URL, underlyingError: Error?)
    case metadataUnavailable(url: URL, key: String)
    case hashError(url: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .accessError(let url, let error):
            return "Cannot access file: \(url.lastPathComponent). \(error?.localizedDescription ?? "")"
        case .metadataUnavailable(let url, let key):
            return "Metadata '\(key)' unavailable for: \(url.lastPathComponent)"
        case .hashError(let url, let reason):
            return "Hash calculation failed for \(url.lastPathComponent): \(reason)"
        }
    }
}
