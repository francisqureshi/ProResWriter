//
//  FrameRateManager.swift
//  SourcePrintCore
//
//  Centralized frame rate management using rational arithmetic for professional workflows
//  Eliminates precision loss and provides consistent frame rate handling across all modules
//

import Foundation
import SwiftFFmpeg

/// Professional frame rate management using rational arithmetic (numerator/denominator)
/// Ensures broadcast-standard precision for all frame rate operations
/// Direct rational support - no enum restrictions, handles any frame rate
public final class FrameRateManager {

    // MARK: - Core Methods

    /// Convert float frame rate to rational representation
    /// Uses exact NTSC rationals for common rates, 1000-scale for others
    public static func convertToRational(frameRate: Float) -> AVRational {
        // Check for common NTSC rates that need exact rationals
        if abs(frameRate - 23.976) < 0.001 {
            return AVRational(num: 24000, den: 1001)  // Exact NTSC
        } else if abs(frameRate - 29.97) < 0.001 {
            return AVRational(num: 30000, den: 1001)  // Exact NTSC
        } else if abs(frameRate - 59.94) < 0.001 {
            return AVRational(num: 60000, den: 1001)  // Exact NTSC
        } else if abs(frameRate - 47.952) < 0.001 {
            return AVRational(num: 48000, den: 1001)  // Exact NTSC
        } else if abs(frameRate - 95.904) < 0.001 {
            return AVRational(num: 96000, den: 1001)  // Exact NTSC
        } else if abs(frameRate - 119.88) < 0.001 {
            return AVRational(num: 120000, den: 1001)  // Exact NTSC
        } else {
            // Use 1000-scale for all other frame rates
            return AVRational(num: Int32(frameRate * 1000), den: 1000)
        }
    }

    /// Check if frame rate is a known drop frame rate
    /// Based on common professional standards
    public static func isDropFrameRate(frameRate: AVRational) -> Bool {
        let floatValue = Float(frameRate.num) / Float(frameRate.den)
        // Common drop frame rates (NTSC family)
        return abs(floatValue - 29.97) < 0.001 ||
               abs(floatValue - 59.94) < 0.001 ||
               abs(floatValue - 119.88) < 0.001
    }

    /// Check if two frame rates are compatible using rational arithmetic
    /// This is the authoritative method for frame rate matching across the system
    public static func areFrameRatesCompatible(_ rate1: AVRational, _ rate2: AVRational) -> Bool {
        // Compare the actual values, not just the raw numerator/denominator
        // This allows 24/1 to match 24000/1000
        let value1 = Float(rate1.num) / Float(rate1.den)
        let value2 = Float(rate2.num) / Float(rate2.den)
        return abs(value1 - value2) < 0.001
    }

    /// Check if two float frame rates are compatible (legacy support)
    /// Converts to rational for precise comparison
    public static func areFrameRatesCompatible(_ rate1: Float, _ rate2: Float) -> Bool {
        let rational1 = convertToRational(frameRate: rate1)
        let rational2 = convertToRational(frameRate: rate2)
        return areFrameRatesCompatible(rational1, rational2)
    }

    /// Generate professional frame rate description with rational notation
    public static func getFrameRateDescription(frameRate: AVRational?, isDropFrame: Bool? = nil) -> String {
        guard let frameRate = frameRate else { return "Unknown" }

        let floatValue = Float(frameRate.num) / Float(frameRate.den)
        let dropFrameInfo = isDropFrame == true ? " (drop frame)" : ""

        return "\(floatValue)fps (\(frameRate.num)/\(frameRate.den))\(dropFrameInfo)"
    }

    /// Generate frame rate description from float (legacy support)
    public static func getFrameRateDescription(frameRate: Float?, isDropFrame: Bool? = nil) -> String {
        guard let frameRate = frameRate else { return "Unknown" }

        let rational = convertToRational(frameRate: frameRate)
        return getFrameRateDescription(frameRate: rational, isDropFrame: isDropFrame)
    }

    // MARK: - TimecodeKit Integration

    /// Convert rational frame rate to TimecodeKit FrameRate enum
    /// Used for professional timecode calculations
    public static func getTimecodeFrameRate(for frameRate: AVRational) -> TimecodeFrameRate {
        let floatValue = Float(frameRate.num) / Float(frameRate.den)

        // Match common professional frame rates with tolerance
        if abs(floatValue - 23.976) < 0.001 { return .fps23_976 }
        if abs(floatValue - 24.0) < 0.001 { return .fps24 }
        if abs(floatValue - 25.0) < 0.001 { return .fps25 }
        if abs(floatValue - 29.97) < 0.001 { return .fps29_97 }
        if abs(floatValue - 30.0) < 0.001 { return .fps30 }
        if abs(floatValue - 47.952) < 0.001 { return .fps47_952 }
        if abs(floatValue - 48.0) < 0.001 { return .fps48 }
        if abs(floatValue - 50.0) < 0.001 { return .fps50 }
        if abs(floatValue - 59.94) < 0.001 { return .fps59_94 }
        if abs(floatValue - 60.0) < 0.001 { return .fps60 }
        if abs(floatValue - 90.0) < 0.001 { return .fps90 }
        if abs(floatValue - 95.904) < 0.001 { return .fps95_904 }
        if abs(floatValue - 96.0) < 0.001 { return .fps96 }
        if abs(floatValue - 100.0) < 0.001 { return .fps100 }
        if abs(floatValue - 119.88) < 0.001 { return .fps119_88 }
        if abs(floatValue - 120.0) < 0.001 { return .fps120 }

        // Default fallback - use closest standard rate
        return .fps25  // Safe PAL default
    }

