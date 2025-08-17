//
//  SMPTE.swift
//  ProResWriter
//
//  Created by Francis Qureshi on 17/08/2025.
//  Swift port of https://github.com/IgorRidanovic/smpte
//

import Foundation

/// Frames to SMPTE timecode converter and reverse.
/// Swift port of Igor Riđanović's Python SMPTE library
class SMPTE {
    
    /// Frame rate (default: 24.0)
    var fps: Double = 24.0
    
    /// Drop frame flag (default: false)
    var df: Bool = false
    
    init() {}
    
    init(fps: Double, dropFrame: Bool = false) {
        self.fps = fps
        self.df = dropFrame
    }
    
    /// Converts SMPTE timecode to frame count
    /// - Parameter tc: Timecode string in format "HH:MM:SS:FF" or "HH:MM:SS;FF" for drop frame
    /// - Returns: Frame count as Int
    /// - Throws: ValueError if timecode format is invalid or frame rate mismatch
    func getFrames(tc: String) throws -> Int {
        // Normalize separator to : for parsing
        let normalizedTC = tc.replacingOccurrences(of: ";", with: ":")
        let components = normalizedTC.split(separator: ":")
        
        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let frames = Int(components[3]) else {
            throw SMPTEError.invalidTimecodeFormat(tc)
        }
        
        if Double(frames) > fps {
            throw SMPTEError.frameRateMismatch(tc, fps)
        }
        
        let totalMinutes = 60 * hours + minutes
        
        // Drop frame calculation using the Duncan/Heidelberger method
        if df {
            let dropFrames = Int(round(fps * 0.066666))
            let timeBase = Int(round(fps))
            
            let hourFrames = timeBase * 60 * 60
            let minuteFrames = timeBase * 60
            
            let frm = ((hourFrames * hours) + (minuteFrames * minutes) + (timeBase * seconds) + frames) - (dropFrames * (totalMinutes - (totalMinutes / 10)))
            
            return frm
        }
        // Non drop frame calculation
        else {
            let fpsInt = Int(round(fps))
            let frm = (totalMinutes * 60 + seconds) * fpsInt + frames
            
            return frm
        }
    }
    
    /// Converts frame count to SMPTE timecode
    /// - Parameter frames: Frame count
    /// - Returns: SMPTE timecode string in format "HH:MM:SS:FF" or "HH:MM:SS;FF" for drop frame
    func getTC(frames: Int) -> String {
        let absFrames = abs(frames)
        
        // Drop frame calculation using the Duncan/Heidelberger method
        if df {
            let spacer = ":"
            let spacer2 = ";"
            
            let dropFrames = Int(round(fps * 0.066666))
            let framesPerHour = Int(round(fps * 3600))
            let framesPer24Hours = framesPerHour * 24
            let framesPer10Minutes = Int(round(fps * 600))
            let framesPerMinute = Int(round(fps)) * 60 - dropFrames
            
            var workingFrames = absFrames % framesPer24Hours
            
            let d = workingFrames / framesPer10Minutes
            let m = workingFrames % framesPer10Minutes
            
            if m > dropFrames {
                workingFrames = workingFrames + (dropFrames * 9 * d) + dropFrames * ((m - dropFrames) / framesPerMinute)
            } else {
                workingFrames = workingFrames + dropFrames * 9 * d
            }
            
            let frRound = Int(round(fps))
            let hr = workingFrames / frRound / 60 / 60
            let mn = (workingFrames / frRound / 60) % 60
            let sc = (workingFrames / frRound) % 60
            let fr = workingFrames % frRound
            
            return String(format: "%02d%@%02d%@%02d%@%02d", hr, spacer, mn, spacer, sc, spacer2, fr)
        }
        // Non drop frame calculation
        else {
            let fpsInt = Int(round(fps))
            let spacer = ":"
            
            let frHour = fpsInt * 3600
            let frMin = fpsInt * 60
            
            let hr = absFrames / frHour
            let mn = (absFrames - hr * frHour) / frMin
            let sc = (absFrames - hr * frHour - mn * frMin) / fpsInt
            let fr = Int(round(Double(absFrames - hr * frHour - mn * frMin - sc * fpsInt)))
            
            return String(format: "%02d%@%02d%@%02d%@%02d", hr, spacer, mn, spacer, sc, spacer, fr)
        }
    }
}

// MARK: - Error Types

enum SMPTEError: Error, LocalizedError {
    case invalidTimecodeFormat(String)
    case frameRateMismatch(String, Double)
    
    var errorDescription: String? {
        switch self {
        case .invalidTimecodeFormat(let tc):
            return "Invalid timecode format: \(tc). Expected format: HH:MM:SS:FF or HH:MM:SS;FF"
        case .frameRateMismatch(let tc, let fps):
            return "SMPTE timecode to frame rate mismatch. Timecode: \(tc), FPS: \(fps)"
        }
    }
}

// MARK: - Convenience Extensions

extension SMPTE {
    
    /// Add frames to a timecode
    /// - Parameters:
    ///   - timecode: Starting timecode
    ///   - frames: Number of frames to add
    /// - Returns: New timecode string
    /// - Throws: SMPTEError if invalid
    func addFrames(to timecode: String, frames: Int) throws -> String {
        let startFrames = try getFrames(tc: timecode)
        let endFrames = startFrames + frames
        return getTC(frames: endFrames)
    }
    
    /// Calculate the difference between two timecodes in frames
    /// - Parameters:
    ///   - startTC: Start timecode
    ///   - endTC: End timecode
    /// - Returns: Frame difference
    /// - Throws: SMPTEError if invalid
    func frameDifference(from startTC: String, to endTC: String) throws -> Int {
        let startFrames = try getFrames(tc: startTC)
        let endFrames = try getFrames(tc: endTC)
        return endFrames - startFrames
    }
    
    /// Check if a timecode is valid for the current frame rate
    /// - Parameter timecode: Timecode to validate
    /// - Returns: true if valid, false otherwise
    func isValidTimecode(_ timecode: String) -> Bool {
        do {
            _ = try getFrames(tc: timecode)
            return true
        } catch {
            return false
        }
    }
}
