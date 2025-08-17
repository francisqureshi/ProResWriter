//
//  blankRushCreator.swift
//  ProResWriter
//
//  Created by Claude on 17/08/2025.
//

import Foundation

// MARK: - Blank Rush Creation

struct BlankRushResult {
    let originalOCF: MediaFileInfo
    let blankRushURL: URL
    let success: Bool
    let error: String?
}

class BlankRushCreator {
    
    private let projectBlankRushDirectory: String
    
    init(projectDirectory: String = "/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush") {
        self.projectBlankRushDirectory = projectDirectory
    }
    
    /// Create blank rush files for all OCF parents that have children
    func createBlankRushes(from linkingResult: LinkingResult) async -> [BlankRushResult] {
        print("🎬 Creating blank rushes for \(linkingResult.ocfParents.count) OCF parents...")
        
        // Ensure output directory exists
        let outputURL = URL(fileURLWithPath: projectBlankRushDirectory)
        createDirectoryIfNeeded(at: outputURL)
        
        var results: [BlankRushResult] = []
        
        // Process each OCF parent that has children
        for parent in linkingResult.ocfParents {
            if parent.hasChildren {
                print("\n📁 Processing \(parent.ocf.fileName) with \(parent.childCount) children...")
                
                let result = await createBlankRush(for: parent.ocf, outputDirectory: outputURL)
                results.append(result)
                
                if result.success {
                    print("  ✅ Created: \(result.blankRushURL.lastPathComponent)")
                } else {
                    print("  ❌ Failed: \(result.error ?? "Unknown error")")
                }
            } else {
                print("📂 Skipping \(parent.ocf.fileName) (no children)")
                
                // Still add to results for completeness
                results.append(BlankRushResult(
                    originalOCF: parent.ocf,
                    blankRushURL: URL(fileURLWithPath: ""),
                    success: false,
                    error: "No children segments found"
                ))
            }
        }
        
        let successCount = results.filter { $0.success }.count
        print("\n🎬 Blank rush creation complete: \(successCount)/\(results.count) succeeded")
        
        return results
    }
    
    /// Create blank rush for a single OCF file using the ffmpeg script
    private func createBlankRush(for ocf: MediaFileInfo, outputDirectory: URL) async -> BlankRushResult {
        
        // Generate output filename: originalName_blankRush.mov
        let baseName = (ocf.fileName as NSString).deletingPathExtension
        let outputFileName = "\(baseName)_blankRush.mov"
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)
        
