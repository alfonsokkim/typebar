import AppKit
import Testing
import TypingCore
@testable import Typebar

@MainActor
struct SettingsTests {
    @Test func wideGamutCustomColoursStayValidAfterConversion() {
        let colour = NSColor(colorSpace: .extendedSRGB, components: [1.2, -0.1, 0.5, 1], count: 4)
        #expect(colour.themeHex == "#FF0080")
    }

    @Test func layoutsStayWithinDisplaysAtAllAnchorsAndSizes() {
        for screen in [CGRect(x: 0, y: 0, width: 800, height: 600),
                       CGRect(x: -1920, y: 350, width: 1920, height: 1055)] {
            for scale in [0.6, 1.0, 1.4] {
                for blur in [0.0, 20, 60] {
                    for x in [0.0, 0.5, 1] {
                        for y in [0.0, 0.5, 1] {
                            var prefs = OverlayPreferences()
                            prefs.scale = scale; prefs.blurRadius = blur
                            prefs.horizontalPosition = x; prefs.verticalPosition = y
                            let result = OverlayLayout.resolve(in: screen, preferences: prefs)
                            #expect(screen.contains(result.frame))
                            #expect(result.contentFrame.width > 0 && result.contentFrame.height > 0)
                            #expect(CGRect(origin: .zero, size: result.frame.size).contains(result.contentFrame))
                        }
                    }
                }
            }
        }
    }

    @Test func preferencesPersistAndMalformedValuesRecover() throws {
        let suite = "TypebarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(presets: try ThemePalette.presets(), defaults: defaults)
        settings.value.themeID = "custom"
        settings.value.customTheme.accent = "#123456"
        settings.value.blurRadius = 0
        settings.value.horizontalPosition = 1
        let reloaded = OverlaySettings(presets: try ThemePalette.presets(), defaults: defaults)
        #expect(reloaded.value == settings.value)
        #expect(reloaded.palette.accent == "#123456")
        defaults.set(Data("invalid json".utf8), forKey: "overlayPreferences")
        #expect(OverlaySettings(presets: [], defaults: defaults).value == OverlayPreferences())
    }

    @Test func zeroBlurCreatesAHardEdgeAndCornerRadiusChangesItsShape() throws {
        func alpha(_ radius: Double, _ x: Int, _ y: Int) throws -> UInt8 {
            var prefs = OverlayPreferences()
            prefs.blurRadius = 0; prefs.cornerRadius = radius; prefs.backgroundOpacity = 1
            var palette = ThemePalette.shadow; palette.background = "#FF0000"
            let image = try #require(ShadowBackdropView.backdrop(size: CGSize(width: 300, height: 200),
                scale: 1, configuration: prefs, palette: palette))
            var bytes = [UInt8](repeating: 0, count: 300 * 200 * 4)
            let context = try #require(CGContext(data: &bytes, width: 300, height: 200, bitsPerComponent: 8,
                bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 300, height: 200))
            #expect(bytes[(100 * 300 + 150) * 4] == 255)
            return bytes[(y * 300 + x) * 4 + 3]
        }
        #expect(try alpha(0, 1, 100) == 0)
        #expect(try alpha(0, 3, 100) == 255)
        #expect(try alpha(0, 4, 4) == 255)
        #expect(try alpha(80, 4, 4) == 0)
    }
}
