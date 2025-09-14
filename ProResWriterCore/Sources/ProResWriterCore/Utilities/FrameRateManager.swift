//
//  FrameRateManager.swift
//  ProResWriterCore
//
//  Centralized frame rate management using rational arithmetic for professional workflows
//  Eliminates precision loss and provides consistent frame rate handling across all modules
//

import Foundation
import SwiftFFmpeg

/// Professional frame rate management using rational arithmetic (numerator/denominator)
/// Ensures broadcast-standard precision for all frame rate operations
public final class FrameRateManager {

    // MARK: - Professional Frame Rate Categories

    /// Professional frame rates defined as exact rational numbers
    public enum ProfessionalFrameRate: CaseIterable {
        // Film/Cinema Standards (24000/1001 family)
        case film23_976    // 23.976fps = 24000/1001
        case film24        // 24fps = 24/1
        case film47_952    // 47.952fps = 48000/1001
        case film48        // 48fps = 48/1
        case film95_904    // 95.904fps = 96000/1001
        case film96        // 96fps = 96/1

        // PAL/European Standards
        case pal25         // 25fps = 25/1
        case pal50         // 50fps = 50/1
        case pal100        // 100fps = 100/1

        // NTSC Standards (30000/1001 family)
        case ntsc29_97     // 29.97fps = 30000/1001
        case ntsc59_94     // 59.94fps = 60000/1001
        case ntsc119_88    // 119.88fps = 120000/1001

        // Integer Standards
        case integer30     // 30fps = 30/1
        case integer60     // 60fps = 60/1
        case integer90     // 90fps = 90/1
        case integer120    // 120fps = 120/1

        // Special/Legacy
        case film24_98     // 24.98fps ≈ 25000/1001

        /// Get the exact rational representation
        public var rational: AVRational {
            switch self {
            // Film/Cinema (24000/1001 family uses exact rational, others use 1000-scale)
            case .film23_976: return AVRational(num: 24000, den: 1001)  // Exact rational for NTSC
            case .film24: return AVRational(num: 24000, den: 1000)      // 1000-scale for precision
            case .film47_952: return AVRational(num: 48000, den: 1001)  // Exact rational for NTSC
            case .film48: return AVRational(num: 48000, den: 1000)      // 1000-scale for precision
            case .film95_904: return AVRational(num: 96000, den: 1001)  // Exact rational for NTSC
            case .film96: return AVRational(num: 96000, den: 1000)      // 1000-scale for precision

            // PAL/European (1000-scale for precision)
            case .pal25: return AVRational(num: 25000, den: 1000)       // 1000-scale for precision
            case .pal50: return AVRational(num: 50000, den: 1000)       // 1000-scale for precision
            case .pal100: return AVRational(num: 100000, den: 1000)     // 1000-scale for precision

            // NTSC (30000/1001 family - exact rational)
            case .ntsc29_97: return AVRational(num: 30000, den: 1001)   // Exact rational for NTSC
            case .ntsc59_94: return AVRational(num: 60000, den: 1001)   // Exact rational for NTSC
            case .ntsc119_88: return AVRational(num: 120000, den: 1001) // Exact rational for NTSC

            // Integer (1000-scale for precision)
            case .integer30: return AVRational(num: 30000, den: 1000)   // 1000-scale for precision
            case .integer60: return AVRational(num: 60000, den: 1000)   // 1000-scale for precision
            case .integer90: return AVRational(num: 90000, den: 1000)   // 1000-scale for precision
            case .integer120: return AVRational(num: 120000, den: 1000) // 1000-scale for precision

            // Special
            case .film24_98: return AVRational(num: 25000, den: 1001)   // Exact rational for NTSC-variant
            }
        }

        /// Get the exact float value for display/compatibility
        public var floatValue: Float {
            return Float(rational.num) / Float(rational.den)
        }

        /// Professional description with rational notation
        public var description: String {
            switch self {
            case .film23_976: return "23.976fps (24000/1001)"
            case .film24: return "24fps (24000/1000)"
            case .film47_952: return "47.952fps (48000/1001)"
            case .film48: return "48fps (48000/1000)"
            case .film95_904: return "95.904fps (96000/1001)"
            case .film96: return "96fps (96000/1000)"
            case .pal25: return "25fps (25000/1000)"
            case .pal50: return "50fps (50000/1000)"
            case .pal100: return "100fps (100000/1000)"
            case .ntsc29_97: return "29.97fps (30000/1001)"
            case .ntsc59_94: return "59.94fps (60000/1001)"
            case .ntsc119_88: return "119.88fps (120000/1001)"
            case .integer30: return "30fps (30000/1000)"
            case .integer60: return "60fps (60000/1000)"
            case .integer90: return "90fps (90000/1000)"
            case .integer120: return "120fps (120000/1000)"
            case .film24_98: return "24.98fps (25000/1001)"
            }
        }

