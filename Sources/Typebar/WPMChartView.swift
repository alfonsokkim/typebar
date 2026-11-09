import AppKit
import TypingCore

final class WPMChartView: NSView {
    var samples: [WPMSample] = [] {
        didSet {
            guard oldValue != samples else { return }
            needsDisplay = true
            let latest = samples.last?.wpm ?? 0
            setAccessibilityValue("\(samples.count) recent completed words. Latest: \(latest) words per minute.")
        }
    }
    var palette = ThemePalette.shadow { didSet { if oldValue != palette { needsDisplay = true } } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("WPM history")
        setAccessibilityValue("No completed words yet.")
        setAccessibilityHelp("Speed recorded after each completed word. Resets with the WPM counter after five seconds idle.")
    }
    required init?(coder: NSCoder) { return nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func upperBound(for samples: [WPMSample]) -> Int {
        let peak = samples.map(\.wpm).max() ?? 0
        return max(20, Int(ceil(Double(peak) / 20)) * 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 50, bounds.height >= 20 else { return }
        let ceiling = Self.upperBound(for: samples)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
        let labelWidth = (String(ceiling) as NSString).size(withAttributes: [.font: font]).width
        let plot = bounds.insetBy(dx: 0, dy: 5)
        let left = bounds.minX + max(22, labelWidth + 8)
        let right = bounds.maxX - 3
        for value in [ceiling, ceiling / 2, 0] {
            let label = String(value) as NSString
            let size = label.size(withAttributes: [.font: font])
            let y = plot.maxY - Double(value) / Double(ceiling) * plot.height
            label.draw(at: NSPoint(x: left - 7 - size.width, y: y - size.height / 2), withAttributes: [
                .font: font,
                .foregroundColor: NSColor(themeHex: palette.muted).withAlphaComponent(0.8)
            ])
        }
        guard !samples.isEmpty else { return }
        let points = samples.enumerated().map { index, sample in
            NSPoint(x: left + Double(index) / Double(max(1, samples.count - 1)) * (right - left),
                    y: plot.maxY - Double(sample.wpm) / Double(ceiling) * plot.height)
        }
        guard let first = points.first, let latest = points.last else { return }
        NSColor(themeHex: palette.accent).setStroke()
        let line = NSBezierPath()
        line.move(to: first)
        for point in points.dropFirst() { line.line(to: point) }
        line.lineWidth = 1.5
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.stroke()
        NSColor(themeHex: palette.accent).setFill()
        NSBezierPath(ovalIn: NSRect(x: latest.x - 1.8, y: latest.y - 1.8, width: 3.6, height: 3.6)).fill()
    }
}
