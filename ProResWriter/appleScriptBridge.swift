//
//  appleScriptBridge.swift
//  ProResWriter
//
//  Created by Francis Qureshi on 06/08/2025.
//

import Foundation
import Cocoa

// Simple class for AME integration
class ProResWriter {
    // Empty class - just needed for the extension
}

extension ProResWriter {

func createBlankFramesWithAME(sourceFile: URL, completion: @escaping (Result<URL, Error>) -> Void) {
    // Generate output path
    let outputFile = sourceFile.appendingPathExtension("_AME_black_tc")
    let scriptPath = "/Users/fq/Projects/ProResWriter/ProResWriter/Resources/ffmpegScripts/ame_encode.js"
    
    // Create a temporary script with parameters
    let tempScriptContent = """
    var SOURCE_FILE = '\(sourceFile.path)';
    var DEST_PATH = '\(outputFile.deletingLastPathComponent().path)';
    var PRESET_NAME = 'w2Blank';
    
    $.evalFile('\(scriptPath)');
    """
    
    let tempScriptPath = "/tmp/ame_temp_encode.js"
    
    do {
        try tempScriptContent.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
        
        let appleScript = """
        tell application "Adobe Media Encoder 2025"
            activate
            try
                do script file "\(tempScriptPath)"
            on error errMsg
                return "Error: " & errMsg
            end try
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: appleScript)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            
            DispatchQueue.main.async {
                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempScriptPath)
                
                if let error = error {
                    completion(.failure(NSError(domain: "AMEError", code: -1, userInfo: [NSLocalizedDescriptionKey: error.description])))
                } else {
                    let resultString = result?.stringValue ?? "No result"
                    print("📊 AME Script Result: \(resultString)")
                    completion(.success(outputFile))
                }
            }
        }
        
    } catch {
        completion(.failure(error))
    }
}

// Monitor AME encoding progress
func monitorAMEProgress(completion: @escaping (String) -> Void) {
  let monitorScript = """
  tell application "Adobe Media Encoder 2025"
      do script "
          var queue = app.getEncodingQueue();
          var status = 'Items: ' + queue.numItems + ', Encoding: ' + app.isEncodingInProgress();
          status;
      "
  end tell
  """

  let script = NSAppleScript(source: monitorScript)
  if let result = script?.executeAndReturnError(nil) {
      completion(result.stringValue ?? "Unknown status")
  }
}
}