        /// Common drop frame rates for validation
        public var isCommonDropFrameRate: Bool {
            switch self {
            case .ntsc29_97, .ntsc59_94, .ntsc119_88:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Core Methods

    /// Convert float frame rate to professional rational representation
    /// Uses broadcast-standard tolerance for recognition
    public static func convertToRational(frameRate: Float) -> AVRational {
        // Try to match against known professional frame rates
        for professionalRate in ProfessionalFrameRate.allCases {
            if abs(frameRate - professionalRate.floatValue) < 0.001 {
                return professionalRate.rational
            }
        }

        // Fallback: Create rational with reasonable precision
        return AVRational(num: Int32(frameRate * 1000), den: 1000)
    }

    /// Identify professional frame rate from float value
    /// Returns nil if not a recognized professional standard
    public static func identifyProfessionalRate(frameRate: Float) -> ProfessionalFrameRate? {
        for professionalRate in ProfessionalFrameRate.allCases {
            if abs(frameRate - professionalRate.floatValue) < 0.001 {
                return professionalRate
            }
        }
        return nil
    }

    /// Check if two frame rates are compatible using rational arithmetic
    /// This is the authoritative method for frame rate matching across the system
    public static func areFrameRatesCompatible(_ rate1: Float, _ rate2: Float) -> Bool {
        guard let prof1 = identifyProfessionalRate(frameRate: rate1),
              let prof2 = identifyProfessionalRate(frameRate: rate2) else {
            // If either rate is not professional standard, use tight float tolerance
            return abs(rate1 - rate2) < 0.001
        }

        // Professional rates must match exactly by category
        return prof1 == prof2
    }

    /// Generate professional frame rate description with rational notation
    public static func getFrameRateDescription(frameRate: Float?, isDropFrame: Bool? = nil) -> String {
        guard let frameRate = frameRate else { return "Unknown" }

        let dropFrameInfo = isDropFrame == true ? " (drop frame)" : ""

        if let professionalRate = identifyProfessionalRate(frameRate: frameRate) {
            return professionalRate.description + dropFrameInfo
        }

        // Fallback for non-standard rates
        return "\(frameRate)fps\(dropFrameInfo)"
    }

    // MARK: - TimecodeKit Integration

    /// Convert frame rate to TimecodeKit FrameRate enum
    /// Used for professional timecode calculations
    public static func getTimecodeFrameRate(for frameRate: Int32) -> TimecodeFrameRate {
        switch frameRate {
        // Film rates (x/1001)
        case 23: return .fps23_976
        case 24: return .fps24
        case 47: return .fps47_952
        case 48: return .fps48
        case 95: return .fps95_904
        case 96: return .fps96

        // PAL rates
        case 25: return .fps25
        case 50: return .fps50
        case 100: return .fps100

        // NTSC rates (x/1001)
        case 29: return .fps29_97
        case 59: return .fps59_94
        case 119: return .fps119_88

        // Integer rates
        case 30: return .fps30
        case 60: return .fps60
        case 90: return .fps90
        case 120: return .fps120

        default: return .fps25  // Safe PAL default
        }
    }

    /// Get CMTime timescale for frame rate using rational arithmetic
    /// Ensures proper timebase precision for Core Media operations
    public static func getTimescale(for frameRate: Int32) -> CMTimeScale {
        let fps = Double(frameRate)

        // Map integer frame rates to their proper rational rates for NTSC family
        switch frameRate {
        case 23: return 24000   // 23.976fps = 24000/1001
        case 29: return 30000   // 29.97fps = 30000/1001
        case 47: return 48000   // 47.952fps = 48000/1001
        case 59: return 60000   // 59.94fps = 60000/1001
        case 95: return 96000   // 95.904fps = 96000/1001
        case 119: return 120000 // 119.88fps = 120000/1001
        default:
            // For exact integer rates, use simple scaling
            return CMTimeScale(fps * 1000)
        }
    }

    // MARK: - Drop Frame Detection

    /// Detect drop frame based on timecode separator and frame rate
    /// Professional broadcast standard validation
    public static func detectDropFrame(timecode: String, frameRate: Float) -> Bool {
        let hasDropFrameSeparator = timecode.contains(";")
        let isDropFrameRate = ProfessionalFrameRate.allCases
            .filter(\.isCommonDropFrameRate)
            .contains { abs(frameRate - $0.floatValue) < 0.001 }

        if hasDropFrameSeparator && isDropFrameRate {
            return true  // Correct drop frame format
        } else if !hasDropFrameSeparator && !isDropFrameRate {
            return false  // Correct non-drop frame format
        } else {
            // Inconsistent - warn and default based on separator
            return hasDropFrameSeparator
        }
    }

    // MARK: - Validation

    /// Validate that a frame rate is suitable for professional workflows
    public static func isValidProfessionalFrameRate(_ frameRate: Float) -> Bool {
        return identifyProfessionalRate(frameRate: frameRate) != nil
    }

    /// Get all supported professional frame rates for validation/UI
    public static func getAllProfessionalFrameRates() -> [ProfessionalFrameRate] {
        return ProfessionalFrameRate.allCases
    }
}

// MARK: - Extensions

extension AVRational {
    /// Convert rational to float for compatibility
    var floatValue: Float {
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

    /// Convert from legacy float-based frame rates to new rational system
    /// Maintains compatibility while migrating to rational arithmetic
    public static func migrateFromFloat(_ frameRate: Float) -> (rational: AVRational, professional: ProfessionalFrameRate?) {
        let professional = identifyProfessionalRate(frameRate: frameRate)
        let rational = professional?.rational ?? convertToRational(frameRate: frameRate)
        return (rational: rational, professional: professional)
    }
}