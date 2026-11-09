import Foundation
import Testing
@testable import TypingCore

@Test func preferencesValidateRangesAndColours() throws {
    var prefs = OverlayPreferences()
    prefs.scale = .infinity; prefs.blurRadius = -10; prefs.cornerRadius = 1000
    prefs.verticalPosition = .nan; prefs.horizontalPosition = 10
    prefs.customTheme.text = "#abc"; prefs.customTheme.background = "invalid"
    let result = prefs.validated()
    #expect(result.scale == 1 && result.blurRadius == 0 && result.cornerRadius == 120)
    #expect(result.verticalPosition == 0 && result.horizontalPosition == 1)
    #expect(result.customTheme.text == "#AABBCC")
    #expect(result.customTheme.background == ThemePalette.shadow.background)
    let themes = try ThemePalette.presets()
    #expect(themes.count == 7)
    #expect(Set(themes.map(\.id)).count == themes.count)
    #expect(themes.allSatisfy { $0 == $0.validated() })
}

@Test func oldPreferencesKeepTheirAppearanceAndReceiveTheDefaultShortcut() throws {
    let legacy = Data(#"{"themeID":"dracula","scale":1.2,"backgroundOpacity":0.35,"contentOpacity":0.73}"#.utf8)
    let prefs = try JSONDecoder().decode(OverlayPreferences.self, from: legacy)
    #expect(prefs.themeID == "dracula" && prefs.scale == 1.2)
    #expect(prefs.backgroundOpacity == 0.35 && prefs.textOpacity == 0.73)
    #expect(prefs.shortcut == .default)
    let saved = try JSONEncoder().encode(prefs)
    let reloaded = try JSONDecoder().decode(OverlayPreferences.self, from: saved)
    #expect(reloaded == prefs)
    let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
    #expect(object["contentOpacity"] == nil && object["textOpacity"] != nil)
}

@Test func shortcutsValidateDisplayAndPersist() throws {
    let custom = OverlayShortcut(modifiers: [.control, .option], keyCode: 40, keyLabel: "K")
    #expect(custom.isValid && custom.displayName == "⌃⌥K")
    #expect(OverlayShortcut(modifiers: .option).isValid)
    #expect(OverlayShortcut(modifiers: .shift).isValid == false)
    #expect(OverlayShortcut(modifiers: [], keyCode: 0, keyLabel: "A").isValid == false)
    #expect(OverlayShortcut(modifiers: [], keyCode: 97, keyLabel: "F6").isValid)
    #expect(OverlayShortcut(modifiers: [.function, .control]).validated() == .default)
    var prefs = OverlayPreferences(); prefs.shortcut = custom
    #expect(try JSONDecoder().decode(OverlayPreferences.self, from: JSONEncoder().encode(prefs)) == prefs)
}

@Test func customModifierShortcutsOnlyFireAfterTheirRelease() {
    var gesture = ShortcutGesture(required: [.control, .shift])
    func update(_ flags: ShortcutModifiers) -> Bool { gesture.flagsChanged(flags) }
    #expect(!update(.control))
    #expect(!update([.control, .shift]))
    #expect(!update(.shift))
    #expect(update([]))
    #expect(!update([.control, .shift]))
    gesture.keyPressed()
    #expect(!update([]))
    #expect(!update([.control, .shift, .option]))
    #expect(!update([]))
}
