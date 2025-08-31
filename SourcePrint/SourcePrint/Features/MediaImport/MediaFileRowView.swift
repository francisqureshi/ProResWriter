//
//  MediaFileRowView.swift
//  SourcePrint
//
//  Created by Francis Qureshi on 31/08/2025.
//

import SwiftUI
import ProResWriterCore

struct MediaFileRowView: View {
    let file: MediaFileInfo
    let type: MediaType
    
    enum MediaType {
        case ocf, segment
    }
    
    var body: some View {
        HStack {
            Image(systemName: type == .ocf ? "camera" : "scissors")
                .foregroundColor(type == .ocf ? .blue : .orange)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    if let frames = file.durationInFrames, let fps = file.frameRate {
                        Text("\(Double(frames) / Double(fps), specifier: "%.2f")s")
                    } else {
                        Text("Unknown duration")
                    }
                    Text("•")
                    Text("\(file.durationInFrames ?? 0) frames")
                    Text("•")
                    Text("\(file.frameRate ?? 0, specifier: "%.3f") fps")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if let startTC = file.sourceTimecode {
                    Text("TC: \(startTC)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text("\(file.mediaType)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    // Create a sample MediaFileInfo for preview
    let sampleFile = MediaFileInfo(
        fileName: "C20250825_0303.mov",
        url: URL(fileURLWithPath: "/path/to/file.mov"),
        resolution: CGSize(width: 3840, height: 2160),
        displayResolution: CGSize(width: 3840, height: 2160),
        sampleAspectRatio: "1:1",
        frameRate: 25.0,
        sourceTimecode: "20:16:31:13",
        endTimecode: "20:17:16:01",
        durationInFrames: 1320,
        isDropFrame: false,
        reelName: nil,
        isInterlaced: false,
        fieldOrder: "progressive",
        mediaType: .originalCameraFile
    )
    
    VStack {
        MediaFileRowView(file: sampleFile, type: .ocf)
        MediaFileRowView(file: sampleFile, type: .segment)
    }
    .padding()
}