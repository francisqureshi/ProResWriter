import Foundation

// MARK: - Offline File Metadata

/// Metadata for offline files to detect when they return and whether they've changed
public struct OfflineFileMetadata: Codable, Equatable {
    public let fileName: String
    public let fileSize: Int64
    public let offlineDate: Date
    public let partialHash: String?  // Optional hash for fallback comparison

    public init(fileName: String, fileSize: Int64, offlineDate: Date, partialHash: String?) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.offlineDate = offlineDate
        self.partialHash = partialHash
    }
}

// MARK: - File Change Tracking

/// Set of detected file changes
public struct FileChangeSet: Equatable {
    public let modifiedFiles: [String]
    public let deletedFiles: [String]
    public let sizeChanges: [String: (old: Int64, new: Int64)]

    public init(
        modifiedFiles: [String],
        deletedFiles: [String],
        sizeChanges: [String: (old: Int64, new: Int64)]
    ) {
        self.modifiedFiles = modifiedFiles
        self.deletedFiles = deletedFiles
        self.sizeChanges = sizeChanges
    }

    public var hasChanges: Bool {
        !modifiedFiles.isEmpty || !deletedFiles.isEmpty
    }

    public var totalChanges: Int {
        modifiedFiles.count + deletedFiles.count
    }

    public static func == (lhs: FileChangeSet, rhs: FileChangeSet) -> Bool {
        lhs.modifiedFiles == rhs.modifiedFiles &&
        lhs.deletedFiles == rhs.deletedFiles &&
        lhs.sizeChanges.keys == rhs.sizeChanges.keys
    }
}

// MARK: - File Classification

/// Classification of detected files based on their relationship to known files
public struct FileClassification: Equatable {
    public let newFiles: [URL]
    public let returningUnchanged: [URL]
    public let returningChanged: [URL]
    public let existingModified: [URL]

    public init(
        newFiles: [URL],
        returningUnchanged: [URL],
        returningChanged: [URL],
        existingModified: [URL]
    ) {
        self.newFiles = newFiles
        self.returningUnchanged = returningUnchanged
        self.returningChanged = returningChanged
        self.existingModified = existingModified
    }

    public var hasChanges: Bool {
        !newFiles.isEmpty || !returningChanged.isEmpty || !existingModified.isEmpty
    }

    public var totalFiles: Int {
        newFiles.count + returningUnchanged.count + returningChanged.count + existingModified.count
    }
}
