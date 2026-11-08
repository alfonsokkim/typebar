import AppKit
import TypingCore

final class TypingView: NSView, NSTextInputClient {
    var session: TypingSession
    var onHide: (() -> Void)?
    var onRestart: (() -> Void)?
    var onSettings: (() -> Void)?
    var palette = ThemePalette.shadow {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            caretLayer.backgroundColor = NSColor(themeHex: palette.accent).cgColor
            CATransaction.commit()
            for button in [settingsButton, resetButton, hideButton] { button.contentTintColor = NSColor(themeHex: palette.muted) }
            needsDisplay = true
        }
    }
    private var marked = ""
    private var caret = NSRect.zero
    private let caretLayer = CALayer()
    private var snapCaretOnNextDraw = true
    private let resetButton = NSButton()
    private let hideButton = NSButton()
    private let settingsButton = NSButton()
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, vocabulary: [String]) {
        session = TypingSession(vocabulary: vocabulary)
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        caretLayer.name = "typingCaret"
        caretLayer.anchorPoint = .zero
        caretLayer.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.79, blue: 0.39, alpha: 1).cgColor
        caretLayer.cornerRadius = 1
        caretLayer.isHidden = true
        layer?.addSublayer(caretLayer)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Typing practice")
        setAccessibilityHelp("Type the words shown. Space advances, backspace corrects, Tab restarts, Escape hides.")
        for (button, symbol, label, action) in [
            (settingsButton, "gearshape", "Typebar Settings", #selector(openSettings)),
            (resetButton, "arrow.counterclockwise", "Restart typing session", #selector(restart)),
            (hideButton, "xmark", "Hide typing overlay", #selector(hideOverlay))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.bezelStyle = .inline
            button.isBordered = false
            button.contentTintColor = .white.withAlphaComponent(0.45)
            button.target = self
            button.action = action
            button.toolTip = label
            button.setAccessibilityLabel(label)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        resetButton.frame = NSRect(x: bounds.width - 70, y: 17, width: 24, height: 24)
        hideButton.frame = NSRect(x: bounds.width - 39, y: 17, width: 24, height: 24)
        settingsButton.frame = NSRect(x: bounds.width - 101, y: 17, width: 24, height: 24)
    }

    @objc private func restart() { onRestart?() }
    @objc private func hideOverlay() { onHide?() }
    @objc private func openSettings() { onSettings?() }

    override func draw(_ dirtyRect: NSRect) {
        text("english 200", at: NSPoint(x: 25, y: 23), size: 11, color: NSColor(themeHex: palette.muted))
        let speed = session.wpm(at: ProcessInfo.processInfo.systemUptime)
        let metrics = "\(speed) wpm"
        let metricsWidth = (metrics as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)]).width
        (metrics as NSString).draw(at: NSPoint(x: bounds.width - 128 - metricsWidth, y: 18), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor(themeHex: palette.accent)
        ])
        for line in 0..<2 { drawLine(line) }
        text("esc  hide     tab  restart", at: NSPoint(x: 25, y: 151), size: 10, color: NSColor(themeHex: palette.muted).withAlphaComponent(0.8))
        let accuracy = "\(session.accuracy)% accuracy"
        let width = (accuracy as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
        text(accuracy, at: NSPoint(x: bounds.width - 25 - width, y: 151), size: 10, color: NSColor(themeHex: palette.muted).withAlphaComponent(0.8))
    }

    private func drawLine(_ line: Int) {
        let start = line * TypingSession.wordsPerLine
        let indices = start..<(start + TypingSession.wordsPerLine)
        let characters = indices.reduce(0) { $0 + max(session.words[$1].target.count, session.words[$1].input.count) }
        let size = min(22, (bounds.width - 50) / (Double(characters) * 0.61 + 9 * 0.85))
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let charWidth = ("m" as NSString).size(withAttributes: [.font: font]).width
        var x: CGFloat = 25
        let y: CGFloat = line == 0 ? 61 : 105
        for index in indices {
            let word = session.words[index]
            let input = Array(word.input)
            let target = Array(word.target)
            for offset in 0..<max(target.count, input.count) {
                let character = offset < target.count ? target[offset] : input[offset]
                let color: NSColor
                if offset < input.count {
                    color = offset < target.count && input[offset] == target[offset]
                        ? NSColor(themeHex: palette.text)
                        : NSColor(themeHex: palette.error)
                } else if word.completed {
                    color = NSColor(themeHex: palette.error).withAlphaComponent(0.8)
                } else {
                    color = NSColor(themeHex: palette.muted).withAlphaComponent(line == 1 ? 0.7 : 1)
                }
                (String(character) as NSString).draw(at: NSPoint(x: x + Double(offset) * charWidth, y: y),
                                                    withAttributes: [.font: font, .foregroundColor: color])
            }
            if index == session.currentIndex {
                moveCaret(to: NSRect(x: x + Double(input.count) * charWidth - 1, y: y - 1,
                                    width: 2, height: size + 7))
            }
            x += Double(max(target.count, input.count)) * charWidth + size * 0.85
        }
    }

    private func moveCaret(to target: NSRect) {
        guard target != caret || snapCaretOnNextDraw else { return }
        let origin = caretLayer.presentation()?.position ?? caretLayer.position
        let animate = !snapCaretOnNextDraw && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && window?.isVisible == true
        caret = target
        snapCaretOnNextDraw = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.removeAnimation(forKey: "caretMovement")
        caretLayer.bounds = NSRect(origin: .zero, size: target.size)
        caretLayer.position = target.origin
        caretLayer.isHidden = false
        CATransaction.commit()
        if animate {
            let movement = CABasicAnimation(keyPath: "position")
            movement.fromValue = NSValue(point: origin)
            movement.toValue = NSValue(point: target.origin)
            movement.duration = 0.11
            movement.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            caretLayer.add(movement, forKey: "caretMovement")
        }
    }

    func settleCaret() {
        caretLayer.removeAnimation(forKey: "caretMovement")
        snapCaretOnNextDraw = true
        needsDisplay = true
    }

    @objc private func accessibilityOptionsChanged() { settleCaret() }

    private func text(_ value: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
    }

    func refreshAccessibility() {
        session.resetSpeedIfIdle(at: ProcessInfo.processInfo.systemUptime)
        let current = session.words[session.currentIndex]
        setAccessibilityValue("\(session.completedWords) words completed. Current word: \(current.target). Typed: \(current.input). \(session.wpm(at: ProcessInfo.processInfo.systemUptime)) words per minute.")
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onHide?(); return }
        if event.keyCode == 48 { onRestart?(); return }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "r": onRestart?()
            case "w": onHide?()
            case "q": NSApplication.shared.terminate(nil)
            case ",": onSettings?()
            default: break
            }
            return
        }
        interpretKeyEvents([event])
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let value = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        let previousLine = session.completedWords / TypingSession.wordsPerLine
        marked = ""
        for character in value where character.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) {
            session.type(character, at: ProcessInfo.processInfo.systemUptime)
        }
        if session.completedWords / TypingSession.wordsPerLine != previousLine { settleCaret() }
        refreshAccessibility()
    }

    override func doCommand(by selector: Selector) {
        switch NSStringFromSelector(selector) {
        case "deleteBackward:": session.backspace(at: ProcessInfo.processInfo.systemUptime)
        case "deleteWordBackward:", "deleteToBeginningOfLine:": session.deleteCurrentWord(at: ProcessInfo.processInfo.systemUptime)
        case "insertTab:": onRestart?()
        case "cancelOperation:": onHide?()
        default: break
        }
        refreshAccessibility()
    }

    func hasMarkedText() -> Bool { !marked.isEmpty }
    func markedRange() -> NSRange { marked.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: marked.utf16.count) }
    func selectedRange() -> NSRange { NSRange(location: session.words[session.currentIndex].input.utf16.count, length: 0) }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
    }
    func unmarkText() { marked = "" }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(caret, to: nil)) ?? .zero
    }
}