    /// Convert integer frame rate to TimecodeKit (legacy support)
    internal static func getTimecodeFrameRate(for frameRate: Int32) -> TimecodeFrameRate {
        // Map common integer shortcuts to their actual NTSC rates
        switch frameRate {
        case 23: return getTimecodeFrameRate(for: AVRational(num: 24000, den: 1001))  // 23.976
        case 29: return getTimecodeFrameRate(for: AVRational(num: 30000, den: 1001))  // 29.97
        case 47: return getTimecodeFrameRate(for: AVRational(num: 48000, den: 1001))  // 47.952
        case 59: return getTimecodeFrameRate(for: AVRational(num: 60000, den: 1001))  // 59.94
        case 95: return getTimecodeFrameRate(for: AVRational(num: 96000, den: 1001))  // 95.904
        case 119: return getTimecodeFrameRate(for: AVRational(num: 120000, den: 1001)) // 119.88
        default:
            let rational = AVRational(num: frameRate * 1000, den: 1000)
            return getTimecodeFrameRate(for: rational)
        }
    }

    /// Get CMTime timescale for rational frame rate
    /// Ensures proper timebase precision for Core Media operations
    public static func getTimescale(for frameRate: AVRational) -> CMTimeScale {
        // Use numerator as timescale for precise rational representation
        return CMTimeScale(frameRate.num)
    }

    /// Get CMTime timescale for integer frame rate (legacy support)
    internal static func getTimescale(for frameRate: Int32) -> CMTimeScale {
        // Map common integer shortcuts to their actual NTSC rates
        switch frameRate {
        case 23: return getTimescale(for: AVRational(num: 24000, den: 1001))  // 23.976
        case 29: return getTimescale(for: AVRational(num: 30000, den: 1001))  // 29.97
        case 47: return getTimescale(for: AVRational(num: 48000, den: 1001))  // 47.952
        case 59: return getTimescale(for: AVRational(num: 60000, den: 1001))  // 59.94
        case 95: return getTimescale(for: AVRational(num: 96000, den: 1001))  // 95.904
        case 119: return getTimescale(for: AVRational(num: 120000, den: 1001)) // 119.88
        default:
            let rational = AVRational(num: frameRate * 1000, den: 1000)
            return getTimescale(for: rational)
        }
    }

    // MARK: - Drop Frame Detection

    /// Detect drop frame based on timecode separator and frame rate
    /// Professional broadcast standard validation
    public static func detectDropFrame(timecode: String, frameRate: AVRational) -> Bool {
        let hasDropFrameSeparator = timecode.contains(";")
        let isKnownDropFrameRate = isDropFrameRate(frameRate: frameRate)

        if hasDropFrameSeparator && isKnownDropFrameRate {
            return true  // Correct drop frame format
        } else if !hasDropFrameSeparator && !isKnownDropFrameRate {
            return false  // Correct non-drop frame format
        } else {
            // Inconsistent - warn and default based on separator
            return hasDropFrameSeparator
        }
    }

    /// Detect drop frame from float frame rate (legacy support)
    public static func detectDropFrame(timecode: String, frameRate: Float) -> Bool {
        let rational = convertToRational(frameRate: frameRate)
        return detectDropFrame(timecode: timecode, frameRate: rational)
    }

    // MARK: - Validation and Utilities

    /// Validate that a frame rate is reasonable for workflows
    /// Any frame rate above 1fps and below 1000fps is considered valid
    public static func isValidFrameRate(_ frameRate: AVRational) -> Bool {
        let floatValue = Float(frameRate.num) / Float(frameRate.den)
        return floatValue > 1.0 && floatValue < 1000.0
    }
}

// MARK: - Extensions

extension AVRational {
    /// Convert rational to float for compatibility
    public var floatValue: Float {
        return Float(num) / Float(den)
    }

    /// Professional description of rational frame rate
    var professionalDescription: String {
        return "\(num)/\(den)"
    }
}

import TimecodeKit

// MARK: - Compatibility Extensions
extension FrameRateManager {

    /// Convert from legacy float-based frame rates to rational system
    /// Direct rational conversion without enum intermediates
    public static func migrateFromFloat(_ frameRate: Float) -> AVRational {
        return convertToRational(frameRate: frameRate)
    }
}