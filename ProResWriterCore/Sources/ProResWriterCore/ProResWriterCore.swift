//
//  ProResWriterCore.swift
//  ProResWriterCore
//
//  Professional post-production workflow automation core library
//

import Foundation
@_exported import struct SwiftFFmpeg.AVRational

/// ProResWriterCore - Professional Post-Production Workflow Automation
///
/// This library provides a complete media processing pipeline for professional video workflows:
/// - Import: Analyze OCF files and graded segments with comprehensive metadata extraction
/// - Linking: Intelligently match segments to original camera files using timecode analysis
/// - BlankRush: Generate ProRes 4444 blank rushes with timecode burn-in for review
/// - PrintProcess: Create frame-accurate final compositions with broadcast-standard quality
///
/// Key Features:
/// - Professional frame rate support (23.976, 24, 25, 29.97, 30, 50, 59.94, 60fps with DF/NDF)
/// - TimecodeKit integration for broadcast-accurate timecode calculations
/// - VideoToolbox hardware acceleration for maximum performance
/// - SwiftFFmpeg integration for comprehensive media format support
/// - ProRes 4444 quality preservation throughout the workflow
public final class ProResWriterCore {
    
    /// Library version following semantic versioning
    public static let version = "1.0.0"
    
    /// Core components available for workflow automation
    public struct Components {
        /// Media import and analysis system
        public static let importer = "MediaImporter"
        
        /// Segment-to-OCF linking engine
        public static let linker = "SegmentOCFLinker" 
        
        /// Blank rush generation system
        public static let blankRushCreator = "BlankRushCreator"
        
        /// Final composition and export system
        public static let printProcessor = "PrintProcessor"
        
        /// SMPTE timecode utilities
        public static let timecodeUtilities = "SMPTEUtilities"
    }
    
    /// Supported professional video frame rates
    public struct FrameRates {
        /// Film and cinema standards
        public static let film23_976 = "23.976fps (24000/1001)"
        public static let film24 = "24fps (24/1)"
        
        /// Broadcast standards  
        public static let pal25 = "25fps (25/1)"
        public static let ntsc29_97 = "29.97fps (30000/1001)"
        public static let ntsc30 = "30fps (30/1)"
        
        /// High frame rate standards
        public static let pal50 = "50fps (50/1)"
        public static let ntsc59_94 = "59.94fps (60000/1001)"
        public static let ntsc60 = "60fps (60/1)"
    }
    
    private init() {
        // Static library - no instantiation needed
    }
}


// MARK: - Public API Exports

// Re-export key types for consumer convenience
@_exported import Foundation
@_exported import AVFoundation
@_exported import VideoToolbox