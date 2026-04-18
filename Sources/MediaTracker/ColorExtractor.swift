import AppKit
import SwiftUI

class ColorExtractor {
    static func dominantColor(from image: NSImage) -> Color {
        // Create a tiny thumbnail to sample from - much faster and memory efficient
        let sampleSize = NSSize(width: 40, height: 40)
        let thumbnail = NSImage(size: sampleSize)
        
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: sampleSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return .accentColor
        }
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var count: CGFloat = 0
        
        let pixelsWide = bitmap.pixelsWide
        let pixelsHigh = bitmap.pixelsHigh
        
        // Sample every pixel of our tiny thumbnail
        for x in 0..<pixelsWide {
            for y in 0..<pixelsHigh {
                if let color = bitmap.colorAt(x: x, y: y) {
                    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    // Ignore extreme colors (too dark or too bright)
                    if brightness > 0.15 && brightness < 0.85 {
                        r += color.redComponent
                        g += color.greenComponent
                        b += color.blueComponent
                        count += 1
                    }
                }
            }
        }
        
        if count == 0 { return .accentColor }
        
        return Color(red: Double(r / count), green: Double(g / count), blue: Double(b / count))
    }
}
