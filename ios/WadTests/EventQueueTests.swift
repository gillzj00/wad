import Foundation
import Testing
@testable import Wad

/// One event on screen at a time, the rest waiting in priority order.
struct EventQueueTests {
    func event(_ kind: GameEventKind, hole: Int = 1, player: String = "zach") -> GameEvent {
        GameEvent(kind: kind, hole: hole, playerIDs: [player], playerNames: [player.capitalized])
    }

    @Test func startsTheFirstEventAndKeepsTheRestInPriorityOrder() {
        var queue = EventQueueState()
        queue.enqueue([event(.skinWon), event(.eagle), event(.wadTaken)])
        #expect(queue.current == event(.eagle))
        #expect(queue.pending == [event(.wadTaken), event(.skinWon)])

        queue.advance()
        #expect(queue.current == event(.wadTaken))
        queue.advance()
        #expect(queue.current == event(.skinWon))
        queue.advance()
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
    }

    @Test func aLaterBatchWaitsBehindTheCurrentEventButJumpsTheQueue() {
        var queue = EventQueueState()
        queue.enqueue([event(.birdie), event(.snowman, player: "sam")])
        #expect(queue.current == event(.snowman, player: "sam"))

        queue.enqueue([event(.holeInOne, hole: 2)])
        // The one playing is never interrupted.
        #expect(queue.current == event(.snowman, player: "sam"))
        #expect(queue.pending == [event(.holeInOne, hole: 2), event(.birdie)])
    }

    @Test func anEventAlreadyPlayingOrWaitingIsNotQueuedTwice() {
        var queue = EventQueueState()
        queue.enqueue([event(.greenie), event(.birdie)])
        queue.enqueue([event(.greenie), event(.birdie), event(.birdie)])
        #expect(queue.current == event(.greenie))
        #expect(queue.pending == [event(.birdie)])
    }

    @Test func enqueueingNothingChangesNothing() {
        var queue = EventQueueState()
        queue.enqueue([])
        #expect(queue.current == nil)
        queue.advance()
        #expect(queue.current == nil)
    }

    @Test func clearDropsEverything() {
        var queue = EventQueueState()
        queue.enqueue([event(.eagle), event(.birdie)])
        queue.clear()
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
    }

    @Test func everyKindHasAShowOfTwoToSixSeconds() {
        for kind in GameEventKind.allCases {
            #expect(kind.duration >= 2 && kind.duration <= 6, "\(kind)")
        }
        #expect(GameEventKind.holeInOne.duration == 6)
    }
}
