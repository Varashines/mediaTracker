import AppKit
import SwiftUI
import ImageIO

@MainActor
class ColorExtractor {
    /// Extracts the dominant color using high-performance ImageIO thumbnails to minimize memory pressure.
    static func dominantColor(from url: URL) -> Color {
        // LOCKDOWN: Skip pixel processing if hibernating
        if SleepManager.shared.isAsleep { return .accentColor }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 40
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .accentColor
        }
        
        return dominantColor(from: cgImage)
    }

    static func dominantColor(from data: Data) -> Color {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 40
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .accentColor
        }
        
        return dominantColor(from: cgImage)
    }

    static func dominantColor(from image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .accentColor
        }
        return dominantColor(from: cgImage)
    }

    static func dominantColor(from cgImage: CGImage) -> Color {
        // Sample every pixel of the small 40x40 thumbnail
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(data: &rawData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return .accentColor
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        var count: Float = 0
        
        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let pr = Float(rawData[i]) / 255.0
            let pg = Float(rawData[i+1]) / 255.0
            let pb = Float(rawData[i+2]) / 255.0
            
            let brightness = (pr + pg + pb) / 3.0
            // Exclude extreme darks and extreme lights
            if brightness > 0.15 && brightness < 0.85 {
                r += pr
                g += pg
                b += pb
                count += 1
            }
        }
        
        if count == 0 { return .accentColor }
        
        return Color(red: Double(r / count), green: Double(g / count), blue: Double(b / count))
    }
}