        // Get the path to the ffmpeg script
        guard let scriptPath = getFFmpegScriptPath() else {
            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: false,
                error: "FFmpeg script not found"
            )
        }
        
        // Run the ffmpeg script
        do {
            let success = try await runFFmpegScript(
                scriptPath: scriptPath,
                inputPath: ocf.url.path,
                outputPath: outputURL.path
            )
            
            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: success,
                error: success ? nil : "FFmpeg script execution failed"
            )
            
        } catch {
            return BlankRushResult(
                originalOCF: ocf,
                blankRushURL: outputURL,
                success: false,
                error: "Error running FFmpeg script: \(error.localizedDescription)"
            )
        }
    }
    
    /// Find the ffmpeg script in the Resources directory
    private func getFFmpegScriptPath() -> String? {
        let fileManager = FileManager.default
        
        // Get the executable path and look for Resources/ffmpegScripts directory next to it
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let executableDirectory = (executablePath as NSString).deletingLastPathComponent
        let scriptPath = "\(executableDirectory)/Resources/ffmpegScripts/timecode_black_frames_relative.sh"
        
        if fileManager.fileExists(atPath: scriptPath) {
            print("📝 Found FFmpeg script at: \(scriptPath)")
            return scriptPath
        }
        
        // Fallback: try current directory
        let currentDirPath = "\(fileManager.currentDirectoryPath)/Resources/ffmpegScripts/timecode_black_frames_relative.sh"
        if fileManager.fileExists(atPath: currentDirPath) {
            print("📝 Found FFmpeg script at: \(currentDirPath)")
            return currentDirPath
        }
        
        print("⚠️ FFmpeg script not found. Tried:")
        print("  - \(scriptPath)")
        print("  - \(currentDirPath)")
        return nil
    }
    
    /// Run the ffmpeg script with input and output paths
    private func runFFmpegScript(scriptPath: String, inputPath: String, outputPath: String) async throws -> Bool {
        
        print("  📝 Running: bash \(scriptPath) \"\(inputPath)\" \"\(outputPath)\"")
        print("  🎬 Starting blank rush creation (this may take several minutes for long videos)...")
        
        // Check if we're in an interactive terminal - if so, use shell script wrapper
        let isInteractive = isatty(STDOUT_FILENO) != 0
        
        if isInteractive {
            print("  📺 Interactive terminal detected - using shell wrapper approach")
            print("  ⏳ Creating temp script to avoid Swift Process API VideoToolbox issues...")
            fflush(stdout)
            
            // Create a temporary shell script that runs the ffmpeg script
            let tempScriptPath = "/tmp/prores_wrapper_\(UUID().uuidString).sh"
            let scriptDirectory = (scriptPath as NSString).deletingLastPathComponent
            let tempScript = """
            #!/bin/bash
            cd "\(scriptDirectory)"
            bash "\(scriptPath)" "\(inputPath)" "\(outputPath)"
            echo "FFMPEG_EXIT_CODE=$?" > /tmp/ffmpeg_status.txt
            """
            
            do {
                try tempScript.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
                
                // Make it executable
                let chmodProcess = Process()
                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodProcess.arguments = ["+x", tempScriptPath]
                try chmodProcess.run()
                chmodProcess.waitUntilExit()
                
                // Run the temp script
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [tempScriptPath]
                
                try process.run()
                process.waitUntilExit()
                
                // Clean up temp script
                try? FileManager.default.removeItem(atPath: tempScriptPath)
                
                // Check the result
                if let statusData = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/ffmpeg_status.txt")),
                   let statusString = String(data: statusData, encoding: .utf8),
                   statusString.contains("FFMPEG_EXIT_CODE=0") {
                    print("  ✅ FFmpeg blank rush creation completed successfully!")
                    try? FileManager.default.removeItem(atPath: "/tmp/ffmpeg_status.txt")
                    return true
                } else {
                    print("  ❌ FFmpeg script failed or status check failed")
                    try? FileManager.default.removeItem(atPath: "/tmp/ffmpeg_status.txt")
                    return false
                }
                
            } catch {
                print("  ❌ Failed to create or run temp script: \(error)")
                try? FileManager.default.removeItem(atPath: tempScriptPath)
                return false
            }
        }
        
        // Fallback to Process-based approach for non-interactive environments
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath, inputPath, outputPath]
            
            // Always use pipes for compatibility with VideoToolbox encoder
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Set up pipe handlers
            var outputBuffer = ""
            var errorBuffer = ""
            
            // Read output in real-time
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    let output = String(data: data, encoding: .utf8) ?? ""
                    outputBuffer += output
                    
                    // Print progress lines (ffmpeg frame updates) - handle both \n and \r line endings
                    let lines = output.components(separatedBy: CharacterSet(charactersIn: "\n\r"))
                    for line in lines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                        if trimmedLine.contains("frame=") && trimmedLine.contains("fps=") {
                            // Extract progress info - only show every 100 frames to avoid spam
                            if let frameMatch = trimmedLine.range(of: "frame=\\s*(\\d+)", options: .regularExpression) {
                                let frameStr = String(trimmedLine[frameMatch]).replacingOccurrences(of: "frame=", with: "").trimmingCharacters(in: .whitespaces)
                                if let frameNum = Int(frameStr), frameNum % 100 == 0 {
                                    print("    ⏳ \(trimmedLine)")
                                    fflush(stdout)
                                }
                            }
                        } else if trimmedLine.contains("Processing:") || trimmedLine.contains("Source") || trimmedLine.contains("🎬") {
                            print("    📝 \(trimmedLine)")
                            fflush(stdout)
                        } else if !trimmedLine.isEmpty && !trimmedLine.contains("ffmpeg version") && !trimmedLine.contains("built with") && !trimmedLine.contains("configuration:") && !trimmedLine.contains("lib") {
                            // Print any other non-empty output for debugging (skip verbose ffmpeg info)
                            print("    📄 \(trimmedLine)")
                            fflush(stdout)
                        }
                    }
                }
            }
            
            // Read errors in real-time
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    let error = String(data: data, encoding: .utf8) ?? ""
                    errorBuffer += error
                    
                    // Print error lines immediately
                    let lines = error.components(separatedBy: .newlines)
                    for line in lines {
                        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            print("    ⚠️ \(line)")
                            fflush(stdout)
                        }
                    }
                }
                }
            }
            
            // Set working directory to script directory  
            let scriptDirectory = (scriptPath as NSString).deletingLastPathComponent
            process.currentDirectoryURL = URL(fileURLWithPath: scriptDirectory)
            
            // Set termination handler for pipe-based mode
            process.terminationHandler = { process in
                // Close the read handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                if process.terminationStatus == 0 {
                    print("  ✅ FFmpeg blank rush creation completed successfully!")
                    continuation.resume(returning: true)
                } else {
                    print("  ❌ FFmpeg script failed with status \(process.terminationStatus)")
                    continuation.resume(returning: false)
                }
            }
            
            do {
                print("  🚀 Starting FFmpeg process...")
                try process.run()
                
                // Add heartbeat updates every 30 seconds  
                var heartbeatCount = 0
                func scheduleHeartbeat() {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                        if process.isRunning {
                            heartbeatCount += 1
                            print("  💓 FFmpeg still processing... (\(heartbeatCount * 30)s elapsed)")
                            fflush(stdout)
                            scheduleHeartbeat()
                        }
                    }
                }
                scheduleHeartbeat()
                
                // Add a generous timeout (15 minutes for very long videos)
                DispatchQueue.global().asyncAfter(deadline: .now() + 900) {
                    if process.isRunning {
                        print("  ⏰ FFmpeg script timed out after 15 minutes, terminating...")
                        fflush(stdout)
                        process.terminate()
                        continuation.resume(returning: false)
                    }
                }
                
            } catch {
                print("  ❌ Failed to start process: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Create directory if it doesn't exist
    private func createDirectoryIfNeeded(at url: URL) {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                print("📁 Created output directory: \(url.path)")
            } catch {
                print("❌ Failed to create directory: \(error)")
            }
        }
    }
}

// MARK: - Convenience Extensions

extension LinkingResult {
    
    /// Get only OCF parents that have children (useful for blank rush creation)
    var parentsWithChildren: [OCFParent] {
        return ocfParents.filter { $0.hasChildren }
    }
    
    /// Summary of blank rush creation candidates
    var blankRushSummary: String {
        let candidateCount = parentsWithChildren.count
        let totalChildren = parentsWithChildren.reduce(0) { $0 + $1.childCount }
        return "\(candidateCount) OCF parents with \(totalChildren) total children ready for blank rush creation"
    }
}