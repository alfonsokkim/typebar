import Testing
@testable import TypingCore

@Test func bundledWordsAreMonkeytypeEnglish200() throws {
    let words = try EnglishWords.load()
    #expect(words.count == 200)
    #expect(Set(words).count == 200)
    #expect(words.contains("the"))
    #expect(words.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
}

@Test func tenWordLinesContinueWithBoundedMemory() {
    var session = TypingSession(vocabulary: ["one", "two", "three"], seed: 1)
    for i in 0..<10_000 {
        let word = session.words[session.currentIndex].target
        for char in word { session.type(char, at: Double(i)) }
        session.type(" ", at: Double(i))
        #expect(session.words.count == 20)
        #expect(session.currentIndex == (i + 1) % 10)
    }
    #expect(session.completedWords == 10_000)
    #expect(session.accuracy == 100)
}

@Test func wpmUsesFiveCharactersAndActiveTime() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "hello " { session.type(char, at: 10) }
    #expect(session.wpm(at: 10.5) == 0)
    #expect(session.wpm(at: 12) == 36)
    session.pause(at: 12)
    #expect(session.wpm(at: 14) == 36)
    session.resume(at: 14)
    #expect(session.wpm(at: 15) == 24)
}

@Test func showingBeforeFirstKeyDoesNotStartClock() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    session.resume(at: 10)
    #expect(session.elapsed(at: 900) == 0)
    session.type("h", at: 900)
    #expect(session.wpm(at: 902) == 6)
}

@Test func wrongWordsDoNotCountTowardWpm() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "xxxxx " { session.type(char, at: 0) }
    #expect(session.wpm(at: 2) == 0)
    #expect(session.completedWords == 1)
    #expect(session.accuracy == 0)
}

@Test func correctionAndUndoRemovePreviouslyCreditedWord() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "hello " { session.type(char, at: 0) }
    session.backspace(at: 1)
    #expect(session.currentIndex == 0)
    #expect(session.completedWords == 0)
    #expect(session.words[0].input == "hello")
    #expect(session.wpm(at: 2) == 30)
    session.backspace(at: 2)
    #expect(session.words[0].input == "hell")
    session.type("x", at: 3)
    session.backspace(at: 3.5)
    session.type("o", at: 4)
    session.type(" ", at: 5)
    #expect(session.words[0].isCorrect)
    #expect(session.wpm(at: 6) == 12)
    #expect(session.accuracy < 100)
}

@Test func whitespaceAndExtraInputCannotGrowSessionUnbounded() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for _ in 0..<1_000 { session.type(" ", at: 0) }
    #expect(session.totalKeystrokes == 0)
    #expect(session.elapsed(at: 500) == 0)
    for _ in 0..<1_000 { session.type("x", at: 1) }
    #expect(session.words[0].input.count == 32)
    session.deleteCurrentWord(at: 2)
    #expect(session.words[0].input.isEmpty)
    session.backspace(at: 2)
    #expect(session.currentIndex == 0)
}

@Test func adjacentWordsDifferAcrossLineBoundaries() {
    let session = TypingSession(vocabulary: ["hello", "world"], seed: 1)
    #expect(zip(session.words, session.words.dropFirst()).allSatisfy { $0.target != $1.target })
}

@Test func idleResetsSpeedButPreservesWordsAndAccuracy() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "hello " { session.type(char, at: 0) }
    #expect(session.wpm(at: 2) == 36)
    #expect(session.wpm(at: 5) > 0)
    #expect(session.wpm(at: 5.001) == 0)
    session.resetSpeedIfIdle(at: 5.001)
    #expect(session.elapsed(at: 50) == 0)
    #expect(session.currentIndex == 1)
    #expect(session.completedWords == 1)
    #expect(session.words[0].input == "hello")
    #expect(session.accuracy == 100)
    for char in "hello " { session.type(char, at: 100) }
    #expect(session.wpm(at: 102) == 36)
    #expect(session.completedWords == 2)
}

