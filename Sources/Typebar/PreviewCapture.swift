import AppKit
import TypingCore

private final class PreviewCanvas: NSView {
    var background = NSColor.white
    var wallpaper: NSImage?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        background.setFill(); bounds.fill()
        if let wallpaper {
            let ratio = max(bounds.width / wallpaper.size.width, bounds.height / wallpaper.size.height)
            let size = NSSize(width: wallpaper.size.width * ratio, height: wallpaper.size.height * ratio)
            wallpaper.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                      width: size.width, height: size.height), from: .zero,
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

enum PreviewCapture {
    static func desktop() throws {
        guard let screen = NSScreen.screens.first else { throw CocoaError(.fileReadUnknown) }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = PreviewCanvas(frame: NSRect(origin: .zero, size: screen.frame.size))
        canvas.background = NSColor(calibratedWhite: 0.2, alpha: 1)
        if let url = NSWorkspace.shared.desktopImageURL(for: screen) { canvas.wallpaper = NSImage(contentsOf: url) }
        let layout = OverlayLayout.resolve(in: screen.visibleFrame, preferences: OverlayPreferences())
        let frame = NSRect(x: layout.frame.minX - screen.frame.minX,
                           y: screen.frame.maxY - layout.frame.maxY,
                           width: layout.frame.width, height: layout.frame.height)
        let overlay = ShadowBackdropView(frame: frame)
        overlay.configuration = layout.configuration
        overlay.alphaValue = 1
        let view = TypingView(frame: layout.contentFrame, vocabulary: try EnglishWords.load())
        view.bounds = layout.contentBounds
        view.alphaValue = layout.configuration.textOpacity
        view.session = TypingSession(vocabulary: try EnglishWords.load(), seed: 42)
        overlay.addSubview(view)
        canvas.addSubview(overlay)
        window.contentView = canvas
        window.level = .floating
        window.orderFrontRegardless()
        canvas.layoutSubtreeIfNeeded()
        CATransaction.flush()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
        }
        withExtendedLifetime(window) { NSApplication.shared.run() }
    }

    static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vocabulary = try EnglishWords.load()
        for (filename, typing, shade) in [("overlay-ready.png", false, 0.94), ("overlay-typing.png", true, 0.82)] {
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1220, height: 421),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let canvas = PreviewCanvas(frame: NSRect(x: 0, y: 0, width: 1220, height: 421))
            canvas.background = NSColor(calibratedWhite: shade, alpha: 1)
            let padding = ShadowBackdropView.contentPadding
            let overlay = ShadowBackdropView(frame: NSRect(x: 12, y: 12, width: 980 + padding * 2,
                                                            height: ShadowBackdropView.contentHeight + padding * 2))
            overlay.appearance = NSAppearance(named: .darkAqua)
            overlay.alphaValue = 1
            let view = TypingView(frame: overlay.bounds.insetBy(dx: padding, dy: padding), vocabulary: vocabulary)
            view.alphaValue = 0.94
            view.session = TypingSession(vocabulary: vocabulary, seed: 42)
            if typing {
                let now = ProcessInfo.processInfo.systemUptime
                let sample = view.session.words.prefix(6).map(\.target).joined(separator: " ") + " "
                let step = 0.16
                var time = now - Double(sample.count + 2) * step
                for char in sample { view.session.type(char, at: time); time += step }
                for char in view.session.words[view.session.currentIndex].target.prefix(2) {
                    view.session.type(char, at: time); time += step
                }
            }
            overlay.addSubview(view)
            canvas.addSubview(overlay)
            window.contentView = canvas
            window.orderFront(nil)
            canvas.layoutSubtreeIfNeeded()
            canvas.display()
            view.display()
            CATransaction.flush()
            guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent(filename))
            window.orderOut(nil)
        }
    }
}
