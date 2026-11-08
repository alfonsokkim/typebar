import AppKit
import Observation
import TypingCore

extension NSColor {
    convenience init(themeHex: String) {
        let hex = themeHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255, alpha: 1)
    }

    var themeHex: String {
        let rgb = usingColorSpace(.sRGB) ?? .white
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }
}

@Observable
final class OverlaySettings {
    let presets: [ThemePalette]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?
    var value: OverlayPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(value.validated()) { defaults.set(data, forKey: "overlayPreferences") }
            onChange?()
        }
    }

    init(presets: [ThemePalette], defaults: UserDefaults = .standard) {
        self.presets = presets
        self.defaults = defaults
        var loaded = defaults.data(forKey: "overlayPreferences")
            .flatMap { try? JSONDecoder().decode(OverlayPreferences.self, from: $0) } ?? OverlayPreferences()
        loaded = loaded.validated()
        if loaded.themeID != "custom", !presets.contains(where: { $0.id == loaded.themeID }) { loaded.themeID = "shadow" }
        value = loaded
    }

    var palette: ThemePalette {
        let prefs = value.validated()
        return (prefs.themeID == "custom" ? prefs.customTheme : presets.first { $0.id == prefs.themeID } ?? .shadow).validated()
    }
}

struct OverlayLayout {
    let frame: CGRect
    let contentFrame: CGRect
    let contentBounds: CGRect
    let configuration: OverlayPreferences

    static func resolve(in screen: CGRect, preferences: OverlayPreferences) -> Self {
        var prefs = preferences.validated()
        let available = screen.insetBy(dx: 12, dy: 12)
        let blurSpace = min((available.width - 490) / 2 - 38, (available.height - 90.5) / 2 - 38)
        prefs.blurRadius = min(prefs.blurRadius, max(0, blurSpace / 3.6))
        let padding = ShadowBackdropView.contentPadding(for: prefs)
        let scale = min(prefs.scale, (available.width - padding * 2) / 980,
                        (available.height - padding * 2) / ShadowBackdropView.contentHeight)
        let width = 980 * scale + padding * 2
        let height = ShadowBackdropView.contentHeight * scale + padding * 2
        let frame = CGRect(x: available.minX + (available.width - width) * prefs.horizontalPosition,
                           y: available.maxY - height - (available.height - height) * prefs.verticalPosition,
                           width: width, height: height)
        let content = CGRect(x: padding, y: padding, width: 980 * scale,
                             height: ShadowBackdropView.contentHeight * scale)
        return Self(frame: frame, contentFrame: content,
                    contentBounds: CGRect(x: 0, y: 0, width: 980, height: ShadowBackdropView.contentHeight),
                    configuration: prefs)
    }
}
