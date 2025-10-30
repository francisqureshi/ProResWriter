import XCTest

@testable import SourcePrintCore

final class FileSystemOperationsTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create a temporary file with given content
    private func createTemporaryFile(content: String, filename: String = "test.txt") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(
            filename)

        // Create parent directory
        try! FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try! content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Create a temporary file with specified size in MB
    private func createLargeFile(sizeMB: Int, filename: String = "largefile.bin") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(
            filename)

        // Create parent directory
        try! FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Create file with specified size
        let bytesPerMB = 1024 * 1024
        let data = Data(repeating: 0x42, count: sizeMB * bytesPerMB)
        try! data.write(to: fileURL)

        return fileURL
    }

    /// Create a temporary directory with test file structure
    private func createTestDirectory(with files: [String]) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)

        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        for filePath in files {
            let fileURL = testDir.appendingPathComponent(filePath)

            // Create parent directories if needed
            let parentDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try! FileManager.default.createDirectory(
                    at: parentDir, withIntermediateDirectories: true)
            }

            // Create file
            try! "test content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return testDir
    }

    // MARK: - getModificationDate Tests

    func testGetModificationDate_Success() throws {
        // Create a test file
        let testFile = createTemporaryFile(content: "test")
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Get modification date
        let result = FileSystemOperations.getModificationDate(for: testFile)

        // Verify success
        switch result {
        case .success(let date):
            XCTAssertLessThanOrEqual(
                date.timeIntervalSinceNow,
                1.0,
                "Modification date should be recent"
            )
            XCTAssertGreaterThanOrEqual(
                date.timeIntervalSinceNow,
                -10.0,
                "Modification date should not be too far in the past"
            )
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testGetModificationDate_NonExistentFile() throws {
        let nonExistentFile = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")

        let result = FileSystemOperations.getModificationDate(for: nonExistentFile)

        switch result {
        case .success:
            XCTFail("Expected failure for non-existent file")
        case .failure:
            // Success - got expected error (type is guaranteed by Result<Date, FileSystemError>)
            break
        }
    }

    // MARK: - getFileSize Tests

    func testGetFileSize_Success() throws {
        let testContent = "Hello, World!"
        let testFile = createTemporaryFile(content: testContent)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let result = FileSystemOperations.getFileSize(for: testFile)

        switch result {
        case .success(let size):
            XCTAssertEqual(
                size,
                Int64(testContent.utf8.count),
                "File size should match content size"
            )
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testGetFileSize_LargeFile() throws {
        let testFile = createLargeFile(sizeMB: 5)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let result = FileSystemOperations.getFileSize(for: testFile)

        switch result {
        case .success(let size):
            let expectedSize = Int64(5 * 1024 * 1024)
            XCTAssertEqual(size, expectedSize, "File size should be 5MB")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testGetFileSize_NonExistentFile() throws {
        let nonExistentFile = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")

        let result = FileSystemOperations.getFileSize(for: nonExistentFile)

        switch result {
        case .success:
            XCTFail("Expected failure for non-existent file")
        case .failure:
            // Success - got expected error (type is guaranteed by Result<Date, FileSystemError>)
            break
        }
    }

    // MARK: - calculatePartialHash Tests

    func testCalculatePartialHash_SmallFile() throws {
        let testFile = createTemporaryFile(content: "Small file content")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let result = FileSystemOperations.calculatePartialHash(for: testFile)

        switch result {
        case .success(let hash):
            XCTAssertEqual(hash.count, 64, "SHA256 hash should be 64 hex characters")
            XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, "Hash should contain only hex digits")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testCalculatePartialHash_LargeFile() throws {
        let testFile = createLargeFile(sizeMB: 10)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let result = FileSystemOperations.calculatePartialHash(for: testFile)

        switch result {
        case .success(let hash):
            XCTAssertEqual(hash.count, 64, "SHA256 hash should be 64 hex characters")
            XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, "Hash should contain only hex digits")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testCalculatePartialHash_Consistency() throws {
        // Create a file
        let testFile = createLargeFile(sizeMB: 3)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Calculate hash twice
        let result1 = FileSystemOperations.calculatePartialHash(for: testFile)
        let result2 = FileSystemOperations.calculatePartialHash(for: testFile)

        // Both should succeed and produce same hash
        switch (result1, result2) {
        case (.success(let hash1), .success(let hash2)):
            XCTAssertEqual(hash1, hash2, "Hash should be consistent for same file")
        default:
            XCTFail("Both hash calculations should succeed")
        }
    }

    func testCalculatePartialHash_NonExistentFile() throws {
        let nonExistentFile = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")

        let result = FileSystemOperations.calculatePartialHash(for: nonExistentFile)

        switch result {
        case .success:
            XCTFail("Expected failure for non-existent file")
        case .failure:
            // Success - got expected error (type is guaranteed by Result<Date, FileSystemError>)
            break
        }
    }

    // MARK: - fileExists Tests

    func testFileExists_ExistingFile() throws {
        let testFile = createTemporaryFile(content: "test")
        defer { try? FileManager.default.removeItem(at: testFile) }

        XCTAssertTrue(
            FileSystemOperations.fileExists(at: testFile),
            "Should return true for existing file"
        )
    }

    func testFileExists_NonExistentFile() throws {
        let nonExistentFile = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")

        XCTAssertFalse(
            FileSystemOperations.fileExists(at: nonExistentFile),
            "Should return false for non-existent file"
        )
    }

    // MARK: - isDirectory Tests

    func testIsDirectory_ActualDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        XCTAssertTrue(
            FileSystemOperations.isDirectory(at: testDir),
            "Should return true for directory"
        )
    }

    func testIsDirectory_RegularFile() throws {
        let testFile = createTemporaryFile(content: "test")
        defer { try? FileManager.default.removeItem(at: testFile) }

        XCTAssertFalse(
            FileSystemOperations.isDirectory(at: testFile),
            "Should return false for regular file"
        )
    }

    func testIsDirectory_NonExistent() throws {
        let nonExistentPath = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)")

        XCTAssertFalse(
            FileSystemOperations.isDirectory(at: nonExistentPath),
            "Should return false for non-existent path"
        )
    }
}
