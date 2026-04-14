import AppKit
import SwiftUI

class ColorExtractor {
    static func dominantColor(from image: NSImage) -> Color {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return .accentColor
        }
        
        let width = 40
        let height = 60
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var count: CGFloat = 0
        
        // Sample pixels at low resolution to get average dominant color
        for x in stride(from: 0, to: bitmap.pixelsWide, by: bitmap.pixelsWide / width) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: bitmap.pixelsHigh / height) {
                if let color = bitmap.colorAt(x: x, y: y) {
                    // Ignore very bright/white or very dark/black pixels
                    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    if brightness > 0.1 && brightness < 0.9 {
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
