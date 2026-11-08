import AppKit

@main
struct MakeIcon {
    @MainActor
    static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                               ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                               ("icon_256x256", 256), ("icon_256x256@2x", 512),
                               ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0),
                  let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw CocoaError(.fileWriteUnknown)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            graphics.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            let transform = NSAffineTransform()
            transform.scale(by: CGFloat(pixels) / 512)
            transform.concat()
            NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 26, y: 26, width: 460, height: 460), xRadius: 102, yRadius: 102).fill()
            TypebarMark.draw(in: NSRect(x: 117, y: 117, width: 278, height: 278),
                             color: NSColor(calibratedRed: 0.94, green: 0.79, blue: 0.39, alpha: 1))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: destination.appendingPathComponent(name + ".png"))
        }
    }
}
