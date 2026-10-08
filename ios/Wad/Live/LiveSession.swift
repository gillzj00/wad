import Foundation
import Observation

/// One room of the relay: connects, subscribes to the code, publishes and
/// hands over what the other phones send. Reconnects with backoff (1, 2, 4,
/// up to 30 s) and subscribes again after a drop, pings every 30 s while
/// connected, and drops a publish while not subscribed: the events are only
/// worth showing live. No UI in here; `LiveCenter` and the screens read it.
@Observable
@MainActor
final class LiveSession {
    enum State: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case subscribed(members: Int)
        /// Between attempts, with why the last one ended.
        case failed(String)

        var isSubscribed: Bool {
            if case .subscribed = self { return true }
            return false
        }
    }

    /// A message another phone sent, as the feed shows it.
    struct Received: Identifiable, Equatable, Sendable {
        let id: UUID
        let receivedAt: Date
        let payload: LivePayload
    }

    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let pingInterval = Duration.seconds(30)
    static let backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    static let feedLimit = 200

    private(set) var state = State.idle
    private(set) var code: String?
    /// Newest first, at most `feedLimit`.
    private(set) var feed: [Received] = []
    /// Called with every game event another phone sends.
    @ObservationIgnored var onGameEvent: ((GameEvent) -> Void)?

    let configuration: LiveConfiguration
    @ObservationIgnored private let transport: any LiveTransport
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var connection: (any LiveConnection)?
    /// The last send, so that the frames leave in the order they were published.
    @ObservationIgnored private var outbox: Task<Void, Never>?
    /// Bumped by every start and stop; a run whose number is stale ends and
    /// its late frames are ignored.
    @ObservationIgnored private var generation = 0

    init(
        configuration: LiveConfiguration,
        transport: any LiveTransport = URLSessionLiveTransport(),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sleep = sleep
        self.now = now
    }

    var isRunning: Bool { run != nil }

    /// Connects and subscribes to the code; does nothing without the relay
    /// settings. The feed is kept when the code is the same (a reconnect).
    func start(code: String) {
        let sameCode = code == self.code
        stop()
        guard configuration.isConfigured, let url = configuration.url else { return }
        self.code = code
        if !sameCode {
            feed.removeAll()
        }
        state = .connecting
        generation += 1
        let generation = generation
        let headers = configuration.headers
        run = Task { [weak self] in
            await self?.loop(url: url, headers: headers, code: code, generation: generation)
        }
    }

    /// Closes the connection; frames that still arrive are ignored.
    func stop() {
        generation += 1
        run?.cancel()
        run = nil
        connection?.close()
        connection = nil
        code = nil
        state = .idle
    }

    /// Drops the message unless subscribed, so nothing stale is sent later.
    func publish(_ payload: LivePayload) {
        guard state.isSubscribed, let code, let connection else { return }
        guard let text = try? LiveFrameCoding.encode(.publish(roundCode: code, message: payload)), LiveFrameCoding.fits(text) else {
            return
        }
        send(text, over: connection)
    }

    /// After the sends before it; a failure shows up on the receiving side.
    private func send(_ text: String, over connection: any LiveConnection) {
        let previous = outbox
        outbox = Task {
            await previous?.value
            try? await connection.send(text)
        }
    }

    /// The app is back in the foreground: a connection that was suspended
    /// with it is dropped and made again, and a wait between attempts is cut short.
    func resume() {
        guard let code, isRunning else { return }
        start(code: code)
    }

    // MARK: The connection

    private func loop(url: URL, headers: [String: String], code: String, generation: Int) async {
        var attempt = 0
        while !Task.isCancelled, isCurrent(generation) {
            state = .connecting
            let reason: String
            var retries = true
            do {
                let connection = try await transport.connect(url: url, headers: headers)
                guard isCurrent(generation) else {
                    connection.close()
                    return
                }
                self.connection = connection
                state = .connected
                attempt = 0
                try await connection.send(try LiveFrameCoding.encode(.subscribe(roundCode: code)))
                let pinger = Task { [sleep] in
                    while !Task.isCancelled {
                        try await sleep(Self.pingInterval)
                        try await connection.send(try LiveFrameCoding.encode(.ping))
                    }
                }
                defer { pinger.cancel() }
                for try await text in connection.frames() {
                    guard isCurrent(generation) else { return }
                    handle(text, code: code)
                }
                reason = "The connection closed."
            } catch is CancellationError {
                return
            } catch {
                reason = Self.describe(error)
                // Without the token no attempt will do better.
                retries = !Self.isUnauthorized(error)
            }
            guard isCurrent(generation), !Task.isCancelled else { return }
            connection?.close()
            connection = nil
            state = .failed(retries ? "\(reason) Reconnecting." : reason)
            guard retries else {
                run = nil
                return
            }
            let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
            attempt += 1
            do {
                try await sleep(delay)
            } catch {
                return
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }

    private func handle(_ text: String, code: String) {
        guard let frame = try? LiveFrameCoding.decode(text) else { return }
        switch frame {
        case .subscribed(_, let members):
            state = .subscribed(members: members)
        case .published(_, let delivered):
            // The relay counts the phones it delivered to: everybody but this one.
            state = .subscribed(members: delivered + 1)
        case .message(_, let payload, _):
            // A type or a kind from a newer build is left out.
            guard payload.isKnown else { return }
            feed.insert(Received(id: UUID(), receivedAt: now(), payload: payload), at: 0)
            if feed.count > Self.feedLimit {
                feed.removeLast(feed.count - Self.feedLimit)
            }
            if case .gameEvent(let event) = payload, let gameEvent = event.gameEvent {
                onGameEvent?(gameEvent)
            }
        case .pong:
            break
        case .error(let errorCode):
            // The relay forgot the subscription (a new connection id): subscribe again.
            if errorCode == "not_subscribed", let connection, let text = try? LiveFrameCoding.encode(.subscribe(roundCode: code)) {
                send(text, over: connection)
            }
        }
    }

    static func isUnauthorized(_ error: Error) -> Bool {
        if case LiveTransportError.refused(let status) = error, status == 401 { return true }
        return false
    }

    /// What the state shows between attempts; the token is never in it.
    static func describe(_ error: Error) -> String {
        switch error {
        case LiveTransportError.refused(let status) where status == 401:
            return "This build is not allowed to use live sharing."
        case LiveTransportError.refused, LiveTransportError.closed:
            return "The relay refused the connection."
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
                return "You seem to be offline."
            default:
                return "The connection dropped."
            }
        default:
            return "The connection dropped."
        }
    }
}
