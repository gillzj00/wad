import Foundation
import SwiftData
import Testing
@testable import Wad

/// Sharing relays what `EventCenter` newly records, once; following plays
/// what arrives and sends nothing back.
@MainActor
struct LiveCenterTests {
    let container: ModelContainer
    let round: Round
    let scorer: RoundScorer
    let events: EventCenter
    let transport = FakeLiveTransport()
    let sleeper = FakeSleeper()
    let code = "ABC123"
    let eagle = GameEvent(kind: .eagle, hole: 2, playerIDs: ["sam"], playerNames: ["Sam"])
    let score = LivePayload.score(LiveScorePayload(playerID: "sam", playerName: "Sam", hole: 2, par: 5, gross: 3))

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        round = try RoundFixtures.threePlayerDraft().makeRound(using: try EngineBridge())
        container.mainContext.insert(round)
        try container.mainContext.save()
        scorer = RoundScorer(round: round)
        events = EventCenter(settings: Self.settings(animations: true))
    }

    /// Defaults of its own, with the sounds off: the test host has no audio to play.
    static func settings(animations: Bool) -> EventSettings {
        let suite = "LiveCenterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = EventSettings(defaults: defaults)
        settings.soundsEnabled = false
        settings.animationsEnabled = animations
        return settings
    }

    func makeCenter(events: EventCenter? = nil, configuration: LiveConfiguration? = nil) -> LiveCenter {
        LiveCenter(
            configuration: configuration ?? LiveConfiguration(url: URL(string: "wss://example.test/dev"), clientToken: "secret-token"),
            events: events ?? self.events,
            transport: transport,
            sleep: sleeper.sleep
        )
    }

    func connection(_ index: Int) async throws -> FakeLiveConnection {
        #expect(await eventually { transport.connections.count > index })
        return try #require(transport.connections.count > index ? transport.connections[index] : nil)
    }

    /// Subscribed under the code, in the role.
    func subscribed(_ center: LiveCenter, index: Int = 0) async throws -> FakeLiveConnection {
        let connection = try await connection(index)
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code)] })
        connection.push(.subscribed(roundCode: code, members: 2))
        #expect(await eventually { center.state == .subscribed(members: 2) })
        return connection
    }

    func publishes(_ connection: FakeLiveConnection) -> [LivePayload] {
        connection.sentFrames.compactMap { frame in
            if case .publish(_, let message) = frame { return message }
            return nil
        }
    }

    /// A change scored the way the scoring screen does it.
    func perform(_ change: () throws -> Void) throws {
        let before = events.snapshot(of: round)
        try change()
        events.record(round, before: before)
    }

    @Test func sharingPublishesTheScoresAndTheEventsAChangeNewlyRecordedOnce() async throws {
        let center = makeCenter()
        center.share(code: code)
        #expect(center.role == .sharing)
        #expect(center.isSharing(code))
        #expect(!center.isSharing("XYZ789"))
        #expect(!center.isSharing(nil))
        let connection = try await subscribed(center)

        // Pars by Sam and Alex on hole 1 (par 4): scores, no event yet.
        try perform { try scorer.setGross(4, playerID: "sam", hole: 1) }
        try perform { try scorer.setGross(4, playerID: "alex", hole: 1) }
        #expect(await eventually { publishes(connection).count == 2 })

        // Zach's birdie completes the hole: his score, then the skin and the birdie.
        try perform { try scorer.setGross(3, playerID: "zach", hole: 1) }
        #expect(await eventually { publishes(connection).count == 5 })
        #expect(publishes(connection)[2] == .score(LiveScorePayload(playerID: "zach", playerName: "Zach", hole: 1, par: 4, gross: 3)))
        let relayed = publishes(connection).compactMap { payload -> LiveGameEventPayload? in
            if case .gameEvent(let event) = payload { return event }
            return nil
        }
        #expect(relayed.map(\.kind) == ["skinWon", "birdie"])
        #expect(relayed.last?.hole == 1)
        #expect(relayed.last?.playerNames == ["Zach"])
        #expect(relayed.last?.otherNames == ["Sam", "Alex"])
        // The shows are for the followers: nothing plays on the scoring phone.
        #expect(events.current == nil)

        // Saving the same score again records nothing new.
        try perform { try scorer.setGross(3, playerID: "zach", hole: 1) }
        await settle()
        #expect(publishes(connection).count == 5)

        // A changed par is a score without an event; a cleared score is sent as null.
        try perform { try scorer.setGross(5, playerID: "sam", hole: 1) }
        try perform { try scorer.setGross(nil, playerID: "sam", hole: 1) }
        #expect(await eventually { publishes(connection).count == 7 })
        #expect(publishes(connection).suffix(2) == [
            .score(LiveScorePayload(playerID: "sam", playerName: "Sam", hole: 1, par: 4, gross: 5)),
            .score(LiveScorePayload(playerID: "sam", playerName: "Sam", hole: 1, par: 4, gross: nil)),
        ])
        #expect(events.current == nil)

        // Stopping takes the hooks away: a later change is not relayed, and
        // the shows play here again. Sam's score completes hole 1 once more.
        center.stop()
        #expect(center.role == nil)
        #expect(center.state == .idle)
        #expect(connection.isClosed)
        try perform { try scorer.setGross(4, playerID: "sam", hole: 1) }
        await settle()
        #expect(publishes(connection).count == 7)
        #expect(events.relay == nil)
        #expect(events.relayScores == nil)
        #expect(events.current?.kind == .skinWon)
    }

    @Test func sharingRelaysWithTheShowsSwitchedOff() async throws {
        let events = EventCenter(settings: Self.settings(animations: false))
        let center = makeCenter(events: events)
        center.share(code: code)
        let connection = try await subscribed(center)

        try scorer.setGross(4, playerID: "sam", hole: 1)
        try scorer.setGross(4, playerID: "alex", hole: 1)
        let before = events.snapshot(of: round)
        #expect(before != nil)
        try scorer.setGross(3, playerID: "zach", hole: 1)
        events.record(round, before: before)
        #expect(await eventually { publishes(connection).count == 3 })
        // Nothing plays here.
        #expect(events.current == nil)

        // Without the relay the snapshot is skipped, as before.
        center.stop()
        #expect(events.snapshot(of: round) == nil)
    }

    @Test func followingPlaysReceivedEventsAndPublishesNothingBack() async throws {
        let center = makeCenter()
        center.follow(code: code)
        #expect(center.role == .following)
        #expect(center.code == code)
        #expect(events.relay == nil)
        let connection = try await subscribed(center)

        connection.push(.message(roundCode: code, message: .gameEvent(LiveGameEventPayload(eagle)), sentAt: "2026-10-05T15:04:05Z"))
        #expect(await eventually { events.current == eagle })
        connection.push(.message(roundCode: code, message: score, sentAt: "2026-10-05T15:04:06Z"))
        #expect(await eventually { center.feed.count == 2 })
        #expect(center.feed.map(\.payload) == [score, .gameEvent(LiveGameEventPayload(eagle))])

        // The event went through `enqueue`, not `record`: nothing is sent back.
        await settle()
        #expect(connection.sentFrames == [.subscribe(roundCode: code)])

        // Scoring on this phone while following relays nothing either.
        try perform { try scorer.setGross(3, playerID: "zach", hole: 1) }
        await settle()
        #expect(connection.sentFrames == [.subscribe(roundCode: code)])
    }

    @Test func aFollowerWithTheShowsOffKeepsTheFeedOnly() async throws {
        let events = EventCenter(settings: Self.settings(animations: false))
        let center = makeCenter(events: events)
        center.follow(code: code)
        let connection = try await subscribed(center)
        connection.push(.message(roundCode: code, message: .gameEvent(LiveGameEventPayload(eagle)), sentAt: ""))
        #expect(await eventually { center.feed.count == 1 })
        await settle()
        #expect(events.current == nil)
    }

    @Test func oneRoleAtATime() async throws {
        let center = makeCenter()
        center.share(code: code)
        let first = try await subscribed(center)

        center.follow(code: "XYZ789")
        #expect(center.role == .following)
        #expect(first.isClosed)
        #expect(events.relay == nil)
        let second = try await connection(1)
        #expect(await eventually { second.sentFrames == [.subscribe(roundCode: "XYZ789")] })

        center.share(code: code)
        #expect(center.role == .sharing)
        #expect(second.isClosed)
        #expect(events.relay != nil)
        let third = try await connection(2)
        #expect(await eventually { third.sentFrames == [.subscribe(roundCode: code)] })

        center.didReturnToForeground()
        #expect(third.isClosed)
        let fourth = try await connection(3)
        #expect(await eventually { fourth.sentFrames == [.subscribe(roundCode: code)] })
        #expect(center.role == .sharing)
        #expect(center.code == code)
    }

    @Test func nothingIsOfferedWithoutTheSettingsOrWithABadCode() async throws {
        let unconfigured = makeCenter(configuration: .unconfigured)
        #expect(!unconfigured.isConfigured)
        unconfigured.share(code: code)
        unconfigured.follow(code: code)
        await settle()
        #expect(unconfigured.role == nil)
        #expect(transport.requests.isEmpty)
        #expect(events.relay == nil)

        let center = makeCenter()
        #expect(center.isConfigured)
        center.share(code: "abc123")
        center.follow(code: "ABC12")
        await settle()
        #expect(center.role == nil)
        #expect(transport.requests.isEmpty)
    }
}

