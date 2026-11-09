import AppKit
import Testing
@testable import TypingCore
@testable import Typebar

@MainActor
struct WPMChartTests {
    @Test func scaleFitsSamplesWithReadableWholeNumberTicks() {
        #expect(WPMChartView.upperBound(for: []) == 20)
        let samples = [WPMSample(completedWord: 1, wpm: 83), WPMSample(completedWord: 2, wpm: 121)]
        #expect(WPMChartView.upperBound(for: samples) == 140)
    }

    @Test func typingAndDirectSessionMutationsKeepTheHeaderChartInSync() throws {
        _ = NSApplication.shared
        let view = TypingView(frame: NSRect(x: 0, y: 0, width: 980, height: 181), vocabulary: ["hello"])
        let chart = try #require(view.subviews.first { $0 is WPMChartView } as? WPMChartView)
        view.insertText("hello ", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(chart.samples.count == 1)
        view.layoutSubtreeIfNeeded()
        #expect(chart.frame.minX > 100 && chart.frame.maxX < 800)
        #expect(chart.frame.maxY < 61)
        let other = ThemePalette.shadow
        view.palette = other
        #expect(chart.palette == other)
        view.session.pause(at: ProcessInfo.processInfo.systemUptime + 6)
        #expect(chart.samples.isEmpty)
        view.session = TypingSession(vocabulary: ["hello"])
        #expect(chart.samples.isEmpty)
    }
}
