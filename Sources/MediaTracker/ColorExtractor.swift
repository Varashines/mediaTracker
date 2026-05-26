import AppKit
import SwiftUI
import ImageIO

struct DominantPair: Sendable, Equatable {
    let primary: Color
    let secondary: Color
}

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
        let pair = await topTwoColors(from: cgImage)
        return pair.primary
    }

    /// Returns the top 2 distinct colors from a CGImage using 512-bucket histogram.
    /// The two colors are guaranteed to be at least 3 quantization levels apart to
    /// avoid returning near-identical shades.
    static func topTwoColors(from cgImage: CGImage) async -> DominantPair {
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
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

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

        // Build ranked list of buckets sorted by population
        let ranked = histogram.enumerated().filter { $0.element > 0 }
            .sorted { $0.element > $1.element }

        guard let first = ranked.first else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        let idx1 = first.offset
        let r1 = idx1 / (levels * levels)
        let g1 = (idx1 / levels) % levels
        let b1 = idx1 % levels

        let primary = Color(
            red: Double(r1) / Double(levels - 1),
            green: Double(g1) / Double(levels - 1),
            blue: Double(b1) / Double(levels - 1)
        )

        // Find the next bucket at least 3 levels away in LAB distance to ensure visual distinction
        let minLevelDistance = 3
        var secondaryColor = primary
        for bucket in ranked.dropFirst() {
            let idx2 = bucket.offset
            let r2 = idx2 / (levels * levels)
            let g2 = (idx2 / levels) % levels
            let b2 = idx2 % levels

            let dist = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
            if dist >= minLevelDistance {
                secondaryColor = Color(
                    red: Double(r2) / Double(levels - 1),
                    green: Double(g2) / Double(levels - 1),
                    blue: Double(b2) / Double(levels - 1)
                )
                break
            }
        }

        return DominantPair(primary: primary, secondary: secondaryColor)
    }
}
