import Testing
@testable import TypingCore

@Test func historyRecordsOneCounterSnapshotPerClearedWord() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    session.type(" ", at: 0)
    #expect(session.wpmHistory.isEmpty)
    for character in "hello" { session.type(character, at: 0) }
    #expect(session.wpmHistory.isEmpty)
    session.type(" ", at: 2)
    #expect(session.wpmHistory == [WPMSample(completedWord: 1, wpm: session.wpm(at: 2))])
    for character in "wrong" { session.type(character, at: 2.5) }
    #expect(session.wpmHistory.count == 1)
    session.type(" ", at: 4)
    #expect(session.wpmHistory.count == 2)
    #expect(session.wpmHistory.last == WPMSample(completedWord: 2, wpm: session.wpm(at: 4)))
    #expect(session.wpmHistory.last!.wpm < session.wpmHistory.first!.wpm)
}

@Test func undoingACompletedWordReplacesItsGraphSample() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for character in "hello " { session.type(character, at: 0) }
    session.backspace(at: 1)
    #expect(session.wpmHistory.isEmpty && session.completedWords == 0)
    session.type(" ", at: 2)
    #expect(session.wpmHistory.count == 1)
    #expect(session.wpmHistory[0] == WPMSample(completedWord: 1, wpm: session.wpm(at: 2)))
    session.deleteCurrentWord(at: 3)
    #expect(session.wpmHistory.isEmpty)
}

@Test func graphHistoryResetsWithIdleSpeedAndSurvivesShortHides() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for character in "hello " { session.type(character, at: 0) }
    let history = session.wpmHistory
    session.pause(at: 1)
    session.resume(at: 2)
    #expect(session.wpmHistory == history)
    session.resetSpeedIfIdle(at: 5.001)
    #expect(session.wpmHistory.isEmpty)
    #expect(session.completedWords == 1 && session.words[0].input == "hello")
    for character in "hello " { session.type(character, at: 10) }
    #expect(session.wpmHistory.count == 1 && session.wpmHistory[0].completedWord == 2)
    for character in "hello " { session.type(character, at: 20) }
    #expect(session.wpmHistory.count == 1 && session.wpmHistory[0].completedWord == 3)
}

@Test func graphHistoryStaysBoundedThroughEndlessLineRollovers() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for word in 0..<1000 {
        for character in "hello " { session.type(character, at: Double(word)) }
    }
    #expect(session.wpmHistory.count == TypingSession.historyLimit)
    #expect(session.wpmHistory.first!.completedWord == 1000 - TypingSession.historyLimit + 1)
    #expect(session.wpmHistory.last!.completedWord == 1000)
    #expect(session.wpmHistory.allSatisfy { $0.wpm >= 0 })
}
