public struct ShortcutModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let command = Self(rawValue: 4)
    public static let shift = Self(rawValue: 8)
    public static let function = Self(rawValue: 16)
    public static let required: Self = [.control, .option, .command]
}

public struct ShortcutGesture {
    private var armed = false
    private var cancelled = false
    private var modifiersDown = false
    private let required: ShortcutModifiers
    public init(required: ShortcutModifiers = .required) { self.required = required }

    public mutating func flagsChanged(_ flags: ShortcutModifiers) -> Bool {
        modifiersDown = !flags.intersection(required).isEmpty
        if flags == required, !armed { armed = true }
        if modifiersDown, !flags.subtracting(required).isEmpty { cancelled = true }
        if flags.intersection(required).isEmpty {
            let shouldToggle = armed && !cancelled
            armed = false
            cancelled = false
            return shouldToggle
        }
        return false
    }

    public mutating func keyPressed() { if modifiersDown { cancelled = true } }
    public mutating func reset() { armed = false; cancelled = false; modifiersDown = false }
}
