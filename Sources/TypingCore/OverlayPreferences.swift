import Foundation

public struct ThemePalette: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var background: String
    public var text: String
    public var muted: String
    public var accent: String
    public var error: String

    public static let shadow = ThemePalette(id: "shadow", name: "Shadow", background: "#000000",
        text: "#F0F0F0", muted: "#A6A6A6", accent: "#F0C963", error: "#FF616B")

    public static func presets() throws -> [Self] {
        guard let url = Bundle.main.url(forResource: "themes", withExtension: "json")
                ?? Bundle.module.url(forResource: "themes", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return [.shadow] + (try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))).map { $0.validated() }
    }

    public func validated() -> Self {
        var result = self
        for key in [\Self.background, \.text, \.muted, \.accent, \.error] {
            let value = result[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines)
            let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
            if (hex.count == 3 || hex.count == 6), hex.allSatisfy(\.isHexDigit) {
                result[keyPath: key] = "#" + (hex.count == 3 ? hex.map { String(repeating: $0, count: 2) }.joined() : hex).uppercased()
            } else { result[keyPath: key] = Self.shadow[keyPath: key] }
        }
        return result
    }
}

public struct OverlayPreferences: Codable, Equatable, Sendable {
    public var themeID = "shadow"
    public var customTheme = ThemePalette.shadow
    public var cornerRadius: Double = 48
    public var blurRadius: Double = 20
    public var scale: Double = 1
    public var horizontalPosition: Double = 0.5
    public var verticalPosition: Double = 0
    public var backgroundOpacity: Double = 0.62
    public var contentOpacity: Double = 0.94
    public init() {}

    public func validated() -> Self {
        var result = self
        func clamp(_ number: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback
        }
        result.cornerRadius = clamp(cornerRadius, 0...120, fallback: 48)
        result.blurRadius = clamp(blurRadius, 0...60, fallback: 20)
        result.scale = clamp(scale, 0.6...1.4, fallback: 1)
        result.horizontalPosition = clamp(horizontalPosition, 0...1, fallback: 0.5)
        result.verticalPosition = clamp(verticalPosition, 0...1, fallback: 0)
        result.backgroundOpacity = clamp(backgroundOpacity, 0.2...1, fallback: 0.62)
        result.contentOpacity = clamp(contentOpacity, 0.4...1, fallback: 0.94)
        result.customTheme = customTheme.validated()
        return result
    }
}