/// While the round is shared live the shows are for the followers: the
/// scoring phone relays them and plays nothing. Not sharing, it plays them.
@MainActor
struct EventCenterTests {
    let container: ModelContainer
    let round: Round
    let scorer: RoundScorer
    let events: EventCenter

    init() throws {
        container = try ModelContainer(for: Round.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        round = try RoundFixtures.threePlayerDraft().makeRound(using: try EngineBridge())
        container.mainContext.insert(round)
        try container.mainContext.save()
        scorer = RoundScorer(round: round)
        events = EventCenter(settings: LiveCenterTests.settings(animations: true))
    }

    /// Pars by Sam and Alex on hole 1, then Zach's birdie completes it: Zach
    /// (a tick on hole 1) wins the skin.
    func scoreHole1() throws {
        try scorer.setGross(4, playerID: "sam", hole: 1)
        try scorer.setGross(4, playerID: "alex", hole: 1)
        let before = events.snapshot(of: round)
        try scorer.setGross(3, playerID: "zach", hole: 1)
        events.record(round, before: before)
    }

    @Test func sharingRelaysTheEventsAndPlaysNothingHere() throws {
        var relayed: [GameEvent] = []
        var relayedScores: [ScoreChange] = []
        events.relay = { relayed += $0 }
        events.relayScores = { relayedScores += $0 }
        try scoreHole1()
        #expect(relayed.map(\.kind) == [.skinWon, .birdie])
        #expect(relayedScores == [ScoreChange(playerID: "zach", playerName: "Zach", hole: 1, par: 4, gross: 3)])
        #expect(events.queue.current == nil)
    }

    @Test func notSharingPlaysTheEventsHere() throws {
        #expect(events.relay == nil)
        try scoreHole1()
        #expect(events.queue.current?.kind == .skinWon)
    }
}

/// Which scores a change set, changed or cleared.
struct ScoreDetectorTests {
    let players = [GameSnapshot.Player(id: "zach", name: "Zach"), GameSnapshot.Player(id: "sam", name: "Sam")]

