import AppKit
import CoreGraphics

let iconSize: CGFloat = 1024
let image = NSImage(size: NSSize(width: iconSize, height: iconSize))

image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// 1. Draw Background Gradient
let colors = [
    NSColor(red: 0.36, green: 0.21, blue: 0.89, alpha: 1.0).cgColor, // Deep Purple
    NSColor(red: 0.19, green: 0.55, blue: 0.91, alpha: 1.0).cgColor  // Bright Blue
] as CFArray
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!

let path = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 180, yRadius: 180)
context.saveGState()
path.addClip()
context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
context.restoreGState()

// 2. Draw Symbols (Simplified Media Icons)
context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
context.setLineWidth(30)
context.setLineCap(.round)

// TV/Screen shape
let screenPath = NSBezierPath()
screenPath.appendRoundedRect(NSRect(x: 312, y: 450, width: 400, height: 280), xRadius: 40, yRadius: 40)
NSColor.white.withAlphaComponent(0.9).setStroke()
screenPath.stroke()

// Play triangle
let playPath = NSBezierPath()
playPath.move(to: NSPoint(x: 480, y: 540))
playPath.line(to: NSPoint(x: 480, y: 640))
playPath.line(to: NSPoint(x: 560, y: 590))
playPath.close()
NSColor.white.withAlphaComponent(0.9).setFill()
playPath.fill()

// Book shape
let bookPath = NSBezierPath()
bookPath.appendRoundedRect(NSRect(x: 312, y: 280, width: 300, height: 120), xRadius: 20, yRadius: 20)
NSColor.white.withAlphaComponent(0.7).setStroke()
bookPath.stroke()

image.unlockFocus()

// 3. Save to Iconset
let fileManager = FileManager.default
let iconsetPath = "AppIcon.iconset"
try? fileManager.removeItem(atPath: iconsetPath)
try? fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()
    
    if let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
        let png = bitmap.representation(using: .png, properties: [:])
        try? png?.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size).png"))
        // Double resolution for retina
        try? png?.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size/2)x\(size/2)@2x.png"))
    }
}

print("✅ Generated icon assets.")
