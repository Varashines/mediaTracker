import AppKit
import SwiftUI
import ImageIO

/// Phase 2 Optimization: Off-thread Color Extraction
enum ColorExtractor {
    /// Extracts the dominant color using high-performance ImageIO thumbnails to minimize memory pressure.
    static func dominantColor(from url: URL) async -> Color {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 120
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        }
        
        return await dominantColor(from: cgImage)
    }

    static func dominantColor(from data: Data) async -> Color {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 120
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        }
        
        return await dominantColor(from: cgImage)
    }

    static func dominantColor(from image: NSImage) async -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        }
        return await dominantColor(from: cgImage)
    }

    static func dominantColor(from cgImage: CGImage) async -> Color {
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
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // Histogram: quantize into 512 buckets (8 levels per channel)
        let levels = 8
        var histogram = [Int](repeating: 0, count: levels * levels * levels)

        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            guard Float(rawData[i+3]) > 30 else { continue }

            let ri = min(Int(Float(rawData[i]) / 255.0 * Float(levels)), levels - 1)
            let gi = min(Int(Float(rawData[i+1]) / 255.0 * Float(levels)), levels - 1)
            let bi = min(Int(Float(rawData[i+2]) / 255.0 * Float(levels)), levels - 1)
            histogram[ri * levels * levels + gi * levels + bi] += 1

            if i % (bytesPerPixel * 200) == 0 {
                await Task.yield()
            }
        }

        guard let maxCount = histogram.max(), maxCount > 0 else { return Color(red: 0.3, green: 0.3, blue: 0.3) }

        let maxIdx = histogram.firstIndex(of: maxCount) ?? 0
        return Color(
            red: Double(maxIdx / (levels * levels)) / Double(levels - 1),
            green: Double((maxIdx / levels) % levels) / Double(levels - 1),
            blue: Double(maxIdx % levels) / Double(levels - 1)
        )
    }
}
