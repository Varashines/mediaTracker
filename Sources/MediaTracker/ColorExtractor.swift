import AppKit
import SwiftUI
import ImageIO

struct DominantPair: Sendable, Equatable {
    let primary: Color
    let secondary: Color
}

enum ColorExtractor {
    static func dominantColor(from url: URL) async -> Color {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 200
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
            kCGImageSourceThumbnailMaxPixelSize: 200
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
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // Convert raw bytes to ARGB Ints
        var pixels = [Int]()
        pixels.reserveCapacity(width * height)

        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            guard rawData[i] > 30 else { continue }

            let a = Int(rawData[i])
            let r = Int(rawData[i + 1])
            let g = Int(rawData[i + 2])
            let b = Int(rawData[i + 3])

            let argb = (a << 24) | (r << 16) | (g << 8) | b
            pixels.append(argb)
        }

        guard !pixels.isEmpty else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        // Quantize using Material Color Utilities
        let quantized = QuantizerCelebi().quantize(pixels, 16)

        // Check if the image is mostly grayscale (low chroma)
        let isGrayscale = isGrayscaleImage(quantized: quantized)

        if isGrayscale {
            return extractGrayscaleColors(quantized: quantized)
        }

        // Normal color path: score for UI theme suitability
        let scored = Score.score(quantized.colorToCount, desired: 4)

        guard let primaryARGB = scored.first else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        let primaryColor = Color(argb: primaryARGB)

        // Find a secondary color that is visually distinct
        var secondaryColor = primaryColor
        if scored.count > 1 {
            let primaryHct = Hct(primaryARGB)
            for argb in scored.dropFirst() {
                let candidateHct = Hct(argb)
                let hueDiff = abs(primaryHct.hue - candidateHct.hue)
                let chromaDiff = abs(primaryHct.chroma - candidateHct.chroma)
                if hueDiff > 30 || chromaDiff > 20 {
                    secondaryColor = Color(argb: argb)
                    break
                }
            }
        }

        return DominantPair(primary: primaryColor, secondary: secondaryColor)
    }

    /// Detect if the quantized image is mostly grayscale
    private static func isGrayscaleImage(quantized: QuantizerResult) -> Bool {
        var totalChroma: Double = 0
        var totalCount: Int = 0

        for (argb, count) in quantized.colorToCount {
            let hct = Hct(argb)
            totalChroma += hct.chroma * Double(count)
            totalCount += count
        }

        guard totalCount > 0 else { return true }
        let averageChroma = totalChroma / Double(totalCount)

        // If average chroma is below 12, treat as grayscale
        // (normal colorful images typically have chroma > 20)
        return averageChroma < 12
    }

    /// Extract colors from grayscale images using the most common gray tones
    private static func extractGrayscaleColors(quantized: QuantizerResult) -> DominantPair {
        // Sort quantized colors by population (most common first)
        let sorted = quantized.colorToCount.sorted { $0.value > $1.value }

        guard let dominantARGB = sorted.first?.key else {
            return DominantPair(primary: Color(red: 0.5, green: 0.5, blue: 0.5),
                                secondary: Color(red: 0.35, green: 0.35, blue: 0.35))
        }

        let dominantHct = Hct(dominantARGB)
        let tone = dominantHct.tone

        // Create a slightly tinted gray based on the tone
        // Warm tint for lighter grays, cool tint for darker grays
        let primaryColor: Color
        if tone > 50 {
            // Light gray → warm tint (slight sepia)
            let r = min(1.0, Double((dominantARGB >> 16) & 0xFF) / 255.0 * 1.05)
            let g = min(1.0, Double((dominantARGB >> 8) & 0xFF) / 255.0 * 1.0)
            let b = Double(dominantARGB & 0xFF) / 255.0 * 0.95
            primaryColor = Color(red: r, green: g, blue: b)
        } else {
            // Dark gray → cool tint (slight blue cast)
            let r = Double((dominantARGB >> 16) & 0xFF) / 255.0 * 0.95
            let g = Double((dominantARGB >> 8) & 0xFF) / 255.0 * 0.98
            let b = min(1.0, Double(dominantARGB & 0xFF) / 255.0 * 1.05)
            primaryColor = Color(red: r, green: g, blue: b)
        }

        // Secondary: slightly different gray tone
        var secondaryColor = Color(red: 0.35, green: 0.35, blue: 0.35)
        if sorted.count > 1, let secondARGB = sorted.dropFirst().first?.key {
            let secondHct = Hct(secondARGB)
            let secondTone = secondHct.tone
            // Use a lighter or darker gray as secondary
            let adjusted = secondTone > tone ? min(100, secondTone + 10) : max(0, secondTone - 10)
            let sR = adjusted / 100.0
            secondaryColor = Color(red: sR, green: sR, blue: sR)
        }

        return DominantPair(primary: primaryColor, secondary: secondaryColor)
    }
}

private extension Color {
    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
