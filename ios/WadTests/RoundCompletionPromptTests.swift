import Testing
@testable import Wad

/// When the scoring screen pops up the way to the round summary.
struct RoundCompletionPromptTests {
    private let lastHole = 18

    @Test(arguments: [1, 9, 18])
    func notWhileTheRoundIsIncomplete(hole: Int) {
        #expect(!RoundCompletionPrompt.shows(wasComplete: false, isComplete: false, changedHole: hole, lastHole: lastHole, wasDismissed: false))
    }

    @Test(arguments: [1, 9, 18])
    func afterTheChangeThatCompletesTheRound(hole: Int) {
        #expect(RoundCompletionPrompt.shows(wasComplete: false, isComplete: true, changedHole: hole, lastHole: lastHole, wasDismissed: false))
    }

    /// A round that is already fully scored: a change on its last hole is what
    /// pops the summary up.
    @Test func onTheLastHoleOfARoundAlreadyComplete() {
        #expect(RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 18, lastHole: lastHole, wasDismissed: false))
    }

    @Test(arguments: [1, 9, 17])
    func notOnAnotherHoleOfARoundAlreadyComplete(hole: Int) {
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: hole, lastHole: lastHole, wasDismissed: false))
    }

    /// A score cleared on the last hole leaves the round incomplete.
    @Test func notWhenTheChangeUndoesTheCompletion() {
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: false, changedHole: 18, lastHole: lastHole, wasDismissed: false))
    }

    /// The last hole is the round's, not hole 18 by name.
    @Test func lastHoleIsTheRoundsLast() {
        #expect(RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 9, lastHole: 9, wasDismissed: false))
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 18, lastHole: 9, wasDismissed: false))
    }

    /// Once dismissed, the changes that follow on the last hole do not bring it back.
    @Test func notAgainOnTheLastHoleOnceDismissed() {
        #expect(!RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 18, lastHole: lastHole, wasDismissed: true))
    }

    /// The change that completes the round shows it even after a dismissal.
    @Test(arguments: [1, 18])
    func againWhenTheChangeCompletesTheRoundAfterADismissal(hole: Int) {
        #expect(RoundCompletionPrompt.shows(wasComplete: false, isComplete: true, changedHole: hole, lastHole: lastHole, wasDismissed: true))
    }

    /// The scoring screen forgets a dismissal when another hole is visited:
    /// a change on the last hole of a complete round shows it again.
    @Test func againOnTheLastHoleAfterAVisitToAnotherHole() {
        #expect(RoundCompletionPrompt.shows(wasComplete: true, isComplete: true, changedHole: 18, lastHole: lastHole, wasDismissed: false))
    }
}
