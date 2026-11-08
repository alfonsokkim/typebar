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
