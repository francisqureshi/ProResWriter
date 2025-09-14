#!/usr/bin/swift

import Foundation
import ProResWriterCore

// Create test MediaFileInfo objects with different frame rates
let ocf24 = MediaFileInfo(url: URL(fileURLWithPath: "/test24.mov"))
ocf24.frameRate = 24.0
ocf24.durationInFrames = 100

let ocf23976 = MediaFileInfo(url: URL(fileURLWithPath: "/test23976.mov"))
ocf23976.frameRate = 23.976
ocf23976.durationInFrames = 100

let segment24 = MediaFileInfo(url: URL(fileURLWithPath: "/segment24.mov"))
segment24.frameRate = 24.0
segment24.durationInFrames = 50
segment24.effectiveDisplayResolution = (width: 1920, height: 1080)

let segment23976 = MediaFileInfo(url: URL(fileURLWithPath: "/segment23976.mov"))
segment23976.frameRate = 23.976
segment23976.durationInFrames = 50
segment23976.effectiveDisplayResolution = (width: 1920, height: 1080)

// Set matching resolution for OCFs
ocf24.effectiveDisplayResolution = (width: 1920, height: 1080)
ocf23976.effectiveDisplayResolution = (width: 1920, height: 1080)

let linker = SegmentOCFLinker()

print("🧪 Testing Frame Rate Matching with Rational Arithmetic")
print("====================================================")

// Test 1: 24fps segment should match 24fps OCF
print("\n✅ Test 1: 24fps segment with 24fps OCF")
let result1 = linker.linkSegments([segment24], withOCFParents: [ocf24])
print("   Result: \(result1.totalLinkedSegments) / \(result1.totalSegments) linked")

// Test 2: 23.976fps segment should match 23.976fps OCF 
print("\n✅ Test 2: 23.976fps segment with 23.976fps OCF")
let result2 = linker.linkSegments([segment23976], withOCFParents: [ocf23976])
print("   Result: \(result2.totalLinkedSegments) / \(result2.totalSegments) linked")

// Test 3: 24fps segment should NOT match 23.976fps OCF (critical test)
print("\n❌ Test 3: 24fps segment with 23.976fps OCF (should NOT match)")
let result3 = linker.linkSegments([segment24], withOCFParents: [ocf23976])
print("   Result: \(result3.totalLinkedSegments) / \(result3.totalSegments) linked")

// Test 4: 23.976fps segment should NOT match 24fps OCF (critical test)
print("\n❌ Test 4: 23.976fps segment with 24fps OCF (should NOT match)")
let result4 = linker.linkSegments([segment23976], withOCFParents: [ocf24])
print("   Result: \(result4.totalLinkedSegments) / \(result4.totalSegments) linked")

print("\n🎯 Expected Results:")
print("   Tests 1 & 2: 1/1 linked (exact frame rate matches)")
print("   Tests 3 & 4: 0/1 linked (different frame rates should not match)")