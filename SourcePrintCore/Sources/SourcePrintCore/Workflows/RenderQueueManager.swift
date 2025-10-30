import Foundation

// MARK: - Render Queue Delegate

/// Delegate protocol for render queue events
@MainActor
public protocol RenderQueueDelegate: AnyObject {
    /// Called when a render item starts processing
    func queueManager(_ manager: RenderQueueManager, didStartItem item: RenderQueueItem)

    /// Called when progress updates occur
    func queueManager(_ manager: RenderQueueManager, didUpdateProgress progress: RenderProgress)

    /// Called when a render item completes (success or failure)
    func queueManager(_ manager: RenderQueueManager, didCompleteItem result: RenderResult)

    /// Called when the entire queue finishes processing
    func queueManager(_ manager: RenderQueueManager, didFinishQueue totalCompleted: Int, totalFailed: Int)

    /// Called when an error occurs
    func queueManager(_ manager: RenderQueueManager, didEncounterError error: Error, ocfFileName: String)
}

// MARK: - Render Queue Manager

/// Manages sequential processing of render queue items
@MainActor
public class RenderQueueManager {

    // MARK: - Properties

    public weak var delegate: RenderQueueDelegate?

    /// Current queue of items to process
    public private(set) var queue: [RenderQueueItem] = []

    /// Whether the queue is currently processing
    public private(set) var isProcessing: Bool = false

    /// Current item being processed
    public private(set) var currentItem: RenderQueueItem?

    /// Total items completed successfully
    public private(set) var completedCount: Int = 0

    /// Total items that failed
    public private(set) var failedCount: Int = 0

    /// Task handle for the current processing loop
    private var processingTask: Task<Void, Never>?

    /// Maximum time to wait for a single render (in seconds)
    public var timeoutPerItem: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Add items to the queue
    public func addToQueue(_ parents: [OCFParent]) {
        let newItems = parents.map { parent in
            RenderQueueItem(
                ocfFileName: parent.ocf.fileName,
                ocfParent: parent,
                status: .pending,
                progress: "Waiting in queue..."
            )
        }

        queue.append(contentsOf: newItems)

        NSLog("📋 Added \(newItems.count) items to render queue (total: \(queue.count))")
    }

    /// Start processing the queue
    public func startProcessing() {
        guard !isProcessing else {
            NSLog("⚠️ Queue is already processing")
            return
        }

        guard !queue.isEmpty else {
            NSLog("⚠️ Queue is empty - nothing to process")
            return
        }

        NSLog("🚀 Starting render queue processing (\(queue.count) items)")

        isProcessing = true
        completedCount = 0
        failedCount = 0

        // Start processing loop
        processingTask = Task { @MainActor in
            await processQueue()
        }
    }

    /// Stop processing the queue
    public func stopProcessing() {
        guard isProcessing else { return }

        NSLog("⏸️ Stopping render queue processing")

        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        currentItem = nil
    }

    /// Clear the queue (removes all pending items)
    public func clearQueue() {
        NSLog("🗑️ Clearing render queue (\(queue.count) items removed)")
        queue.removeAll()

        if !isProcessing {
            completedCount = 0
            failedCount = 0
        }
    }

    /// Get current queue status
    public func getStatus() -> RenderQueueStatus {
        return RenderQueueStatus(
            totalItems: queue.count + completedCount + failedCount,
            completedItems: completedCount,
            failedItems: failedCount,
            isProcessing: isProcessing,
            currentItem: currentItem
        )
    }

    // MARK: - Internal Processing

    /// Process the queue sequentially
    private func processQueue() async {
        while !queue.isEmpty && !Task.isCancelled {
            // Get next item
            var item = queue.removeFirst()
            currentItem = item

            // Update status to generatingBlankRush
            item.status = .generatingBlankRush
            item.startTime = Date()
            currentItem = item

            NSLog("📤 Processing: \(item.ocfFileName) (\(queue.count) remaining)")

            // Notify delegate
            delegate?.queueManager(self, didStartItem: item)

            // Wait for render to complete (with timeout)
            let result = await waitForRenderCompletion(item: item)

            // Update counters
            if result.success {
                completedCount += 1
            } else {
                failedCount += 1
            }

            // Notify delegate of completion
            delegate?.queueManager(self, didCompleteItem: result)

            // Small delay between items
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Queue finished
        NSLog("✅ Render queue completed! Success: \(completedCount), Failed: \(failedCount)")

        isProcessing = false
        currentItem = nil

        delegate?.queueManager(self, didFinishQueue: completedCount, totalFailed: failedCount)
    }

    /// Wait for a render to complete (with timeout)
    private func waitForRenderCompletion(item: RenderQueueItem) async -> RenderResult {
        let startTime = Date()
        let timeoutDate = startTime.addingTimeInterval(timeoutPerItem)

        // Poll for completion or timeout
        while Date() < timeoutDate && !Task.isCancelled {
            // Check if still processing (render service should update item status)
            if let current = currentItem, current.status.isFinished {
                // Render completed or failed
                let duration = Date().timeIntervalSince(startTime)

                return RenderResult(
                    ocfFileName: item.ocfFileName,
                    success: current.status == .completed,
                    outputURL: nil, // Will be set by render service
                    error: current.status == .failed ? current.progress : nil,
                    duration: duration,
                    segmentCount: item.ocfParent.children.count
                )
            }

            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        // Timeout or cancellation
        let duration = Date().timeIntervalSince(startTime)

        if Task.isCancelled {
            NSLog("⏹️ Render cancelled: \(item.ocfFileName)")
            return RenderResult(
                ocfFileName: item.ocfFileName,
                success: false,
                error: "Render cancelled by user",
                duration: duration,
                segmentCount: item.ocfParent.children.count
            )
        } else {
            NSLog("⏱️ Render timeout: \(item.ocfFileName) (exceeded \(timeoutPerItem)s)")
            return RenderResult(
                ocfFileName: item.ocfFileName,
                success: false,
                error: "Render timeout (exceeded \(Int(timeoutPerItem))s)",
                duration: duration,
                segmentCount: item.ocfParent.children.count
            )
        }
    }

    // MARK: - Status Updates (Called by Render Service)

    /// Update current item status (called by render service)
    public func updateCurrentItemStatus(_ status: RenderStatus, progress: String) {
        guard var item = currentItem else { return }

        item.status = status
        item.progress = progress
        currentItem = item

        // Notify delegate of progress
        let progressUpdate = RenderProgress(
            ocfFileName: item.ocfFileName,
            status: status,
            message: progress,
            percentage: nil,
            elapsedTime: item.duration
        )

        delegate?.queueManager(self, didUpdateProgress: progressUpdate)
    }

    /// Mark current item as completed (called by render service)
    public func markCurrentItemCompleted(outputURL: URL) {
        guard var item = currentItem else { return }

        item.status = .completed
        item.completionTime = Date()
        currentItem = item

        NSLog("✅ Completed: \(item.ocfFileName)")
    }

    /// Mark current item as failed (called by render service)
    public func markCurrentItemFailed(error: String) {
        guard var item = currentItem else { return }

        item.status = .failed
        item.progress = error
        item.completionTime = Date()
        currentItem = item

        NSLog("❌ Failed: \(item.ocfFileName) - \(error)")
    }
}
