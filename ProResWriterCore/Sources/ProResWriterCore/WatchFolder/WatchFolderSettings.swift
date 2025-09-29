//
//  WatchFolderSettings.swift
//  ProResWriterCore
//
//  Created by Claude on 29/09/2025.
//  Basic settings model for watch folder functionality
//

import Foundation

/// Watch folder configuration with support for grade and VFX folders
public struct WatchFolderSettings: Codable, Equatable {
    /// Whether watch folder monitoring is enabled
    public var isEnabled: Bool = false

    /// Primary grade folder to monitor (imports as segments)
    public var primaryGradeFolder: URL?

    /// VFX folder to monitor (imports as VFX segments)
    public var vfxFolder: URL?

    /// Debounce interval in seconds to prevent rapid fire events
    public var debounceInterval: Double = 3.0

    /// Whether to automatically import detected files
    public var autoImportEnabled: Bool = true

    public init() {}

    public init(isEnabled: Bool = false, primaryGradeFolder: URL? = nil, vfxFolder: URL? = nil, debounceInterval: Double = 3.0, autoImportEnabled: Bool = true) {
        self.isEnabled = isEnabled
        self.primaryGradeFolder = primaryGradeFolder
        self.vfxFolder = vfxFolder
        self.debounceInterval = debounceInterval
        self.autoImportEnabled = autoImportEnabled
    }
}