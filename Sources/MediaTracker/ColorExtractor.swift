import AppKit
import SwiftUI
import ImageIO

struct DominantPair: Sendable, Equatable {
    let primary: Color
    let secondary: Color
}

private struct ColorSwatch {
    let r: Double
    let g: Double
    let b: Double
    let population: Int

    var hue: Double {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        if maxC == r {
            return 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == g {
            return 60.0 * (((b - r) / delta) + 2)
        } else {
            return 60.0 * (((r - g) / delta) + 4)
        }
    }

    var saturation: Double {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        guard maxC > 0 else { return 0 }
        return delta / maxC
    }

    var lightness: Double {
        (max(r, g, b) + min(r, g, b)) / 2.0
    }
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
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let levels = 4
        let bucketCount = levels * levels * levels
        var histogram = [Int](repeating: 0, count: bucketCount)

        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            guard rawData[i+3] > 30 else { continue }

            let r = Double(rawData[i]) / 255.0
            let g = Double(rawData[i+1]) / 255.0
            let b = Double(rawData[i+2]) / 255.0
            let maxC = max(r, g, b)
            let minC = min(r, g, b)

            // Skip near-black and near-white
            guard maxC > 0.08, minC < 0.92 else { continue }

            let ri = min(Int(r * Double(levels)), levels - 1)
            let gi = min(Int(g * Double(levels)), levels - 1)
            let bi = min(Int(b * Double(levels)), levels - 1)
            histogram[ri * levels * levels + gi * levels + bi] += 1

            if i % (bytesPerPixel * 200) == 0 {
                await Task.yield()
            }
        }

        // Build swatches from non-empty buckets
        var swatches: [ColorSwatch] = []
        for idx in 0..<bucketCount {
            guard histogram[idx] > 0 else { continue }
            let ri = idx / (levels * levels)
            let gi = (idx / levels) % levels
            let bi = idx % levels
            // Center of quantization cell
            let r = (Double(ri) + 0.5) / Double(levels)
            let g = (Double(gi) + 0.5) / Double(levels)
            let b = (Double(bi) + 0.5) / Double(levels)
            swatches.append(ColorSwatch(r: r, g: g, b: b, population: histogram[idx]))
        }

        guard !swatches.isEmpty else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        let highestPop = swatches.map(\.population).max() ?? 1

        // Score each swatch against target profiles
        let vibrantScored = swatches.map { ($0, scoreVibrant($0, highestPopulation: highestPop)) }
        let mutedScored = swatches.map { ($0, scoreMuted($0, highestPopulation: highestPop)) }

        guard let bestVibrant = vibrantScored.max(by: { $0.1 < $1.1 }) else {
            return DominantPair(primary: Color(red: 0.3, green: 0.3, blue: 0.3),
                                secondary: Color(red: 0.2, green: 0.2, blue: 0.2))
        }

        let primaryColor = Color(red: bestVibrant.0.r, green: bestVibrant.0.g, blue: bestVibrant.0.b)

        // Find best Muted swatch that is visually distinct from primary
        let minDist = 3
        var secondaryColor = primaryColor
        let sortedMuted = mutedScored.sorted { $0.1 > $1.1 }
        for (swatch, _) in sortedMuted {
            let dr = abs(swatch.r - bestVibrant.0.r)
            let dg = abs(swatch.g - bestVibrant.0.g)
            let db = abs(swatch.b - bestVibrant.0.b)
            let dist = Int((dr + dg + db) * Double(levels))
            if dist >= minDist {
                secondaryColor = Color(red: swatch.r, green: swatch.g, blue: swatch.b)
                break
            }
        }

        return DominantPair(primary: primaryColor, secondary: secondaryColor)
    }

    private static func scoreVibrant(_ swatch: ColorSwatch, highestPopulation: Int) -> Double {
        let targetSatMid = 0.675   // midpoint of 0.35...1.0
        let targetLumMid = 0.5     // midpoint of 0.3...0.7
        return scoreSwatch(swatch, highestPopulation: highestPopulation,
                           targetSatMid: targetSatMid, targetLumMid: targetLumMid)
    }

    private static func scoreMuted(_ swatch: ColorSwatch, highestPopulation: Int) -> Double {
        let targetSatMid = 0.2     // midpoint of 0.0...0.4
        let targetLumMid = 0.5     // midpoint of 0.3...0.7
        return scoreSwatch(swatch, highestPopulation: highestPopulation,
                           targetSatMid: targetSatMid, targetLumMid: targetLumMid)
    }

    private static func scoreSwatch(_ swatch: ColorSwatch, highestPopulation: Int,
                                     targetSatMid: Double, targetLumMid: Double) -> Double {
        let satScore = 1.0 - abs(swatch.saturation - targetSatMid)
        let lumScore = 1.0 - abs(swatch.lightness - targetLumMid)
        let popScore = Double(swatch.population) / Double(highestPopulation)
        // Weight: saturation 3x, lightness 6.5x, population 0.5x
        return (satScore * 3.0 + lumScore * 6.5 + popScore * 0.5) / 10.0
    }
}
