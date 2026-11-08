import AppKit
import CoreImage
import TypingCore

final class ShadowBackdropView: NSView {
    static let edgePadding: CGFloat = 72
    static let contentPadding: CGFloat = edgePadding + 36
    static let contentHeight: CGFloat = 181
    static func fadePadding(for configuration: OverlayPreferences) -> CGFloat { max(2, configuration.blurRadius * 3.6) }
    static func contentPadding(for configuration: OverlayPreferences) -> CGFloat { fadePadding(for: configuration) + 36 }
    var configuration = OverlayPreferences() { didSet { if oldValue != configuration { invalidateBackdrop() } } }
    var palette = ThemePalette.shadow { didSet { if oldValue != palette { invalidateBackdrop() } } }
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let shadowLayer = CALayer()
    private var renderedSize = CGSize.zero
    private var renderedScale: CGFloat = 0
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shadowLayer.isOpaque = false
        layer?.addSublayer(shadowLayer)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        guard renderedSize != bounds.size || renderedScale != scale else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.contentsScale = scale
        shadowLayer.contents = Self.backdrop(size: bounds.size, scale: scale, configuration: configuration, palette: palette)
        CATransaction.commit()
        renderedSize = bounds.size
        renderedScale = scale
    }

    private func invalidateBackdrop() { renderedSize = .zero; needsLayout = true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderedScale = 0
        needsLayout = true
    }

    static func backdrop(size: CGSize, scale: CGFloat, configuration: OverlayPreferences = OverlayPreferences(),
                         palette: ThemePalette = .shadow) -> CGImage? {
        let configuration = configuration.validated()
        let extent = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
        let core = extent.insetBy(dx: fadePadding(for: configuration) * scale, dy: fadePadding(for: configuration) * scale)
        let colour = NSColor(themeHex: palette.validated().background)
        guard let shape = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: core),
            "inputRadius": min(configuration.cornerRadius * scale, min(core.width, core.height) / 2),
            "inputColor": CIColor(red: colour.redComponent, green: colour.greenComponent,
                                   blue: colour.blueComponent, alpha: configuration.backgroundOpacity)
        ])?.outputImage else { return nil }
        let diffuse = configuration.blurRadius == 0 ? shape
            : shape.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: configuration.blurRadius * scale])
        return context.createCGImage(diffuse, from: extent)
    }
}
