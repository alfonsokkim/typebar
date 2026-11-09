import AppKit
import Carbon
import TypingCore

final class GlobalHotKey {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pressed = false
    private var onPress: (() -> Void)?
    private static let signature: OSType = 0x54594252
    private static var nextID: UInt32 = 0
    private(set) var identifier = EventHotKeyID(signature: 0x54594252, id: 0)

    func register(_ shortcut: OverlayShortcut, onPress: @escaping () -> Void) -> OSStatus {
        unregister()
        guard let keyCode = shortcut.keyCode, shortcut.isValid else { return OSStatus(paramErr) }
        self.onPress = onPress
        Self.nextID &+= 1
        identifier = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                    var identifier = EventHotKeyID()
                    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                    guard result == noErr, owner.registration != nil,
                          identifier.signature == owner.identifier.signature,
                          identifier.id == owner.identifier.id else { return OSStatus(eventNotHandledErr) }
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed = false }
                    else if !owner.pressed { owner.pressed = true; owner.onPress?() }
                    return noErr
                }
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        var modifiers: UInt32 = 0
        for (flag, native) in [(ShortcutModifiers.control, controlKey), (.option, optionKey), (.command, cmdKey), (.shift, shiftKey)] {
            if shortcut.modifiers.contains(flag) { modifiers |= UInt32(native) }
        }
        return RegisterEventHotKey(UInt32(keyCode), modifiers, identifier,
                                   GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &registration)
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        pressed = false
        onPress = nil
    }

    // Remove the C callback before releasing this controller.
    func invalidate() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
