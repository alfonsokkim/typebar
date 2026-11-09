import AppKit
import SwiftUI
import TypingCore

extension ShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags, includeFunction: Bool = true) {
        self = []
        for (native, flag) in [(NSEvent.ModifierFlags.control, Self.control), (.option, .option),
                                (.command, .command), (.shift, .shift)] {
            if eventFlags.contains(native) { insert(flag) }
        }
        if includeFunction, eventFlags.contains(.function) { insert(.function) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let settings: OverlaySettings

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = settings.value.shortcut
        button.onRecording = { settings.isRecordingShortcut = $0 }
        button.onRecord = { settings.changeShortcut($0) }
        button.onError = { settings.shortcutError = $0 }
        if !settings.isRecordingShortcut { button.stopRecording() }
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.stopRecording() }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut = OverlayShortcut.default
    var onRecording: ((Bool) -> Void)?
    var onRecord: ((OverlayShortcut) -> Void)?
    var onError: ((String?) -> Void)?
    private var monitor: Any?
    private var modifiers: ShortcutModifiers = []
    private var pending: OverlayShortcut?
    private var keyReleased = false
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        toolTip = "Click, then press your shortcut. Escape cancels."
        setAccessibilityLabel("Record overlay shortcut")
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: nil)
    }
    required init?(coder: NSCoder) { return nil }

    func refreshTitle() { title = monitor == nil ? shortcut.displayName : (pending == nil ? "Press shortcut…" : "Release to save…") }

    @objc private func beginRecording() {
        if monitor != nil { stopRecording(); return }
        window?.makeFirstResponder(self)
        modifiers = []
        pending = nil
        keyReleased = false
        onError?(nil)
        onRecording?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isKeyWindow, event.window === window else { return false }
                self.capture(event)
                return true
            }
            return consumed ? nil : event
        }
        refreshTitle()
    }

    func capture(_ event: NSEvent) {
        let flags = ShortcutModifiers(eventFlags: event.modifierFlags, includeFunction: event.type == .flagsChanged)
        if event.type == .keyDown {
            if event.keyCode == 53, flags.isEmpty { stopRecording(); return }
            guard pending == nil, !event.isARepeat else { return }
            let candidate = OverlayShortcut(modifiers: ShortcutModifiers(eventFlags: event.modifierFlags, includeFunction: false),
                                            keyCode: event.keyCode, keyLabel: Self.label(for: event))
            guard candidate.isValid else {
                onError?("Include Control, Option, or Command, or use a function key.")
                modifiers = []
                return
            }
            pending = candidate
            refreshTitle()
        } else if event.type == .keyUp {
            if event.keyCode == pending?.keyCode { keyReleased = true }
            if flags.isEmpty, keyReleased { finishRecording() }
        } else {
            if !flags.isEmpty { modifiers.formUnion(flags) }
            else if pending != nil {
                if keyReleased { finishRecording() }
            } else if !modifiers.isEmpty {
                let candidate = OverlayShortcut(modifiers: modifiers)
                if candidate.isValid { pending = candidate; finishRecording() }
                else { modifiers = []; onError?("Use Control, Option, or Command. Fn and Globe are not supported.") }
            }
        }
    }

    private func finishRecording() {
        guard let candidate = pending else { return }
        stopRecording()
        onRecord?(candidate)
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        let wasRecording = monitor != nil
        monitor = nil
        modifiers = []
        pending = nil
        keyReleased = false
        if wasRecording { onRecording?(false) }
        refreshTitle()
    }

    override func resignFirstResponder() -> Bool { stopRecording(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
    @objc private func windowResignedKey(_ notification: Notification) {
        if notification.object as? NSWindow === window { stopRecording() }
    }

    private static func label(for event: NSEvent) -> String {
        let labels: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        if let label = labels[event.keyCode] { return label }
        let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        if let index = functionKeys.firstIndex(of: event.keyCode) { return "F\(index + 1)" }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}
