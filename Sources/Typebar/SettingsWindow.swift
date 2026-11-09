import AppKit
import SwiftUI
import TypingCore

final class SettingsWindow: NSWindowController {
    init(settings: OverlaySettings) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Typebar Settings"
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsForm(settings: settings, done: { [weak window] in
            window?.performClose(nil)
        }))
    }
    required init?(coder: NSCoder) { return nil }

    static func initialFrame(in visibleFrame: CGRect, previewFrame: CGRect) -> CGRect {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        let spaceBelowPreview = previewFrame.minY - available.minY - 12
        let height = min(528, max(360, spaceBelowPreview), available.height)
        let size = CGSize(width: min(580, available.width), height: height)
        let centredY = (visibleFrame.minY + previewFrame.minY - height) / 2
        let y = min(available.maxY - height, max(available.minY, centredY))
        return CGRect(x: available.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    func positionBelowPreview(on screen: NSScreen, previewFrame: CGRect) {
        window?.setFrame(Self.initialFrame(in: screen.visibleFrame, previewFrame: previewFrame), display: false)
    }
}

private struct SettingsForm: View {
    @Bindable var settings: OverlaySettings
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Shortcut") {
                    HStack {
                        Text("Show / hide overlay")
                        Spacer()
                        ShortcutRecorder(settings: settings).frame(width: 190, height: 28)
                        Button("Reset") { settings.isRecordingShortcut = false; settings.changeShortcut(.default) }
                    }
                    Text("Click the shortcut, then press modifiers alone or a key combination. Escape cancels.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = settings.shortcutError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Theme") {
                    Picker("Colours", selection: $settings.value.themeID) {
                        ForEach(settings.presets, id: \.id) { Text($0.name).tag($0.id) }
                        Text("Custom").tag("custom")
                    }
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
                    slider("Background opacity", $settings.value.backgroundOpacity, in: 0...1, percentage: true)
                    slider("Text opacity", $settings.value.textOpacity, in: 0...1, percentage: true)
                }
                Section("Position on this display") {
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
                Button("Reset Defaults") {
                    settings.isRecordingShortcut = false
                    settings.shortcutError = nil
                    settings.value = OverlayPreferences()
                }
                    .accessibilityLabel("Reset Defaults")
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Done")
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
