import Testing
@testable import Wad

/// When the scoring screen pops up the way to the round summary.
struct RoundCompletionPromptTests {
    private let lastHole = 18

    @Test(arguments: [1, 9, 18])
    func notWhileTheRoundIsIncomplete(hole: Int) {
        #expect(!RoundCompletionPrompt.shows(wasComplete: false, isComplete: false, changedHole: hole, lastHole: lastHole))
    }

    @Test(arguments: [1, 9, 18])
    func afterTheChangeThatCompletesTheRound(hole: Int) {
        #expect(RoundCompletionPrompt.shows(wasComplete: false, isComplete: true, changedHole: hole, lastHole: lastHole))
    }

    /// A round that started every hole at par is complete from the start: a
    /// change on its last hole is what pops the summary up.
    @Test func onTheLastHoleOfARoundAlreadyComplete() {
        #expect(RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 18, lastHole: lastHole))
    }

    @Test(arguments: [1, 9, 17])
    func notOnAnotherHoleOfARoundAlreadyComplete(hole: Int) {
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: hole, lastHole: lastHole))
    }

    /// A score cleared on the last hole leaves the round incomplete.
    @Test func notWhenTheChangeUndoesTheCompletion() {
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: false, changedHole: 18, lastHole: lastHole))
    }

    /// The last hole is the round's, not hole 18 by name.
    @Test func lastHoleIsTheRoundsLast() {
        #expect(RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 9, lastHole: 9))
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 18, lastHole: 9))
    }
}
