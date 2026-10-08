import Foundation
import Observation

/// The phone's part in a live round: sharing the one it scores, or following
/// another phone's code. One per app, in the environment next to
/// `EventCenter`, and one of the two at a time. Sharing relays what
/// `EventCenter` newly records; following plays what arrives through
/// `EventCenter`, wherever the follower is in the app, and keeps the feed.
@Observable
@MainActor
final class LiveCenter {
    enum Role: Equatable, Sendable {
        case sharing, following
    }

    let session: LiveSession
    private(set) var role: Role?
    @ObservationIgnored private let events: EventCenter

    init(
        configuration: LiveConfiguration = .fromBundle,
        events: EventCenter,
        transport: any LiveTransport = URLSessionLiveTransport(),
        sleep: @escaping LiveSession.Sleep = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.events = events
        session = LiveSession(configuration: configuration, transport: transport, sleep: sleep, now: now)
        session.onGameEvent = { [weak self] event in self?.received(event) }
    }

    /// False in a build without `WAD_LIVE_URL`: nothing is offered and
    /// nothing connects.
    var isConfigured: Bool { session.configuration.isConfigured }
    var code: String? { session.code }
    var state: LiveSession.State { session.state }
    var feed: [LiveSession.Received] { session.feed }

    /// Whether the round with this code is the one being shared.
    func isSharing(_ code: String?) -> Bool {
        guard let code, role == .sharing else { return false }
        return session.code == code
    }

    /// Shares the round scored on this phone: every event it newly records
    /// and every score change go to the phones following the code. The shows
    /// play there, not here, until `stop`.
    func share(code: String) {
        guard isConfigured, LiveCode.isValid(code) else { return }
        stop()
        role = .sharing
        events.relay = { [weak self] events in self?.publish(events) }
        events.relayScores = { [weak self] changes in self?.publish(changes) }
        session.start(code: code)
    }

    /// Follows the phone scoring under the code: its events play here.
    func follow(code: String) {
        guard isConfigured, LiveCode.isValid(code) else { return }
        stop()
        role = .following
        session.start(code: code)
    }

    func stop() {
        events.relay = nil
        events.relayScores = nil
        role = nil
        session.stop()
    }

    /// The app is back on screen; the connection is made again if it was lost.
    func didReturnToForeground() {
        session.resume()
    }

    private func publish(_ newEvents: [GameEvent]) {
        for event in newEvents {
            session.publish(.gameEvent(LiveGameEventPayload(event)))
        }
    }

    private func publish(_ changes: [ScoreChange]) {
        for change in changes {
            session.publish(.score(LiveScorePayload(
                playerID: change.playerID,
                playerName: change.playerName,
                hole: change.hole,
                par: change.par,
                gross: change.gross
            )))
        }
    }

    /// An event from the scoring phone: the same show as there. Never relayed
    /// back, since only `EventCenter.record` relays. A follower with the shows
    /// switched off keeps the feed only.
    private func received(_ event: GameEvent) {
        guard role == .following, events.isEnabled else { return }
        events.enqueue([event])
    }
}

/// What a received message says in the feed.
enum LiveFeedText {
    struct Line: Equatable, Sendable {
        var title: String
        var detail: String
    }

    /// Nil for a message this build does not know, which the feed leaves out.
    static func line(_ payload: LivePayload) -> Line? {
        switch payload {
        case .gameEvent(let payload):
            guard let event = payload.gameEvent else { return nil }
            return Line(title: EventText.title(event), detail: EventText.subtitle(event))
        case .score(let score):
            if let gross = score.gross {
                return Line(
                    title: "\(score.playerName): \(gross) on hole \(score.hole)",
                    detail: "\(ScoreNotation.name(gross: gross, par: score.par)), par \(score.par)"
                )
            }
            return Line(title: "\(score.playerName): score cleared on hole \(score.hole)", detail: "Par \(score.par)")
        case .unknown:
            return nil
        }
    }
}
