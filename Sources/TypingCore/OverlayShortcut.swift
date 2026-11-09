import Foundation

public struct OverlayShortcut: Codable, Equatable, Sendable {
    public var modifierBits: UInt8
    public var keyCode: UInt16?
    public var keyLabel: String

    public init(modifiers: ShortcutModifiers, keyCode: UInt16? = nil, keyLabel: String = "") {
        modifierBits = modifiers.rawValue
        self.keyCode = keyCode
        self.keyLabel = keyLabel
    }

    public static let `default` = Self(modifiers: .required)
    public var modifiers: ShortcutModifiers { ShortcutModifiers(rawValue: modifierBits) }
    public var isValid: Bool {
        guard modifierBits & ~UInt8(15) == 0 else { return false }
        let hasModifier = !modifiers.intersection([.control, .option, .command]).isEmpty
        if let keyCode {
            return keyCode <= 127 && (hasModifier || Self.functionKeys.contains(keyCode))
        }
        return hasModifier
    }
    public func validated() -> Self { isValid ? self : .default }
    public var displayName: String {
        let glyphs: [(ShortcutModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined()
        guard let keyCode else { return prefix }
        let label = keyLabel.isEmpty || keyLabel.count > 20 ? "Key \(keyCode)" : keyLabel
        return prefix + label
    }
    private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                                  103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
}
