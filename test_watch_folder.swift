#!/usr/bin/env swift

//
//  test_watch_folder.swift
//  Simple test script to verify FSEvents monitoring works
//

import Foundation
import Dispatch

// Add the current directory to the swift import path
import ProResWriterCore

print("🧪 Testing FSEvents monitoring...")
print("📁 This will monitor /tmp/watch_test for file changes")
print("💡 Create, modify, or delete files in that folder to test")

// Create test directory
let testDir = "/tmp/watch_test"
try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true, attributes: nil)
print("📂 Created test directory: \(testDir)")

// Create the watch folder service
let watcher = SimpleWatchFolder()

// Start watching
watcher.startWatching(path: testDir)

print("👀 Monitoring started. Try these commands in another terminal:")
print("   touch \(testDir)/test.mov")
print("   echo 'test' > \(testDir)/grade.prores")
print("   rm \(testDir)/*")
print("")
print("Press Ctrl+C to stop...")

// Keep running
let runLoop = RunLoop.current
while runLoop.run(mode: .default, before: Date.distantFuture) {
    // Keep the run loop alive
}