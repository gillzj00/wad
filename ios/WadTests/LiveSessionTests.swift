import Foundation
import Testing
@testable import Wad

/// The game events another phone sent, as the session hands them over.
@MainActor
final class ReceivedEvents {
    var events: [GameEvent] = []
}

/// One room of the relay over the fake transport: connecting, subscribing,
/// publishing, receiving, pinging, reconnecting and stopping, with the
/// sleeps ended by the test.
@MainActor
struct LiveSessionTests {
    let transport = FakeLiveTransport()
    let sleeper = FakeSleeper()
    let configuration = LiveConfiguration(url: URL(string: "wss://example.test/dev"), clientToken: "secret-token")
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let code = "ABC123"
    let birdie = GameEvent(kind: .birdie, hole: 4, playerIDs: ["p1"], playerNames: ["Zach"], otherNames: ["Sam", "Alex"])
    let score = LivePayload.score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: 3))

    func makeSession() -> LiveSession {
        let now = now
        return LiveSession(configuration: configuration, transport: transport, sleep: sleeper.sleep, now: { now })
    }

    /// The connection the transport handed out, once it has.
    func connection(_ index: Int) async throws -> FakeLiveConnection {
        #expect(await eventually { transport.connections.count > index })
        return try #require(transport.connections.count > index ? transport.connections[index] : nil)
    }

    func message(_ payload: LivePayload) -> LiveServerFrame {
        .message(roundCode: code, message: payload, sentAt: "2026-10-05T15:04:05Z")
    }

    /// Started, connected and subscribed.
    func subscribedSession(members: Int = 2) async throws -> (LiveSession, FakeLiveConnection) {
        let session = makeSession()
        session.start(code: code)
        let connection = try await connection(0)
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code)] })
        connection.push(.subscribed(roundCode: code, members: members))
        #expect(await eventually { session.state == .subscribed(members: members) })
        return (session, connection)
    }

    @Test func subscribesAfterConnectingWithTheToken() async throws {
        let session = makeSession()
        #expect(session.state == .idle)
        session.start(code: code)
        #expect(session.state == .connecting)
        #expect(session.code == code)
        #expect(session.isRunning)

        let connection = try await connection(0)
        #expect(transport.requests == [FakeLiveTransport.Request(url: configuration.url!, headers: ["x-wad-client": "secret-token"])])
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code)] })
        #expect(session.state == .connected)

        connection.push(.subscribed(roundCode: code, members: 2))
        #expect(await eventually { session.state == .subscribed(members: 2) })
    }

    @Test func publishesOnlyWhileSubscribedAndDropsTheRest() async throws {
        let session = makeSession()
        session.publish(score)
        session.start(code: code)
        session.publish(score)
        let connection = try await connection(0)
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code)] })
        session.publish(score)
        await settle()
        #expect(connection.sentFrames == [.subscribe(roundCode: code)])

        connection.push(.subscribed(roundCode: code, members: 1))
        #expect(await eventually { session.state == .subscribed(members: 1) })
        session.publish(score)
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code), .publish(roundCode: code, message: score)] })

        // The relay says how many phones got it: the members are them and this one.
        connection.push(.published(roundCode: code, delivered: 2))
        #expect(await eventually { session.state == .subscribed(members: 3) })

        // A frame over the relay's limit is not sent.
        session.publish(.score(LiveScorePayload(playerID: String(repeating: "p", count: 5000), playerName: "Zach", hole: 4, par: 4, gross: 3)))
        await settle()
        #expect(connection.sentFrames.count == 2)
    }

    @Test func aReceivedGameEventReachesTheCallbackAndTheFeed() async throws {
        let (session, connection) = try await subscribedSession()
        let received = ReceivedEvents()
        session.onGameEvent = { received.events.append($0) }

        connection.push(message(.gameEvent(LiveGameEventPayload(birdie))))
        #expect(await eventually { received.events == [birdie] })
        #expect(session.feed.map(\.payload) == [.gameEvent(LiveGameEventPayload(birdie))])
        #expect(session.feed.first?.receivedAt == now)

        // Newest first.
        connection.push(message(score))
        #expect(await eventually { session.feed.count == 2 })
        #expect(session.feed.map(\.payload) == [score, .gameEvent(LiveGameEventPayload(birdie))])

        // What this build does not know, and what is not a frame, is ignored.
        connection.push(message(.unknown(type: "chat")))
        connection.push(message(.gameEvent(LiveGameEventPayload(kind: "chipIn", hole: 2, playerIDs: ["p1"], playerNames: ["Zach"]))))
        connection.push("not json")
        connection.push(#"{"event":"later"}"#)
        connection.push(.pong)
        await settle()
        #expect(received.events == [birdie])
        #expect(session.feed.count == 2)
        #expect(session.state == .subscribed(members: 2))
    }

    @Test func theFeedKeepsTheLatestTwoHundred() async throws {
        let (session, connection) = try await subscribedSession()
        for hole in 1...205 {
            connection.push(message(.score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: hole, par: 4, gross: 4))))
        }
        #expect(await eventually { session.feed.count == LiveSession.feedLimit && session.feed.first?.payload == .score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 205, par: 4, gross: 4)) })
        #expect(session.feed.last?.payload == .score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 6, par: 4, gross: 4)))
    }

    @Test func pingsEveryThirtySecondsWhileConnected() async throws {
        let (session, connection) = try await subscribedSession()
        #expect(await eventually { sleeper.pendingDurations == [LiveSession.pingInterval] })
        sleeper.fire()
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code), .ping] })
        connection.push(.pong)
        #expect(await eventually { sleeper.pendingDurations == [LiveSession.pingInterval] })
        #expect(LiveSession.pingInterval == .seconds(30))

        session.stop()
        #expect(await eventually { sleeper.pendingDurations.isEmpty })
    }

    @Test func aDropReconnectsAfterABackoffAndSubscribesAgain() async throws {
        let (session, first) = try await subscribedSession()

        first.drop()
        #expect(await eventually { session.state == .failed("You seem to be offline. Reconnecting.") })
        #expect(await eventually { sleeper.pendingDurations == [.seconds(1)] })
        #expect(first.isClosed)
        #expect(transport.connections.count == 1)
        // Nothing is sent while down.
        session.publish(score)

        sleeper.fire()
        let second = try await connection(1)
        #expect(await eventually { second.sentFrames == [.subscribe(roundCode: code)] })
        #expect(session.state == .connected)
        second.push(.subscribed(roundCode: code, members: 1))
        #expect(await eventually { session.state == .subscribed(members: 1) })
        #expect(first.sentFrames == [.subscribe(roundCode: code)])
        #expect(session.code == code)
    }

    @Test func theBackoffGrowsToThirtySecondsAndStartsOverAfterAConnection() async throws {
        transport.failNextConnects(with: Array(repeating: URLError(.cannotConnectToHost), count: 7))
        let session = makeSession()
        session.start(code: code)
        let expected: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)]
        for delay in expected {
            #expect(await eventually { sleeper.pendingDurations == [delay] })
            #expect(session.state == .failed("You seem to be offline. Reconnecting."))
            sleeper.fire()
        }
        let connection = try await connection(0)
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code)] })
        #expect(transport.requests.count == 8)
        // The ping sleep comes after the connection, so the waits are the first ones asked for.
        #expect(Array(sleeper.requested.prefix(expected.count)) == expected)

        connection.drop(LiveTransportError.closed(code: 1006))
        #expect(await eventually { session.state == .failed("The relay refused the connection. Reconnecting.") })
        #expect(await eventually { sleeper.pendingDurations == [.seconds(1)] })
    }

    @Test func aRefusedTokenStopsTrying() async throws {
        transport.failNextConnects(with: [LiveTransportError.refused(status: 401)])
        let session = makeSession()
        session.start(code: code)
        #expect(await eventually { session.state == .failed("This build is not allowed to use live sharing.") })
        await settle()
        #expect(!session.isRunning)
        #expect(sleeper.pendingDurations.isEmpty)
        #expect(transport.requests.count == 1)
        #expect(transport.connections.isEmpty)
    }

    @Test func notSubscribedSubscribesAgain() async throws {
        let (session, connection) = try await subscribedSession()
        connection.push(.error(code: "not_subscribed"))
        #expect(await eventually { connection.sentFrames == [.subscribe(roundCode: code), .subscribe(roundCode: code)] })
        connection.push(.error(code: "invalid_message"))
        await settle()
        #expect(connection.sentFrames.count == 2)
        #expect(session.state == .subscribed(members: 2))
    }

    @Test func stopClosesTheConnectionAndIgnoresLateFrames() async throws {
        let (session, connection) = try await subscribedSession()
        let received = ReceivedEvents()
        session.onGameEvent = { received.events.append($0) }

        session.stop()
        #expect(session.state == .idle)
        #expect(session.code == nil)
        #expect(!session.isRunning)
        #expect(connection.isClosed)

        connection.push(message(.gameEvent(LiveGameEventPayload(birdie))))
        connection.push(.subscribed(roundCode: code, members: 5))
        session.publish(score)
        await settle()
        #expect(received.events.isEmpty)
        #expect(session.feed.isEmpty)
        #expect(session.state == .idle)
        #expect(connection.sentFrames == [.subscribe(roundCode: code)])
        // No reconnect either.
        #expect(transport.connections.count == 1)
        #expect(sleeper.pendingDurations.isEmpty)
    }

    @Test func resumeConnectsAgainAndKeepsTheFeed() async throws {
        let (session, first) = try await subscribedSession()
        first.push(message(score))
        #expect(await eventually { session.feed.count == 1 })

        session.resume()
        #expect(first.isClosed)
        let second = try await connection(1)
        #expect(await eventually { second.sentFrames == [.subscribe(roundCode: code)] })
        #expect(session.code == code)
        #expect(session.feed.count == 1)

        // Nothing to resume once stopped.
        session.stop()
        session.resume()
        await settle()
        #expect(transport.connections.count == 2)
        #expect(session.state == .idle)
    }

    @Test func anotherCodeClosesTheFirstConnectionAndClearsTheFeed() async throws {
        let (session, first) = try await subscribedSession()
        first.push(message(score))
        #expect(await eventually { session.feed.count == 1 })

        session.start(code: "XYZ789")
        #expect(first.isClosed)
        #expect(session.feed.isEmpty)
        let second = try await connection(1)
        #expect(await eventually { second.sentFrames == [.subscribe(roundCode: "XYZ789")] })
        #expect(session.code == "XYZ789")
    }

    @Test func nothingConnectsWithoutTheSettings() async {
        let session = LiveSession(configuration: .unconfigured, transport: transport, sleep: sleeper.sleep)
        session.start(code: code)
        await settle()
        #expect(session.state == .idle)
        #expect(!session.isRunning)
        #expect(session.code == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func errorsHaveTheirMessagesWithoutTheToken() {
        #expect(LiveSession.describe(URLError(.notConnectedToInternet)) == "You seem to be offline.")
        #expect(LiveSession.describe(URLError(.timedOut)) == "You seem to be offline.")
        #expect(LiveSession.describe(URLError(.cancelled)) == "The connection dropped.")
        #expect(LiveSession.describe(LiveTransportError.refused(status: 401)) == "This build is not allowed to use live sharing.")
        #expect(LiveSession.describe(LiveTransportError.refused(status: 503)) == "The relay refused the connection.")
        #expect(LiveSession.describe(LiveTransportError.closed(code: 1006)) == "The relay refused the connection.")
        #expect(LiveSession.isUnauthorized(LiveTransportError.refused(status: 401)))
        #expect(!LiveSession.isUnauthorized(LiveTransportError.refused(status: 403)))
        #expect(!LiveSession.isUnauthorized(URLError(.userAuthenticationRequired)))
    }

    @Test func theStateRowSaysHowTheConnectionIsDoing() {
        #expect(LiveStateRow.text(.idle) == "Not connected.")
        #expect(LiveStateRow.text(.connecting) == "Connecting.")
        #expect(LiveStateRow.text(.connected) == "Connected, joining the round.")
        #expect(LiveStateRow.text(.subscribed(members: 1)) == "Live. No other phone is connected yet.")
        #expect(LiveStateRow.text(.subscribed(members: 3)) == "Live. 3 phones connected.")
        #expect(LiveStateRow.text(.failed("You seem to be offline. Reconnecting.")) == "You seem to be offline. Reconnecting.")
    }
}