@Test func firstKeyAfterIdleResetsEvenWithoutATimerTick() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "hello " { session.type(char, at: 0) }
    for char in "hello " { session.type(char, at: 100) }
    #expect(session.wpm(at: 102) == 36)
}

@Test func partialWordBeforeBreakIsNotCreditedToTheNewMeasurement() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "he" { session.type(char, at: 0) }
    session.resetSpeedIfIdle(at: 6)
    #expect(session.words[0].input == "he")
    for char in "llo " { session.type(char, at: 100) }
    #expect(session.wpm(at: 102) == 24)
}

@Test func correctingPreBreakCharactersCanEarnFreshCredit() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "he" { session.type(char, at: 0) }
    session.resetSpeedIfIdle(at: 6)
    session.backspace(at: 100)
    session.backspace(at: 100.1)
    for char in "hello " { session.type(char, at: 100.5) }
    #expect(session.wpm(at: 102) == 36)
}

@Test func aLongHiddenBreakStartsFreshInsteadOfResumingOldSpeed() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "hello " { session.type(char, at: 0) }
    session.pause(at: 2)
    session.resume(at: 100)
    #expect(session.wpm(at: 100) == 0)
    #expect(session.elapsed(at: 101) == 0)
    for char in "hello " { session.type(char, at: 101) }
    #expect(session.wpm(at: 103) == 36)
}

@Test func backspaceCountsAsTypingActivity() {
    var session = TypingSession(vocabulary: ["hello"], seed: 1)
    for char in "hello " { session.type(char, at: 0) }
    session.backspace(at: 4)
    #expect(session.wpm(at: 8) > 0)
    session.resetSpeedIfIdle(at: 8)
    #expect(session.elapsed(at: 8) == 8)
    #expect(session.wpm(at: 9.001) == 0)
}

@Test func modifierOnlyShortcutTogglesOnlyOnceAfterFullRelease() {
    var gesture = ShortcutGesture()
    let results = [gesture.flagsChanged(.control),
                   gesture.flagsChanged([.control, .option]),
                   gesture.flagsChanged(.required),
                   gesture.flagsChanged([.control, .option]),
                   gesture.flagsChanged(.control),
                   gesture.flagsChanged([]), gesture.flagsChanged([])]
    #expect(results == [false, false, false, false, false, true, false])
}

@Test func existingThreeModifierKeyboardShortcutsDoNotToggle() {
    var gesture = ShortcutGesture()
    let armed = gesture.flagsChanged(.required)
    #expect(!armed)
    gesture.keyPressed()
    let results = [gesture.flagsChanged([]),
                   gesture.flagsChanged([.required, .shift]),
                   gesture.flagsChanged(.required), gesture.flagsChanged([]),
                   gesture.flagsChanged(.required), gesture.flagsChanged([])]
    #expect(results == [false, false, false, false, false, true])
}

@Test func pressingAnotherKeyBeforeTheFullChordAlsoCancels() {
    var gesture = ShortcutGesture()
    let first = gesture.flagsChanged([.control, .option])
    gesture.keyPressed()
    let full = gesture.flagsChanged(.required)
    let released = gesture.flagsChanged([])
    #expect(!first && !full && !released)
}

@Test func shortcutWorksInEveryModifierOrder() {
    let c = ShortcutModifiers.control, o = ShortcutModifiers.option, m = ShortcutModifiers.command
    for order in [[c, o, m], [c, m, o], [o, c, m], [o, m, c], [m, c, o], [m, o, c]] {
        var gesture = ShortcutGesture()
        var flags: ShortcutModifiers = []
        var toggles = 0
        for modifier in order {
            flags.insert(modifier)
            if gesture.flagsChanged(flags) { toggles += 1 }
        }
        for modifier in order {
            flags.remove(modifier)
            if gesture.flagsChanged(flags) { toggles += 1 }
        }
        #expect(toggles == 1)
    }
}
