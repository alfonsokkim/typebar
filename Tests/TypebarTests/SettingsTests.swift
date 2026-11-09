import AppKit
import Testing
import TypingCore
@testable import Typebar

@MainActor
struct SettingsTests {
    @Test func editingSettingsKeepsALivePreviewAndPreservesPractice() throws {
        let application = NSApplication.shared
        let suite = "TypebarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(presets: try ThemePalette.presets(), defaults: defaults)
        let delegate = AppDelegate(vocabulary: ["hello"], settings: settings)
        delegate.perform(NSSelectorFromString("toggleOverlay"))
        let panel = try #require(application.windows.compactMap { $0 as? OverlayPanel }.first { $0.isVisible })
        let input = try #require(panel.contentView?.subviews.first { $0 is TypingView } as? TypingView)
        input.insertText("he", replacementRange: NSRange(location: NSNotFound, length: 0))
        delegate.perform(NSSelectorFromString("showSettings"))
        let window = try #require(application.windows.first { $0.title == "Typebar Settings" && $0.isVisible })
        defer {
            if window.isVisible { window.performClose(nil) }
            panel.orderOut(nil)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        #expect(panel.isVisible && window.isVisible)
        #expect(panel.ignoresMouseEvents && !panel.canBecomeKey)
        #expect(window.canBecomeKey && window.firstResponder !== input)
        delegate.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(panel.isVisible)
        #expect(panel.level == .normal)
        let now = ProcessInfo.processInfo.systemUptime
        #expect(input.session.elapsed(at: now) == input.session.elapsed(at: now + 10))
        let previousFrame = panel.frame
        settings.value.scale = 0.6
        settings.value.blurRadius = 0
        settings.value.themeID = "dracula"
        #expect(panel.frame.width < previousFrame.width)
        #expect(panel.isVisible && window.isVisible)
        #expect(!panel.canBecomeKey && window.firstResponder !== input)
        #expect(input.palette.id == "dracula")
        #expect(input.session.words[input.session.currentIndex].input == "he")
        let changedFrame = panel.frame
        delegate.perform(NSSelectorFromString("showSettings"))
        #expect(panel.frame == changedFrame)
        window.performClose(nil)
        #expect(!window.isVisible && panel.isVisible)
        #expect(!panel.ignoresMouseEvents && panel.canBecomeKey)
        #expect(panel.firstResponder === input)
        delegate.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        #expect(panel.isVisible)
        #expect(panel.level == .floating)
        #expect(input.session.words[input.session.currentIndex].input == "he")
        delegate.perform(NSSelectorFromString("toggleOverlay"))
        #expect(!panel.isVisible)
        delegate.perform(NSSelectorFromString("showSettings"))
        #expect(panel.isVisible && window.isVisible)
        #expect(panel.ignoresMouseEvents && window.canBecomeKey)
    }

    @Test func settingsAreCentredBetweenThePreviewAndDisplayBottom() {
        for display in [CGRect(x: 0, y: 35, width: 1800, height: 1134),
                        CGRect(x: -1440, y: 100, width: 1440, height: 875)] {
            let preview = OverlayLayout.resolve(in: display, preferences: OverlayPreferences()).frame
            let settings = SettingsWindow.initialFrame(in: display, previewFrame: preview)
            #expect(display.contains(settings))
            #expect(settings.midY == (display.minY + preview.minY) / 2)
            #expect(settings.midX == display.midX)
            #expect(settings.maxY <= preview.minY - 12)
        }
    }

    @Test func previewCannotTakeKeyboardFocusWhileSettingsAreBeingEdited() {
        _ = NSApplication.shared
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        #expect(panel.canBecomeKey)
        panel.ignoresMouseEvents = true
        #expect(!panel.canBecomeKey)
        panel.ignoresMouseEvents = false
        #expect(panel.canBecomeKey)
    }

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
