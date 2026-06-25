import AppKit
import SwiftUI
import Vision

struct DominantPair: Sendable, Equatable {
    let primary: Color
    let secondary: Color
}

enum ColorExtractor {
    private static let defaultGray = Color(red: 0.3, green: 0.3, blue: 0.3)
    private static let secondaryGray = Color(red: 0.2, green: 0.2, blue: 0.2)

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
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rawData,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Generate saliency map using Vision attention-based saliency
        let saliencyData = await generateSaliencyData(from: cgImage)

        var pixels: [(r: Int, g: Int, b: Int)] = []
        pixels.reserveCapacity(width * height)

        let salWidth = saliencyData?.width ?? 0
        let salHeight = saliencyData?.height ?? 0
        let salValues = saliencyData?.values

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let i = rowOffset + x * bytesPerPixel
                let r = rawData[i]
                let g = rawData[i + 1]
                let b = rawData[i + 2]
                let a = rawData[i + 3]
                guard a > 30 else { continue }
                let maxRGB = max(r, g, b)
                guard maxRGB > 20 else { continue }

                // Compute saliency weight for this pixel
                let weight: Float
                if let salValues, salWidth > 0, salHeight > 0 {
                    let sx = min(x * salWidth / width, salWidth - 1)
                    let sy = min(y * salHeight / height, salHeight - 1)
                    weight = salValues[sy * salWidth + sx]
                } else {
                    weight = 1.0
                }

                // Weight floor of 0.1 ensures non-salient pixels still contribute
                let copies = max(1, Int(max(weight, 0.1) * 10))
                let pixel = (Int(r), Int(g), Int(b))
                for _ in 0..<copies {
                    pixels.append(pixel)
                }
            }
        }

        guard !pixels.isEmpty else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        // Check if image is essentially grayscale
        let avgR = pixels.map(\.r).reduce(0, +) / pixels.count
        let avgG = pixels.map(\.g).reduce(0, +) / pixels.count
        let avgB = pixels.map(\.b).reduce(0, +) / pixels.count
        let range = max(avgR, avgG, avgB) - min(avgR, avgG, avgB)
        if range < 25 {
            let gray = Double(avgR) / 255.0
            return DominantPair(
                primary: Color(red: gray, green: gray, blue: gray),
                secondary: Color(red: gray * 0.7, green: gray * 0.7, blue: gray * 0.7)
            )
        }

        // Median cut: split RGB space into boxes at the median of the widest channel
        struct Box {
            var pixels: [(r: Int, g: Int, b: Int)]
            var count: Int { pixels.count }
        }

        func splitBox(_ box: Box) -> (Box, Box) {
            let rMin = box.pixels.map(\.r).min()!
            let rMax = box.pixels.map(\.r).max()!
            let gMin = box.pixels.map(\.g).min()!
            let gMax = box.pixels.map(\.g).max()!
            let bMin = box.pixels.map(\.b).min()!
            let bMax = box.pixels.map(\.b).max()!
            let rRange = rMax - rMin
            let gRange = gMax - gMin
            let bRange = bMax - bMin

            let channel: Int // 0=R, 1=G, 2=B
            if rRange >= gRange && rRange >= bRange {
                channel = 0
            } else if gRange >= rRange && gRange >= bRange {
                channel = 1
            } else {
                channel = 2
            }

            let mid = box.count / 2
            let sortedPixels = box.pixels.sorted { a, b in
                switch channel {
                case 0: return a.r < b.r
                case 1: return a.g < b.g
                default: return a.b < b.b
                }
            }
            let left = Box(pixels: Array(sortedPixels[0..<mid]))
            let right = Box(pixels: Array(sortedPixels[mid...]))
            return (left, right)
        }

        var boxes = [Box(pixels: pixels)]
        for _ in 0..<8 {
            guard let idx = boxes.enumerated().max(by: { $0.element.count < $1.element.count })?.offset else { break }
            let largest = boxes.remove(at: idx)
            let (left, right) = splitBox(largest)
            boxes.append(left)
            boxes.append(right)
        }

        // Compute centroid and saturation for each box
        struct BoxResult {
            let count: Int
            let r: Double
            let g: Double
            let b: Double
            let saturation: Double
        }

        let results: [BoxResult] = boxes.map { box in
            let rSum = box.pixels.map(\.r).reduce(0, +)
            let gSum = box.pixels.map(\.g).reduce(0, +)
            let bSum = box.pixels.map(\.b).reduce(0, +)
            let cnt = box.count
            let cr = Double(rSum) / Double(cnt)
            let cg = Double(gSum) / Double(cnt)
            let cb = Double(bSum) / Double(cnt)
            let maxC = max(cr, cg, cb)
            let minC = min(cr, cg, cb)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            return BoxResult(count: cnt, r: cr, g: cg, b: cb, saturation: sat)
        }

        // Filter: keep clusters with meaningful saturation and lightness
        let filtered = results.filter { box in
            let lightness = (box.r + box.g + box.b) / (255.0 * 3)
            return box.saturation >= 0.08 && lightness >= 0.08
        }

        // If all were filtered out (desaturated image), use the largest box overall
        let candidates = filtered.isEmpty ? results : filtered
        let sorted = candidates.sorted { $0.count > $1.count }

        guard let primaryResult = sorted.first else {
            let gray = Double(avgR) / 255.0
            return DominantPair(
                primary: Color(red: gray, green: gray, blue: gray),
                secondary: Color(red: gray * 0.7, green: gray * 0.7, blue: gray * 0.7)
            )
        }

        let primaryColor = Color(red: primaryResult.r / 255.0, green: primaryResult.g / 255.0, blue: primaryResult.b / 255.0)

        // Secondary: first box with >30° hue difference from primary
        var secondaryColor = primaryColor
        let primaryHue = rgbToHue(r: primaryResult.r / 255.0, g: primaryResult.g / 255.0, b: primaryResult.b / 255.0)
        for boxResult in sorted.dropFirst() {
            let cHue = rgbToHue(r: boxResult.r / 255.0, g: boxResult.g / 255.0, b: boxResult.b / 255.0)
            let hueDiff = abs(primaryHue - cHue)
            if hueDiff > 30 || (360 - hueDiff) > 30 {
                secondaryColor = Color(red: boxResult.r / 255.0, green: boxResult.g / 255.0, blue: boxResult.b / 255.0)
                break
            }
        }

        return DominantPair(primary: primaryColor, secondary: secondaryColor)
    }

    // MARK: - Vision Saliency

    private struct SaliencyData {
        let values: [Float]
        let width: Int
        let height: Int
    }

    private static func generateSaliencyData(from cgImage: CGImage) async -> SaliencyData? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateAttentionBasedSaliencyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    guard let observation = request.results?.first as? VNSaliencyImageObservation else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let pixelBuffer = observation.pixelBuffer
                    let salWidth = CVPixelBufferGetWidth(pixelBuffer)
                    let salHeight = CVPixelBufferGetHeight(pixelBuffer)
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

                    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

                    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    var values = [Float](repeating: 0, count: salWidth * salHeight)
                    for y in 0..<salHeight {
                        let src = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                        let dstOffset = y * salWidth
                        for x in 0..<salWidth {
                            values[dstOffset + x] = src[x]
                        }
                    }

                    continuation.resume(returning: SaliencyData(values: values, width: salWidth, height: salHeight))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
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
