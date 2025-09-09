//
//  Font+MonoNumbers.swift
//  SourcePrint
//
//  SF Pro font support with monospaced digits
//

import SwiftUI

extension Font {
    static func monoNumbers(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Use SF Pro system font - monospaced digits will be applied via .monospacedDigit() modifier
        return Font.system(size: size, weight: weight)
    }
}