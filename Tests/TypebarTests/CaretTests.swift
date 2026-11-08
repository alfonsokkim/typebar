import AppKit
import Testing
@testable import Typebar

@Suite(.serialized)
@MainActor
struct CaretTests {
    private func makeView() -> (NSWindow, TypingView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 980, height: 181),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = TypingView(frame: NSRect(x: 0, y: 0, width: 980, height: 181), vocabulary: ["hello"])
        window.contentView = view
        window.orderFront(nil)
        view.display()
        return (window, view)
    }

    @Test func typingRetargetsOneShortCaretAnimation() throws {
        let (window, view) = makeView()
        defer { window.orderOut(nil) }
        let caret = try #require(view.layer?.sublayers?.first { $0.name == "typingCaret" })
        let initial = caret.position
        view.insertText("h", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.display()
        #expect(caret.position.x > initial.x)
        #expect(caret.position.y == initial.y)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = try #require(caret.animation(forKey: "caretMovement") as? CABasicAnimation)
            #expect(animation.duration == 0.11)
            #expect((animation.toValue as? NSValue)?.pointValue == caret.position)
            view.insertText("e", replacementRange: NSRange(location: NSNotFound, length: 0))
            view.display()
            #expect(caret.animationKeys() == ["caretMovement"])
            let retargeted = try #require(caret.animation(forKey: "caretMovement") as? CABasicAnimation)
            #expect((retargeted.toValue as? NSValue)?.pointValue == caret.position)
        } else {
            #expect(caret.animationKeys()?.isEmpty != false)
        }
    }

    @Test func lineRolloverAndReopeningDoNotSweepAcrossThePanel() throws {
        let (window, view) = makeView()
        defer { window.orderOut(nil) }
        let caret = try #require(view.layer?.sublayers?.first { $0.name == "typingCaret" })
        view.insertText(String(repeating: "hello ", count: 10), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.display()
        #expect(view.session.completedWords == 10)
        #expect(caret.animation(forKey: "caretMovement") == nil)
        view.insertText("h", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.display()
        view.settleCaret()
        view.display()
        #expect(caret.animation(forKey: "caretMovement") == nil)
    }

    @Test func periodicRefreshClearsIdleSpeedWithoutClearingTheWords() {
        let (window, view) = makeView()
        defer { window.orderOut(nil) }
        let beforeBreak = ProcessInfo.processInfo.systemUptime - 6
        for char in "hello " { view.session.type(char, at: beforeBreak) }
        view.refreshAccessibility()
        #expect(view.session.completedWords == 1)
        #expect(view.session.currentIndex == 1)
        #expect(view.session.elapsed(at: ProcessInfo.processInfo.systemUptime) == 0)
        #expect((view.accessibilityValue() as? String)?.contains("0 words per minute") == true)
    }
}
