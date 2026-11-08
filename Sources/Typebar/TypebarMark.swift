import AppKit

enum TypebarMark {
    static func draw(in bounds: NSRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.minX, yBy: bounds.minY)
        transform.scale(by: min(bounds.width, bounds.height) / 18)
        transform.concat()
        ("a" as NSString).draw(at: NSPoint(x: 0.5, y: -0.5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: color
        ])
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 13.5, y: 2, width: 1.6, height: 14), xRadius: 0.8, yRadius: 0.8).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: 18, height: 18), color: .black)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Typebar"
        return image
    }
}
