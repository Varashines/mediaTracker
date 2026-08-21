import AppKit
import SwiftUI
import Vision

struct DominantPair: Sendable, Equatable {
    let primary: Color
    let secondary: Color
}

/// A cohesive poster palette: primary (theme), secondary (accent), muted (subtle wash).
struct DominantTriple: Sendable, Equatable {
    let primary: Color
    let secondary: Color
    let muted: Color
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

        struct WeightedPixel {
            let r: Int
            let g: Int
            let b: Int
            let weight: Int
        }

        var pixels: [WeightedPixel] = []
        pixels.reserveCapacity(width * height)
        var totalWeight = 0
        var weightedRed = 0
        var weightedGreen = 0
        var weightedBlue = 0

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
                pixels.append(WeightedPixel(r: Int(r), g: Int(g), b: Int(b), weight: copies))
                totalWeight += copies
                weightedRed += Int(r) * copies
                weightedGreen += Int(g) * copies
                weightedBlue += Int(b) * copies
            }
        }

        guard !pixels.isEmpty, totalWeight > 0 else {
            return DominantPair(primary: defaultGray, secondary: secondaryGray)
        }

        // Check if image is essentially grayscale
        let avgR = weightedRed / totalWeight
        let avgG = weightedGreen / totalWeight
        let avgB = weightedBlue / totalWeight
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
            var pixels: [WeightedPixel]
            var weight: Int {
                pixels.reduce(0) { $0 + $1.weight }
            }
        }

        func splitBox(_ box: Box) -> (Box, Box)? {
            guard box.weight > 1 else { return nil }

            var minRed = 255
            var maxRed = 0
            var minGreen = 255
            var maxGreen = 0
            var minBlue = 255
            var maxBlue = 0

            for pixel in box.pixels {
                minRed = min(minRed, pixel.r)
                maxRed = max(maxRed, pixel.r)
                minGreen = min(minGreen, pixel.g)
                maxGreen = max(maxGreen, pixel.g)
                minBlue = min(minBlue, pixel.b)
                maxBlue = max(maxBlue, pixel.b)
            }

            let rRange = maxRed - minRed
            let gRange = maxGreen - minGreen
            let bRange = maxBlue - minBlue

            let channel: Int // 0=R, 1=G, 2=B
            if rRange >= gRange && rRange >= bRange {
                channel = 0
            } else if gRange >= rRange && gRange >= bRange {
                channel = 1
            } else {
                channel = 2
            }

            let sortedPixels = box.pixels.sorted { a, b in
                switch channel {
                case 0: return a.r < b.r
                case 1: return a.g < b.g
                default: return a.b < b.b
                }
            }

            var remainingLeftWeight = box.weight / 2
            var leftPixels: [WeightedPixel] = []
            var rightPixels: [WeightedPixel] = []
            leftPixels.reserveCapacity(sortedPixels.count)
            rightPixels.reserveCapacity(sortedPixels.count)

            for pixel in sortedPixels {
                let leftWeight = min(pixel.weight, remainingLeftWeight)
                if leftWeight > 0 {
                    leftPixels.append(
                        WeightedPixel(r: pixel.r, g: pixel.g, b: pixel.b, weight: leftWeight)
                    )
                    remainingLeftWeight -= leftWeight
                }

                let rightWeight = pixel.weight - leftWeight
                if rightWeight > 0 {
                    rightPixels.append(
                        WeightedPixel(r: pixel.r, g: pixel.g, b: pixel.b, weight: rightWeight)
                    )
                }
            }

            guard !leftPixels.isEmpty, !rightPixels.isEmpty else { return nil }
            return (Box(pixels: leftPixels), Box(pixels: rightPixels))
        }

        var boxes = [Box(pixels: pixels)]
        for _ in 0..<8 {
            guard let idx = boxes.enumerated().max(by: { $0.element.weight < $1.element.weight })?.offset else { break }
            let largest = boxes.remove(at: idx)
            guard let (left, right) = splitBox(largest) else {
                boxes.append(largest)
                break
            }
            boxes.append(left)
            boxes.append(right)
        }

        // Compute centroid and saturation for each box
        struct BoxResult {
            let weight: Int
            let r: Double
            let g: Double
            let b: Double
            let saturation: Double
        }

        let results: [BoxResult] = boxes.map { box in
            var redSum = 0
            var greenSum = 0
            var blueSum = 0
            var boxWeight = 0

            for pixel in box.pixels {
                redSum += pixel.r * pixel.weight
                greenSum += pixel.g * pixel.weight
                blueSum += pixel.b * pixel.weight
                boxWeight += pixel.weight
            }

            let cr = Double(redSum) / Double(boxWeight)
            let cg = Double(greenSum) / Double(boxWeight)
            let cb = Double(blueSum) / Double(boxWeight)
            let maxC = max(cr, cg, cb)
            let minC = min(cr, cg, cb)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            return BoxResult(weight: boxWeight, r: cr, g: cg, b: cb, saturation: sat)
        }

        // Filter: keep clusters with meaningful saturation and lightness
        let filtered = results.filter { box in
            let lightness = (box.r + box.g + box.b) / (255.0 * 3)
            return box.saturation >= 0.08 && lightness >= 0.08
        }

        // If all were filtered out (desaturated image), use the largest box overall
        let candidates = filtered.isEmpty ? results : filtered
        let sorted = candidates.sorted { $0.weight > $1.weight }

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

    private final class SaliencyData {
        let values: [Float]
        let width: Int
        let height: Int

        init(values: [Float], width: Int, height: Int) {
            self.values = values
            self.width = width
            self.height = height
        }
    }

    /// Cache saliency results to avoid repeated Vision neural network inference.
    /// Key is a lightweight hash of image dimensions + corner/center pixel samples.
    nonisolated(unsafe) private static let saliencyCache: NSCache<NSString, SaliencyData> = {
        let cache = NSCache<NSString, SaliencyData>()
        cache.countLimit = 50
        return cache
    }()

    private static func saliencyCacheKey(for cgImage: CGImage) -> NSString {
        let w = cgImage.width
        let h = cgImage.height
        // Sample 9 pixels: 4 corners + 4 edge midpoints + center
        var hasher = Hasher()
        hasher.combine(w)
        hasher.combine(h)
        if let data = cgImage.dataProvider?.data,
           let ptr = CFDataGetBytePtr(data) {
            let bytesPerRow = cgImage.bytesPerRow
            let bpp = cgImage.bitsPerPixel / 8
            let samples: [(Int, Int)] = [
                (0, 0), (w-1, 0), (0, h-1), (w-1, h-1),
                (w/2, 0), (w/2, h-1), (0, h/2), (w-1, h/2),
                (w/2, h/2)
            ]
            for (x, y) in samples {
                let offset = y * bytesPerRow + x * bpp
                if offset + 3 < CFDataGetLength(data) {
                    hasher.combine(ptr[offset])
                    hasher.combine(ptr[offset + 1])
                    hasher.combine(ptr[offset + 2])
                }
            }
        }
        return "saliency_\(hasher.finalize())" as NSString
    }

    private static func generateSaliencyData(from cgImage: CGImage) async -> SaliencyData? {
        let key = saliencyCacheKey(for: cgImage)
        if let cached = saliencyCache.object(forKey: key) {
            return cached
        }

        let result: SaliencyData? = await withCheckedContinuation { continuation in
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

        if let result {
            saliencyCache.setObject(result, forKey: key)
        }
        return result
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

    // MARK: - Theme Palette (saliency-weighted CIELAB k-means)
    //
    // Premium poster palette: saliency-weighted weighted k-means in CIELAB,
    // scored for a vibrant-but-cohesive theme color. Produces primary, secondary,
    // and a derived muted swatch. The existing topTwoColors/dominantColor paths are
    // kept for logo-contrast detection (light/dark signal).

    private struct LabPoint: Sendable {
        var L: Double, a: Double, b: Double
    }
    private struct LabSample {
        var lab: LabPoint
        var weight: Double
    }
    private struct LabCluster {
        var centroid: LabPoint
        var mass: Double = 0
    }

    static func extractThemePalette(from cgImage: CGImage) async -> DominantTriple {
        let fallback = DominantTriple(
            primary: defaultGray,
            secondary: secondaryGray,
            muted: Color(red: 0.22, green: 0.22, blue: 0.22)
        )

        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return fallback }

        // Downscale to cap sample count (one-time, but keep it sane).
        let maxDim: CGFloat = 150
        let scale = min(1, maxDim / CGFloat(max(w, h)))
        let tw = max(1, Int(CGFloat(w) * scale))
        let th = max(1, Int(CGFloat(h) * scale))

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * tw
        var rawData = [UInt8](repeating: 0, count: tw * th * bytesPerPixel)
        guard let ctx = CGContext(
            data: &rawData, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallback }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))

        let saliency = await generateSaliencyData(from: cgImage)
        let salW = saliency?.width ?? 0
        let salH = saliency?.height ?? 0
        let salVals = saliency?.values

        var samples: [LabSample] = []
        samples.reserveCapacity(tw * th)

        for y in 0..<th {
            let row = y * bytesPerRow
            for x in 0..<tw {
                let i = row + x * bytesPerPixel
                let r = rawData[i]
                let g = rawData[i + 1]
                let b = rawData[i + 2]
                let a = rawData[i + 3]
                guard a > 30 else { continue }
                guard max(r, g, b) > 20 else { continue }

                var weight: Double = 0.15
                if let salVals, salW > 0, salH > 0 {
                    let sx = min(x * salW / tw, salW - 1)
                    let sy = min(y * salH / th, salH - 1)
                    weight = max(0.1, Double(salVals[sy * salW + sx]))
                }
                // Border mask: strongly de-emphasize the outer ~4% (bars/borders).
                let bx = Double(min(x, tw - 1 - x)) / Double(tw)
                let by = Double(min(y, th - 1 - y)) / Double(th)
                if bx < 0.04 || by < 0.04 { weight *= 0.05 }

                let lab = sRGBToLab(r: Double(r) / 255.0, g: Double(g) / 255.0, b: Double(b) / 255.0)
                samples.append(LabSample(lab: lab, weight: weight))
            }
        }

        guard samples.count >= 9 else { return fallback }

        // Weighted mean lightness & chroma for grayscale detection.
        var totalW = 0.0
        var lum = 0.0
        var chromaAcc = 0.0
        for s in samples {
            totalW += s.weight
            lum += s.lab.L * s.weight
            chromaAcc += (s.lab.a * s.lab.a + s.lab.b * s.lab.b).squareRoot() * s.weight
        }
        guard totalW > 0 else { return fallback }
        lum /= totalW
        let avgChroma = chromaAcc / totalW

        if avgChroma < 6 {
            let gray = clamp(lum / 100.0, 0, 1)
            return DominantTriple(
                primary: Color(red: gray, green: gray, blue: gray),
                secondary: Color(red: max(0, gray - 0.1), green: max(0, gray - 0.1), blue: max(0, gray - 0.1)),
                muted: Color(red: max(0, gray - 0.18), green: max(0, gray - 0.18), blue: max(0, gray - 0.18))
            )
        }

        let clusters = weightedKMeans(samples: samples, k: 6, iterations: 20)

        // Score each cluster for the theme color.
        var scored: [(index: Int, cluster: LabCluster, score: Double)] = []
        for (i, cluster) in clusters.enumerated() {
            let chroma = (cluster.centroid.a * cluster.centroid.a + cluster.centroid.b * cluster.centroid.b).squareRoot()
            var chromaScore = min(chroma / 45.0, 1.0)
            if chroma > 60 {
                // Soft penalty for very saturated colors — never zeroes them out
                // (a solid red poster should still resolve to red).
                chromaScore *= max(0.45, 1 - (chroma - 60) / 140)
            }
            let lightnessScore = exp(-pow((cluster.centroid.L - 52) / 22.0, 2))
            scored.append((i, cluster, cluster.mass * chromaScore * lightnessScore))
        }

        scored.sort { $0.score > $1.score }
        guard let primary = scored.first, primary.score > 0 else { return fallback }

        // Secondary: highest-hue-difference cluster from primary with meaningful mass.
        let primaryHue = labHue(primary.cluster.centroid)
        var secondary = primary.cluster
        var bestDiff = -1.0
        for (i, cluster) in scored.enumerated() where i > 0 && cluster.cluster.mass > primary.cluster.mass * 0.15 {
            let diff = hueDistance(labHue(cluster.cluster.centroid), primaryHue)
            if diff > bestDiff {
                bestDiff = diff
                secondary = cluster.cluster
            }
        }

        let primaryColor = labToSRGBColor(primary.cluster.centroid)
        let secondaryColor = labToSRGBColor(secondary.centroid)
        let mutedColor = labToSRGBColor(derivedMuted(from: primary.cluster.centroid))

        return DominantTriple(primary: primaryColor, secondary: secondaryColor, muted: mutedColor)
    }

    // MARK: - CIELAB helpers

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    private static func sRGBToLab(r: Double, g: Double, b: Double) -> LabPoint {
        func lin(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = lin(r), gl = lin(g), bl = lin(b)
        let x = 0.4124 * rl + 0.3576 * gl + 0.1805 * bl
        let y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        let z = 0.0193 * rl + 0.1192 * gl + 0.9505 * bl

        func f(_ t: Double) -> Double {
            let e = 216.0 / 24389.0
            let k = 24389.0 / 27.0
            return t > e ? pow(t, 1.0 / 3.0) : (k * t + 16.0) / 116.0
        }
        let xn = 0.95047, yn = 1.0, zn = 1.08883
        let fx = f(x / xn), fy = f(y / yn), fz = f(z / zn)
        return LabPoint(L: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    private static func labToSRGBColor(_ p: LabPoint) -> Color {
        func fInv(_ t: Double) -> Double {
            let e = 216.0 / 24389.0
            let k = 24389.0 / 27.0
            return t * t * t > e ? t * t * t : (116 * t - 16) / k
        }
        let xn = 0.95047, yn = 1.0, zn = 1.08883
        let fy = (p.L + 16) / 116
        let fx = fy + p.a / 500
        let fz = fy - p.b / 200
        let x = xn * fInv(fx)
        let y = yn * fInv(fy)
        let z = zn * fInv(fz)

        func gamma(_ c: Double) -> Double {
            let lin = 3.2406 * x + -1.5372 * y + -0.4986 * z
            let ling = -0.9689 * x + 1.8758 * y + 0.0415 * z
            let linb = 0.0557 * x + -0.2040 * y + 1.0570 * z
            let v = c == x ? lin : (c == y ? ling : linb)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        let r = clamp(gamma(x), 0, 1)
        let g = clamp(gamma(y), 0, 1)
        let b = clamp(gamma(z), 0, 1)
        return Color(red: r, green: g, blue: b)
    }

    private static func labHue(_ p: LabPoint) -> Double {
        var h = atan2(p.b, p.a) * 180 / .pi
        if h < 0 { h += 360 }
        return h
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 360 - d)
    }

    /// Chroma-reduced, mid-lightness blend of the primary → a harmonious muted wash.
    private static func derivedMuted(from p: LabPoint) -> LabPoint {
        let chroma = (p.a * p.a + p.b * p.b).squareRoot()
        let factor = chroma > 0 ? (chroma * 0.38) / chroma : 0
        return LabPoint(
            L: clamp(p.L * 0.55 + 52 * 0.45, 38, 64),
            a: p.a * factor,
            b: p.b * factor
        )
    }

    private static func weightedKMeans(samples: [LabSample], k: Int, iterations: Int) -> [LabCluster] {
        func dist(_ a: LabPoint, _ b: LabPoint) -> Double {
            let dl = a.L - b.L, da = a.a - b.a, db = a.b - b.b
            return (dl * dl + da * da + db * db).squareRoot()
        }

        // Deterministic k-means++ seeding.
        var centroids: [LabPoint] = []
        centroids.append(samples[samples.count / 2].lab)
        var seed = 7
        while centroids.count < k {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff
            var distSum = 0.0
            var dists = [Double](repeating: 0, count: samples.count)
            for (i, s) in samples.enumerated() {
                let d = centroids.map { dist(s.lab, $0) }.min() ?? 0
                dists[i] = d * d
                distSum += dists[i]
            }
            if distSum <= 0 { break }
            let r = (Double(seed % 1000) / 1000.0) * distSum
            var acc = 0.0
            var pick = 0
            for (i, d) in dists.enumerated() {
                acc += d
                if acc >= r { pick = i; break }
            }
            centroids.append(samples[pick].lab)
        }

        var assignment = [Int](repeating: 0, count: samples.count)
        for _ in 0..<iterations {
            for (i, s) in samples.enumerated() {
                var best = 0
                var bestD = Double.greatestFiniteMagnitude
                for (ci, c) in centroids.enumerated() {
                    let d = dist(s.lab, c)
                    if d < bestD { bestD = d; best = ci }
                }
                assignment[i] = best
            }
            var sums = [LabPoint](repeating: LabPoint(L: 0, a: 0, b: 0), count: k)
            var wsums = [Double](repeating: 0, count: k)
            for (i, s) in samples.enumerated() {
                let ci = assignment[i]
                let wt = s.weight
                sums[ci].L += s.lab.L * wt
                sums[ci].a += s.lab.a * wt
                sums[ci].b += s.lab.b * wt
                wsums[ci] += wt
            }
            for ci in 0..<k where wsums[ci] > 0 {
                centroids[ci] = LabPoint(L: sums[ci].L / wsums[ci], a: sums[ci].a / wsums[ci], b: sums[ci].b / wsums[ci])
            }
        }

        // Final mass per cluster.
        var mass = [Double](repeating: 0, count: k)
        for (i, s) in samples.enumerated() {
            mass[assignment[i]] += s.weight
        }
        return centroids.enumerated().map { LabCluster(centroid: $0.element, mass: mass[$0.offset]) }
    }
}
