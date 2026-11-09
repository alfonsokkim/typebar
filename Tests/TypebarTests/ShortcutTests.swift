import AppKit
import Carbon
import Testing
import TypingCore
@testable import Typebar

@MainActor
struct ShortcutTests {
    private func event(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = [], key: UInt16 = 0,
                       character: String = "") throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
            isARepeat: false, keyCode: key))
    }

    @Test func recorderWaitsForReleaseAndCancelsWithoutSaving() throws {
        _ = NSApplication.shared
        let button = ShortcutRecorderButton()
        var captured: [OverlayShortcut] = []
        var recording = false
        button.onRecord = { captured.append($0) }
        button.onRecording = { recording = $0 }
        defer { button.stopRecording() }
        button.performClick(nil)
        #expect(recording)
        button.capture(try event(.flagsChanged, flags: [.control, .option]))
        button.capture(try event(.keyDown, flags: [.control, .option], key: 40, character: "k"))
        button.capture(try event(.keyUp, flags: [.control, .option], key: 40, character: "k"))
        #expect(captured.isEmpty)
        button.capture(try event(.flagsChanged))
        #expect(!recording && captured == [OverlayShortcut(modifiers: [.control, .option], keyCode: 40, keyLabel: "K")])
        button.performClick(nil)
        button.capture(try event(.keyDown, key: 53))
        #expect(!recording && captured.count == 1)
        button.performClick(nil)
        button.capture(try event(.flagsChanged, flags: [.control, .option, .command]))
        button.capture(try event(.flagsChanged))
        #expect(captured.last == .default && !recording)
    }

    @Test func functionKeysRecordWithoutWaitingForASeparateFnRelease() throws {
        _ = NSApplication.shared
        let button = ShortcutRecorderButton()
        var captured: OverlayShortcut?
        button.onRecord = { captured = $0 }
        defer { button.stopRecording() }
        button.performClick(nil)
        button.capture(try event(.keyDown, flags: .function, key: 97))
        button.capture(try event(.keyUp, flags: .function, key: 97))
        #expect(captured == OverlayShortcut(modifiers: [], keyCode: 97, keyLabel: "F6"))
    }

    @Test func unavailableShortcutKeepsThePreviousPreference() throws {
        let name = "TypebarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OverlaySettings(presets: [], defaults: defaults)
        settings.shortcutValidator = { _ in "Unavailable" }
        settings.changeShortcut(OverlayShortcut(modifiers: .option, keyCode: 40, keyLabel: "K"))
        #expect(settings.value.shortcut == .default)
        #expect(settings.shortcutError == "Unavailable")
    }

    @Test func nativeEventsToggleOncePerPressAndIgnoreOldRegistrations() throws {
        _ = NSApplication.shared
        let hotKey = GlobalHotKey()
        defer { hotKey.invalidate() }
        var count = 0
        let shortcut = OverlayShortcut(modifiers: [.control, .option, .command, .shift], keyCode: 80, keyLabel: "F19")
        #expect(hotKey.register(shortcut, onPress: { count += 1 }) == noErr)
        func send(_ kind: Int, identifier: EventHotKeyID) throws {
            var rawEvent: EventRef?
            let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), 0, 0, &rawEvent)
            #expect(created == noErr)
            let event = try #require(rawEvent)
            defer { ReleaseEvent(event) }
            var identifier = identifier
            let set = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        MemoryLayout<EventHotKeyID>.size, &identifier)
            #expect(set == noErr)
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
        }
        let original = hotKey.identifier
        try send(kEventHotKeyPressed, identifier: original)
        try send(kEventHotKeyPressed, identifier: original)
        #expect(count == 1)
        try send(kEventHotKeyReleased, identifier: original)
        try send(kEventHotKeyPressed, identifier: original)
        #expect(count == 2)
        #expect(hotKey.register(shortcut, onPress: { count += 1 }) == noErr)
        try send(kEventHotKeyPressed, identifier: original)
        #expect(count == 2)
        try send(kEventHotKeyPressed, identifier: hotKey.identifier)
        #expect(count == 3)
    }

    @Test func nativeRegistrationCanBeReplacedAndReleased() {
        _ = NSApplication.shared
        let first = GlobalHotKey(), second = GlobalHotKey()
        defer { first.invalidate(); second.invalidate() }
        let shortcut = OverlayShortcut(modifiers: [.control, .option, .command, .shift], keyCode: 90, keyLabel: "F20")
        let registered = first.register(shortcut, onPress: {})
        #expect(registered == noErr)
        let duplicate = second.register(shortcut, onPress: {})
        #expect(duplicate != noErr)
        first.unregister()
        let replacement = second.register(shortcut, onPress: {})
        #expect(replacement == noErr)
    }
}
