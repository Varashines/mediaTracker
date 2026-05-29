import AppKit
import SwiftUI
import CoreImage

struct DominantPair: Sendable, Equatable {
    let primary: Color
    let secondary: Color
}

enum ColorExtractor {
    private static let defaultGray = Color(red: 0.3, green: 0.3, blue: 0.3)
    private static let secondaryGray = Color(red: 0.2, green: 0.2, blue: 0.2)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func dominantColor(from url: URL) async -> Color {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 200
              ] as CFDictionary) else {
            return defaultGray
        }
        return await dominantColor(from: cgImage)
    }

    static func dominantColor(from data: Data) async -> Color {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 200
              ] as CFDictionary) else {
            return defaultGray
        }
        return await dominantColor(from: cgImage)
    }

    static func dominantColor(from image: NSImage) async -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return defaultGray
        }
        return await dominantColor(from: cgImage)
    }

    static func dominantColor(from cgImage: CGImage) async -> Color {
        let pair = await topTwoColors(from: cgImage)
        return pair.primary
    }

    static func topTwoColors(from cgImage: CGImage) async -> DominantPair {
        let ciImage = CIImage(cgImage: cgImage)

        guard let scaledImage = ciContext.createCGImage(
            ciImage,
            from: CGRect(x: 0, y: 0, width: ciImage.extent.width, height: ciImage.extent.height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        let width = scaledImage.width
        let height = scaledImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rawData,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        context.draw(scaledImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels: [(r: Double, g: Double, b: Double)] = []
        pixels.reserveCapacity(width * height)

        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let r = Double(rawData[i])
            let g = Double(rawData[i + 1])
            let b = Double(rawData[i + 2])
            let a = Double(rawData[i + 3])
            guard a > 30 else { continue }
            let maxRGB = max(r, g, b)
            guard maxRGB > 20 else { continue }
            pixels.append((r, g, b))
        }

        guard !pixels.isEmpty else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        let avgR = pixels.map(\.r).reduce(0, +) / Double(pixels.count)
        let avgG = pixels.map(\.g).reduce(0, +) / Double(pixels.count)
        let avgB = pixels.map(\.b).reduce(0, +) / Double(pixels.count)
        let range = max(avgR, avgG, avgB) - min(avgR, avgG, avgB)

        if range < 25 {
            let gray = avgR / 255.0
            return DominantPair(
                primary: Color(red: gray, green: gray, blue: gray),
                secondary: Color(red: gray * 0.7, green: gray * 0.7, blue: gray * 0.7)
            )
        }

        struct ColorCandidate {
            let r: Double
            let g: Double
            let b: Double
            let saturation: Double
        }

        var candidates: [ColorCandidate] = []
        let step = max(1, pixels.count / 200)
        for idx in stride(from: 0, to: pixels.count, by: step) {
            let p = pixels[idx]
            let maxC = max(p.r, p.g, p.b)
            let minC = min(p.r, p.g, p.b)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            candidates.append(ColorCandidate(r: p.r, g: p.g, b: p.b, saturation: sat))
        }

        candidates.sort { $0.saturation > $1.saturation }

        guard let top = candidates.first else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        let primaryColor = Color(red: top.r / 255.0, green: top.g / 255.0, blue: top.b / 255.0)

        var secondaryColor = primaryColor
        let primaryHue = rgbToHue(r: top.r / 255.0, g: top.g / 255.0, b: top.b / 255.0)

        for candidate in candidates.dropFirst() {
            let cHue = rgbToHue(r: candidate.r / 255.0, g: candidate.g / 255.0, b: candidate.b / 255.0)
            let hueDiff = abs(primaryHue - cHue)
            if hueDiff > 30 || (360 - hueDiff) > 30 {
                secondaryColor = Color(red: candidate.r / 255.0, green: candidate.g / 255.0, blue: candidate.b / 255.0)
                break
            }
        }

        return DominantPair(primary: primaryColor, secondary: secondaryColor)
    }

    private static func rgbToHue(r: Double, g: Double, b: Double) -> Double {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        let hue: Double
        if maxC == r {
            hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == g {
            hue = 60 * (((b - r) / delta) + 2)
        } else {
            hue = 60 * (((r - g) / delta) + 4)
        }
        return hue < 0 ? hue + 360 : hue
    }
}
