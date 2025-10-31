import Foundation

/// Service for scanning and detecting existing blank rush files
public class BlankRushScanner {

    /// Scan directory for existing blank rush files matching OCF parents
    ///
    /// - Parameters:
    ///   - linkingResult: Linking result with OCF parents
    ///   - blankRushDirectory: Directory to scan
    /// - Returns: Dictionary of OCF filename to blank rush URL
    public static func scanForExistingBlankRushes(
        linkingResult: LinkingResult,
        blankRushDirectory: URL
    ) -> [String: URL] {
        var foundBlankRushes: [String: URL] = [:]

        for parent in linkingResult.parentsWithChildren {
            let baseName = (parent.ocf.fileName as NSString).deletingPathExtension
            let blankRushFileName = "\(baseName)_blankRush.mov"
            let blankRushURL = blankRushDirectory.appendingPathComponent(blankRushFileName)

            if FileManager.default.fileExists(atPath: blankRushURL.path) {
                foundBlankRushes[parent.ocf.fileName] = blankRushURL
                NSLog("✅ Found existing blank rush: \(blankRushFileName)")
            }
        }

        NSLog("📊 Scan complete: Found \(foundBlankRushes.count)/\(linkingResult.parentsWithChildren.count) blank rushes")
        return foundBlankRushes
    }

    /// Check if blank rush exists for specific OCF
    ///
    /// - Parameters:
    ///   - ocfFileName: OCF filename to check
    ///   - directory: Directory to search
    /// - Returns: True if blank rush file exists on disk
    public static func blankRushExists(
        for ocfFileName: String,
        in directory: URL
    ) -> Bool {
        let baseName = (ocfFileName as NSString).deletingPathExtension
        let blankRushFileName = "\(baseName)_blankRush.mov"
        let blankRushURL = directory.appendingPathComponent(blankRushFileName)
        return FileManager.default.fileExists(atPath: blankRushURL.path)
    }

    /// Get blank rush URL for OCF filename
    ///
    /// - Parameters:
    ///   - ocfFileName: OCF filename
    ///   - directory: Blank rush directory
    /// - Returns: Expected blank rush URL (may not exist on disk)
    public static func blankRushURL(
        for ocfFileName: String,
        in directory: URL
    ) -> URL {
        let baseName = (ocfFileName as NSString).deletingPathExtension
        let blankRushFileName = "\(baseName)_blankRush.mov"
        return directory.appendingPathComponent(blankRushFileName)
    }
}
