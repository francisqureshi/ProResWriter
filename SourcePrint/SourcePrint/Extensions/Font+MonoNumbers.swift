//
//  Font+MonoNumbers.swift
//  SourcePrint
//
//  GT Pressura Mono font support for numeric displays
//

import SwiftUI

extension Font {
    static func monoNumbers(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Try to load GT Pressura Mono from app bundle
        if let fontURL = Bundle.main.url(forResource: "gt-pressura-mono-light", withExtension: "ttf") {
            
            // Register the font if needed
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                print("⚠️ Failed to register GT Pressura Mono font: \(error?.takeRetainedValue() as Any)")
            }
            
            // Return GT Pressura Mono font
            return Font.custom("GT Pressura Mono", size: size)
        }
        
        // Fallback to system monospaced if GT Pressura Mono fails
        print("⚠️ GT Pressura Mono not found, using system monospaced")
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
}