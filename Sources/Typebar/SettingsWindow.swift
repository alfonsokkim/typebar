import AppKit
import SwiftUI
import TypingCore

final class SettingsWindow: NSWindowController {
    init(settings: OverlaySettings, showOverlay: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 730),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Typebar Settings"
        window.minSize = NSSize(width: 520, height: 580)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsForm(settings: settings, preview: { [weak window] in
            window?.orderOut(nil)
            showOverlay()
        }))
        window.center()
    }
    required init?(coder: NSCoder) { return nil }
}

private struct SettingsForm: View {
    @Bindable var settings: OverlaySettings
    let preview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Theme") {
                    Picker("Colours", selection: $settings.value.themeID) {
                        ForEach(settings.presets, id: \.id) { Text($0.name).tag($0.id) }
                        Text("Custom").tag("custom")
                    }
                    HStack(spacing: 10) {
                        Text("the quick brown fox").font(.system(size: 18, design: .monospaced))
                            .foregroundStyle(Color(nsColor: NSColor(themeHex: settings.palette.text)))
                        Text("75 wpm").monospacedDigit().foregroundStyle(Color(nsColor: NSColor(themeHex: settings.palette.accent)))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: NSColor(themeHex: settings.palette.background)))
                    .clipShape(RoundedRectangle(cornerRadius: min(16, settings.value.cornerRadius)))
                    if settings.value.themeID == "custom" {
                        ColorPicker("Background", selection: colour(\.background), supportsOpacity: false)
                        ColorPicker("Typed text", selection: colour(\.text), supportsOpacity: false)
                        ColorPicker("Untyped text", selection: colour(\.muted), supportsOpacity: false)
                        ColorPicker("Caret and WPM", selection: colour(\.accent), supportsOpacity: false)
                        ColorPicker("Mistakes", selection: colour(\.error), supportsOpacity: false)
                    }
                }
                Section("Appearance") {
                    slider("Size", $settings.value.scale, in: 0.6...1.4, percentage: true)
                    slider("Corner radius", $settings.value.cornerRadius, in: 0...120)
                    slider("Edge blur", $settings.value.blurRadius, in: 0...60)
                    Text("Set edge blur to 0 for a hard edge, or increase it for a softer shadow.")
                        .font(.caption).foregroundStyle(.secondary)
                    slider("Background opacity", $settings.value.backgroundOpacity, in: 0.2...1, percentage: true)
                    slider("Overall opacity", $settings.value.contentOpacity, in: 0.4...1, percentage: true)
                }
                Section("Position on the display under your pointer") {
                    Picker("Placement", selection: placement) {
                        ForEach(Array(Self.placements.enumerated()), id: \.offset) { index, item in Text(item.0).tag(index) }
                        Text("Custom position").tag(-1)
                    }
                    slider("Left to right", $settings.value.horizontalPosition, in: 0...1, percentage: true)
                    slider("Top to bottom", $settings.value.verticalPosition, in: 0...1, percentage: true)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Reset Defaults") { settings.value = OverlayPreferences() }
                    .accessibilityLabel("Reset Defaults")
                Spacer()
                Button("Show Overlay", action: preview).keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Show Overlay")
            }
            .padding(16)
        }
    }

    private static let placements: [(String, Double, Double)] = [
        ("Top left", 0, 0), ("Top centre", 0.5, 0), ("Top right", 1, 0),
        ("Centre left", 0, 0.5), ("Centre", 0.5, 0.5), ("Centre right", 1, 0.5),
        ("Bottom left", 0, 1), ("Bottom centre", 0.5, 1), ("Bottom right", 1, 1)
    ]

    private var placement: Binding<Int> {
        Binding(get: {
            Self.placements.firstIndex { abs($0.1 - settings.value.horizontalPosition) < 0.001
                && abs($0.2 - settings.value.verticalPosition) < 0.001 } ?? -1
        }, set: { index in
            guard Self.placements.indices.contains(index) else { return }
            var value = settings.value
            value.horizontalPosition = Self.placements[index].1
            value.verticalPosition = Self.placements[index].2
            settings.value = value
        })
    }

    private func colour(_ key: WritableKeyPath<ThemePalette, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(themeHex: settings.value.customTheme[keyPath: key])) }, set: { color in
            var value = settings.value
            value.customTheme[keyPath: key] = NSColor(color).themeHex
            settings.value = value
        })
    }

    private func slider(_ title: String, _ value: Binding<Double>, in range: ClosedRange<Double>, percentage: Bool = false) -> some View {
        HStack {
            Text(title).frame(width: 132, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text("\(Int((value.wrappedValue * (percentage ? 100 : 1)).rounded()))\(percentage ? "%" : " pt")")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
        }
    }
}
