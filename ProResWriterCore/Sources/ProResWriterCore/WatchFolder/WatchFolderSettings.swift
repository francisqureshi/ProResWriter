//
//  WatchFolderSettings.swift
//  ProResWriterCore
//
//  Created by Claude on 29/09/2025.
//  Basic settings model for watch folder functionality
//

import Foundation

/// Simple settings model for watch folder configuration
public struct WatchFolderSettings: Codable, Equatable {
    /// Whether watch folder monitoring is enabled
    public var isEnabled: Bool = false

    /// Primary grade folder to monitor
    public var primaryGradeFolder: URL?

    /// Debounce interval in seconds to prevent rapid fire events
    public var debounceInterval: Double = 2.0

    /// Whether to automatically import detected files
    public var autoImportEnabled: Bool = true

    public init() {}

    public init(isEnabled: Bool = false, primaryGradeFolder: URL? = nil, debounceInterval: Double = 2.0, autoImportEnabled: Bool = true) {
        self.isEnabled = isEnabled
        self.primaryGradeFolder = primaryGradeFolder
        self.debounceInterval = debounceInterval
        self.autoImportEnabled = autoImportEnabled
    }
}