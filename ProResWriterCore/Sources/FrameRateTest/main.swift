#!/usr/bin/env swift
//
//  FrameRateTest - Diagnose SwiftFFmpeg r_frame_rate bug
//
//  Tests reading frame rates from video files to diagnose why
//  realFramerate returns garbage on M1 Pro but works on M4 Pro
//

import Foundation
import SwiftFFmpeg

func testFile(path: String) {
    print("=== Testing: \(path) ===")

    guard let fmtCtx = try? AVFormatContext(url: path) else {
        print("❌ Failed to open file")
        return
    }

    try? fmtCtx.findStreamInfo()

    guard let videoStream = fmtCtx.streams.first(where: { $0.mediaType == .video }) else {
        print("❌ No video stream found")
        return
    }

    let realFR = videoStream.realFramerate
    let avgFR = videoStream.averageFramerate

    print("realFramerate (r_frame_rate):")
    print("  Raw: num=\(realFR.num) den=\(realFR.den)")
    print("  Hex: num=0x\(String(format: "%08X", UInt32(bitPattern: realFR.num))) den=0x\(String(format: "%08X", UInt32(bitPattern: realFR.den)))")
    if realFR.den > 0 {
        let fps = Float(realFR.num) / Float(realFR.den)
        print("  Calculated FPS: \(fps)")
    } else {
        print("  Invalid (den=0)")
    }

    print("\naverageFramerate (avg_frame_rate):")
    print("  Raw: num=\(avgFR.num) den=\(avgFR.den)")
    print("  Hex: num=0x\(String(format: "%08X", UInt32(bitPattern: avgFR.num))) den=0x\(String(format: "%08X", UInt32(bitPattern: avgFR.den)))")
    if avgFR.den > 0 {
        let fps = Float(avgFR.num) / Float(avgFR.den)
        print("  Calculated FPS: \(fps)")
    } else {
        print("  Invalid (den=0)")
    }

    // Try to interpret realFR.num as a float to see if it's reading from wrong offset
    let floatBytes = withUnsafeBytes(of: realFR.num) { Data($0) }
    if let floatValue = floatBytes.withUnsafeBytes({ $0.load(as: Float.self) }) {
        print("\nDEBUG: If realFR.num interpreted as IEEE 754 float: \(floatValue)")
    }

    print("")
}

// Test files
let testFiles = [
    "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/Ganni/ALL_GRADES_MM/C20250825_0303.mov",
    "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/Ganni/ALL_GRADES_MM/C20250825_0303_S001.mov",
    "/Users/fq/Movies/ProResWriter/SourcePrintTestGround/Ganni/ALL_GRADES_MM/C20250825_0303_S000.mov"
]

for file in testFiles {
    if FileManager.default.fileExists(atPath: file) {
        testFile(path: file)
    } else {
        print("⚠️ File not found: \(file)\n")
    }
}

print("✅ Test complete")
