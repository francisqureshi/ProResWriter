//
//  progressBar.swift
//  ProResWriter
//
//  Created by Francis Qureshi on 24/08/2025.
//

import Foundation

/// Modular progress bar system for consistent TUI experience across ProResWriter
class ProgressBar {
    
    private let title: String
    private let emoji: String
    private let barWidth: Int
    private let showFPS: Bool
    private var startTime: CFAbsoluteTime
    private var lastUpdate: CFAbsoluteTime
    private let updateInterval: TimeInterval
    
    /// Initialize a new progress bar
    /// - Parameters:
    ///   - title: Title to display above the progress bar
    ///   - emoji: Emoji to use in the progress bar (e.g., "🖤", "📹")
    ///   - barWidth: Width of the progress bar in characters (default: 50)
    ///   - showFPS: Whether to calculate and display FPS (default: false)
    ///   - updateInterval: Minimum time between updates in seconds (default: 0.1)
    init(title: String, emoji: String = "📊", barWidth: Int = 50, showFPS: Bool = false, updateInterval: TimeInterval = 0.1) {
        self.title = title
        self.emoji = emoji
        self.barWidth = barWidth
        self.showFPS = showFPS
        self.updateInterval = updateInterval
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.lastUpdate = 0
    }
    
    /// Start the progress bar with initial display
    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
        lastUpdate = 0
        print("  📹 \(title):")
    }
    
    /// Update progress bar display using the same technique as working printProcess.swift
    /// - Parameters:
    ///   - current: Current progress value
    ///   - total: Total progress value
    ///   - forceUpdate: Force update regardless of time interval (default: false)
    func update(current: Int, total: Int, forceUpdate: Bool = false) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Throttle updates unless forced or it's the final update
        if !forceUpdate && current < total && (currentTime - lastUpdate) < updateInterval {
            return
        }
        
        lastUpdate = currentTime
        
        let percentage = Int((Float(current) / Float(total)) * 100)
        // Use the same technique as working printProcess.swift - half-width bars
        let progressBar = String(repeating: "█", count: percentage / 2)
        let emptyBar = String(repeating: "░", count: barWidth - (percentage / 2))
        
        var progressString = "\r  \(emoji) [\(progressBar)\(emptyBar)] \(percentage)%"
        
        // Add FPS calculation if enabled
        if showFPS {
            let elapsedTime = currentTime - startTime
            let fps = current > 0 ? Double(current) / elapsedTime : 0.0
            progressString += " @ \(String(format: "%.1f", fps))fps"
        }
        
        print(progressString, terminator: "")
        fflush(stdout)
    }
    
    /// Update progress using a float percentage (0.0 to 1.0) - useful for callback-based systems
    /// - Parameter progress: Progress as a float between 0.0 and 1.0
    func updateProgress(_ progress: Float) {
        let current = Int(progress * 100)
        update(current: current, total: 100)
    }
    
    /// Complete the progress bar with 100% display and optional final stats
    /// - Parameters:
    ///   - total: Total items processed
    ///   - showFinalStats: Whether to show final timing/FPS stats (default: true)
    func complete(total: Int, showFinalStats: Bool = true) {
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalElapsed = endTime - startTime
        
        // Use the same technique as working printProcess.swift - full bar at 100%
        var completionString = "\r  \(emoji) [\(String(repeating: "█", count: barWidth))] 100%"
        
        if showFPS && showFinalStats {
            let finalFPS = Double(total) / totalElapsed
            completionString += " @ \(String(format: "%.1f", finalFPS))fps"
        }
        
        print(completionString)
        
        if showFinalStats {
            print("  ⏱️  Completed in \(String(format: "%.2f", totalElapsed))s")
        }
        
        print("")  // New line after progress bar
    }
}

/// Convenience extensions for common progress bar types
extension ProgressBar {
    
    /// Create a progress bar for frame generation tasks
    static func frameGeneration() -> ProgressBar {
        return ProgressBar(
            title: "Frame Generation Progress", 
            emoji: "🖤", 
            barWidth: 50, 
            showFPS: true,
            updateInterval: 0.05  // Update more frequently for frame generation
        )
    }
    
    /// Create a progress bar for export/rendering tasks
    static func export() -> ProgressBar {
        return ProgressBar(
            title: "Export Progress", 
            emoji: "📹", 
            barWidth: 50, 
            showFPS: false,
            updateInterval: 0.1
        )
    }
    
    /// Create a progress bar for general processing tasks
    static func processing(title: String) -> ProgressBar {
        return ProgressBar(
            title: title, 
            emoji: "⚙️", 
            barWidth: 50, 
            showFPS: false,
            updateInterval: 0.05  // Update more frequently for processing tasks
        )
    }
}