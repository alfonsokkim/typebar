import Foundation

public enum EnglishWords {
    public static func load() throws -> [String] {
        struct Language: Decodable { let words: [String] }
        guard let url = Bundle.main.url(forResource: "english", withExtension: "json")
                ?? Bundle.module.url(forResource: "english", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Language.self, from: Data(contentsOf: url)).words
    }
}

public struct PracticeWord: Sendable {
    public let target: String
    public var input = ""
    public var completed = false
    public var isCorrect: Bool { input == target || (target == "I" && input == "i") }
    public func matchesInput(_ actual: Character, expected: Character) -> Bool {
        actual == expected || (target == "I" && actual == "i" && expected == "I")
    }
}

struct WordFeed {
    let vocabulary: [String]
    var state: UInt64
    var previous: String?

    mutating func next() -> String {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        var index = Int(value % UInt64(vocabulary.count))
        if vocabulary.count > 1, vocabulary[index] == previous {
            index = (index + 1) % vocabulary.count
        }
        previous = vocabulary[index]
        return vocabulary[index]
    }
}

public struct TypingSession {
    public static let wordsPerLine = 10
    public static let idleResetInterval: TimeInterval = 5
    public private(set) var words: [PracticeWord] = []
    public private(set) var currentIndex = 0
    public private(set) var completedWords = 0
    public private(set) var totalKeystrokes = 0
    public private(set) var correctKeystrokes = 0
    private var creditedCharacters = 0
    private var feed: WordFeed
    private var accumulatedTime: TimeInterval = 0
    private var activeSince: TimeInterval?
    private var hasStarted = false
    private var lastInputAt: TimeInterval?
    private var speedBaselineCharacters = 0

    public init(vocabulary: [String], seed: UInt64 = .random(in: .min ... .max)) {
        precondition(!vocabulary.isEmpty && vocabulary.allSatisfy { !$0.isEmpty })
        feed = WordFeed(vocabulary: vocabulary, state: seed)
        refill()
    }

    public mutating func type(_ character: Character, at time: TimeInterval) {
        guard !character.isNewline, !character.unicodeScalars.contains(where: { $0.value < 32 }) else { return }
        if character == " " {
            guard !words[currentIndex].input.isEmpty else { return }
            recordInput(at: time)
            totalKeystrokes += 1
            if words[currentIndex].isCorrect {
                correctKeystrokes += 1
                creditedCharacters += words[currentIndex].target.count + 1
            }
            words[currentIndex].completed = true
            speedBaselineCharacters = min(speedBaselineCharacters, correctCharacters)
            completedWords += 1
            currentIndex += 1
            if currentIndex == Self.wordsPerLine {
                words.removeFirst(Self.wordsPerLine)
                currentIndex = 0
                refill()
            }
        } else {
            guard words[currentIndex].input.count < 32 else { return }
            recordInput(at: time)
            let index = words[currentIndex].input.count
            let target = Array(words[currentIndex].target)
            totalKeystrokes += 1
            if index < target.count, words[currentIndex].matchesInput(character, expected: target[index]) { correctKeystrokes += 1 }
            words[currentIndex].input.append(character)
        }
    }

    public mutating func backspace(at time: TimeInterval) {
        guard !words[currentIndex].input.isEmpty || currentIndex > 0 else { return }
        recordInput(at: time)
        if !words[currentIndex].input.isEmpty {
            words[currentIndex].input.removeLast()
        } else if currentIndex > 0 {
            currentIndex -= 1
            completedWords -= 1
            if words[currentIndex].isCorrect { creditedCharacters -= words[currentIndex].target.count + 1 }
            words[currentIndex].completed = false
        }
        speedBaselineCharacters = min(speedBaselineCharacters, correctCharacters)
    }

    public mutating func deleteCurrentWord(at time: TimeInterval) {
        guard !words[currentIndex].input.isEmpty || currentIndex > 0 else { return }
        recordInput(at: time)
        if words[currentIndex].input.isEmpty { backspace(at: time) }
        words[currentIndex].input = ""
        speedBaselineCharacters = min(speedBaselineCharacters, correctCharacters)
    }

    public mutating func pause(at time: TimeInterval) {
        resetSpeedIfIdle(at: time)
        if let activeSince { accumulatedTime += max(0, time - activeSince) }
        activeSince = nil
    }

    public mutating func resume(at time: TimeInterval) {
        resetSpeedIfIdle(at: time)
        if hasStarted, activeSince == nil { activeSince = time }
    }

    public mutating func resetSpeedIfIdle(at time: TimeInterval) {
        guard let lastInputAt, time - lastInputAt > Self.idleResetInterval else { return }
        speedBaselineCharacters = correctCharacters
        accumulatedTime = 0
        activeSince = nil
        hasStarted = false
        self.lastInputAt = nil
    }

    public func elapsed(at time: TimeInterval) -> TimeInterval {
        accumulatedTime + (activeSince.map { max(0, time - $0) } ?? 0)
    }

    public func wpm(at time: TimeInterval) -> Int {
        guard let lastInputAt, time - lastInputAt <= Self.idleResetInterval else { return 0 }
        let seconds = elapsed(at: time)
        guard seconds >= 1 else { return 0 }
        return Int((Double(max(0, correctCharacters - speedBaselineCharacters)) * 12 / seconds).rounded())
    }

    public var accuracy: Int {
        guard totalKeystrokes > 0 else { return 100 }
        return Int((Double(correctKeystrokes) / Double(totalKeystrokes) * 100).rounded())
    }

    private var correctCharacters: Int {
        let current = words[currentIndex]
        let matching = current.completed ? 0 : zip(current.input, current.target).filter { current.matchesInput($0, expected: $1) }.count
        return creditedCharacters + matching
    }

    private mutating func recordInput(at time: TimeInterval) {
        resetSpeedIfIdle(at: time)
        hasStarted = true
        if activeSince == nil { activeSince = time }
        lastInputAt = time
    }

    private mutating func refill() {
        while words.count < Self.wordsPerLine * 2 { words.append(PracticeWord(target: feed.next())) }
    }
}