    func snapshot(_ scores: [GameSnapshot.Score]) -> GameSnapshot {
        GameSnapshot(players: players, scores: scores)
    }

    @Test func findsSetChangedAndClearedScores() {
        let before = snapshot([
            GameSnapshot.Score(playerID: "zach", hole: 1, par: 4, gross: 4),
            GameSnapshot.Score(playerID: "sam", hole: 1, par: 4, gross: 5),
            GameSnapshot.Score(playerID: "sam", hole: 2, par: 5, gross: 6),
        ])
        let after = snapshot([
            GameSnapshot.Score(playerID: "zach", hole: 1, par: 4, gross: 3),
            GameSnapshot.Score(playerID: "sam", hole: 1, par: 4, gross: 5),
            GameSnapshot.Score(playerID: "zach", hole: 2, par: 5, gross: 5),
        ])
        #expect(ScoreDetector.changes(before: before, after: after) == [
            ScoreChange(playerID: "zach", playerName: "Zach", hole: 1, par: 4, gross: 3),
            ScoreChange(playerID: "zach", playerName: "Zach", hole: 2, par: 5, gross: 5),
            ScoreChange(playerID: "sam", playerName: "Sam", hole: 2, par: 5, gross: nil),
        ])
        #expect(ScoreDetector.changes(before: after, after: after).isEmpty)
        #expect(ScoreDetector.changes(before: snapshot([]), after: snapshot([])).isEmpty)
    }
}
