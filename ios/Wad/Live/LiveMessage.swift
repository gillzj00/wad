import Foundation

/// What the app sends through the relay. The relay does not read it; the
/// phones on both ends agree on it here. A `type` nobody knows decodes as
/// `.unknown` and is ignored, so an older build keeps up with a newer one.
enum LivePayload: Equatable, Sendable {
    case gameEvent(LiveGameEventPayload)
    case score(LiveScorePayload)
    case unknown(type: String)
}

extension LivePayload {
    /// False for a type, or an event kind, this build does not know.
    var isKnown: Bool {
        switch self {
        case .gameEvent(let payload): payload.gameEvent != nil
        case .score: true
        case .unknown: false
        }
    }
}

/// A `GameEvent` on the wire: `kind` is the `GameEventKind` case name.
struct LiveGameEventPayload: Equatable, Sendable {
    var kind: String
    var hole: Int
    var playerIDs: [String]
    var playerNames: [String]
    var otherNames: [String]
    var amountCents: Int?

    init(_ event: GameEvent) {
        kind = event.kind.liveName
        hole = event.hole
        playerIDs = event.playerIDs
        playerNames = event.playerNames
        otherNames = event.otherNames
        amountCents = event.amountCents
    }

    init(kind: String, hole: Int, playerIDs: [String], playerNames: [String], otherNames: [String] = [], amountCents: Int? = nil) {
        self.kind = kind
        self.hole = hole
        self.playerIDs = playerIDs
        self.playerNames = playerNames
        self.otherNames = otherNames
        self.amountCents = amountCents
    }

    /// Nil for a kind this build does not know.
    var gameEvent: GameEvent? {
        guard let kind = GameEventKind(liveName: kind) else { return nil }
        return GameEvent(
            kind: kind,
            hole: hole,
            playerIDs: playerIDs,
            playerNames: playerNames,
            otherNames: otherNames,
            amountCents: amountCents
        )
    }
}

/// A gross score as it was entered; `gross` nil when it was cleared.
struct LiveScorePayload: Equatable, Sendable {
    var playerID: String
    var playerName: String
    var hole: Int
    var par: Int
    var gross: Int?
}

extension GameEventKind {
    /// The case name, as the payload carries it.
    var liveName: String { "\(self)" }

    init?(liveName: String) {
        guard let kind = Self.allCases.first(where: { $0.liveName == liveName }) else { return nil }
        self = kind
    }
}

/// A frame the phone sends.
enum LiveClientFrame: Equatable, Sendable {
    case subscribe(roundCode: String)
    case publish(roundCode: String, message: LivePayload)
    case ping
}

/// A frame the relay sends.
enum LiveServerFrame: Equatable, Sendable {
    case subscribed(roundCode: String, members: Int)
    case published(roundCode: String, delivered: Int)
    /// A message from another phone in the room.
    case message(roundCode: String, message: LivePayload, sentAt: String)
    case pong
    /// `not_subscribed`, `invalid_message` or `unknown_action`.
    case error(code: String)
}

/// The JSON of the frames and the limit the relay puts on one.
enum LiveFrameCoding {
    /// A frame larger than this is refused by the relay, so it is not sent.
    static let maximumBytes = 4096

    static func encode(_ frame: LiveClientFrame) throws -> String {
        let data = try JSONEncoder().encode(frame)
        guard let text = String(data: data, encoding: .utf8) else { throw LiveFrameError.notText }
        return text
    }

    static func decode(_ text: String) throws -> LiveServerFrame {
        try JSONDecoder().decode(LiveServerFrame.self, from: Data(text.utf8))
    }

    static func fits(_ text: String) -> Bool {
        text.utf8.count <= maximumBytes
    }
}

enum LiveFrameError: Error, Equatable {
    case notText
    case unknownAction(String)
    case unknownEvent(String)
}

// MARK: - Codable

private enum FrameKeys: String, CodingKey {
    case action, event, roundCode, message, members, delivered, sentAt, code
}

private enum PayloadKeys: String, CodingKey {
    case type, kind, hole, playerIDs, playerNames, otherNames, amountCents, playerID, playerName, par, gross
}

extension LivePayload: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PayloadKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "gameEvent":
            self = .gameEvent(try LiveGameEventPayload(from: decoder))
        case "score":
            self = .score(try LiveScorePayload(from: decoder))
        default:
            self = .unknown(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PayloadKeys.self)
        switch self {
        case .gameEvent(let payload):
            try container.encode("gameEvent", forKey: .type)
            try payload.encode(to: encoder)
        case .score(let payload):
            try container.encode("score", forKey: .type)
            try payload.encode(to: encoder)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

extension LiveGameEventPayload: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PayloadKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        hole = try container.decode(Int.self, forKey: .hole)
        playerIDs = try container.decode([String].self, forKey: .playerIDs)
        playerNames = try container.decode([String].self, forKey: .playerNames)
        otherNames = try container.decodeIfPresent([String].self, forKey: .otherNames) ?? []
        amountCents = try container.decodeIfPresent(Int.self, forKey: .amountCents)
    }

    /// `amountCents` is written as null rather than left out, as the contract shows it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PayloadKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(hole, forKey: .hole)
        try container.encode(playerIDs, forKey: .playerIDs)
        try container.encode(playerNames, forKey: .playerNames)
        try container.encode(otherNames, forKey: .otherNames)
        try container.encode(amountCents, forKey: .amountCents)
    }
}

extension LiveScorePayload: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PayloadKeys.self)
        playerID = try container.decode(String.self, forKey: .playerID)
        playerName = try container.decode(String.self, forKey: .playerName)
        hole = try container.decode(Int.self, forKey: .hole)
        par = try container.decode(Int.self, forKey: .par)
        gross = try container.decodeIfPresent(Int.self, forKey: .gross)
    }

    /// `gross` is written as null when the score was cleared.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PayloadKeys.self)
        try container.encode(playerID, forKey: .playerID)
        try container.encode(playerName, forKey: .playerName)
        try container.encode(hole, forKey: .hole)
        try container.encode(par, forKey: .par)
        try container.encode(gross, forKey: .gross)
    }
}

extension LiveClientFrame: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FrameKeys.self)
        let action = try container.decode(String.self, forKey: .action)
        switch action {
        case "subscribe":
            self = .subscribe(roundCode: try container.decode(String.self, forKey: .roundCode))
        case "publish":
            self = .publish(
                roundCode: try container.decode(String.self, forKey: .roundCode),
                message: try container.decode(LivePayload.self, forKey: .message)
            )
        case "ping":
            self = .ping
        default:
            throw LiveFrameError.unknownAction(action)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FrameKeys.self)
        switch self {
        case .subscribe(let roundCode):
            try container.encode("subscribe", forKey: .action)
            try container.encode(roundCode, forKey: .roundCode)
        case .publish(let roundCode, let message):
            try container.encode("publish", forKey: .action)
            try container.encode(roundCode, forKey: .roundCode)
            try container.encode(message, forKey: .message)
        case .ping:
            try container.encode("ping", forKey: .action)
        }
    }
}

extension LiveServerFrame: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FrameKeys.self)
        let event = try container.decode(String.self, forKey: .event)
        switch event {
        case "subscribed":
            self = .subscribed(
                roundCode: try container.decode(String.self, forKey: .roundCode),
                members: try container.decode(Int.self, forKey: .members)
            )
        case "published":
            self = .published(
                roundCode: try container.decode(String.self, forKey: .roundCode),
                delivered: try container.decode(Int.self, forKey: .delivered)
            )
        case "message":
            self = .message(
                roundCode: try container.decode(String.self, forKey: .roundCode),
                message: try container.decode(LivePayload.self, forKey: .message),
                sentAt: try container.decodeIfPresent(String.self, forKey: .sentAt) ?? ""
            )
        case "pong":
            self = .pong
        case "error":
            self = .error(code: try container.decode(String.self, forKey: .code))
        default:
            throw LiveFrameError.unknownEvent(event)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FrameKeys.self)
        switch self {
        case .subscribed(let roundCode, let members):
            try container.encode("subscribed", forKey: .event)
            try container.encode(roundCode, forKey: .roundCode)
            try container.encode(members, forKey: .members)
        case .published(let roundCode, let delivered):
            try container.encode("published", forKey: .event)
            try container.encode(roundCode, forKey: .roundCode)
            try container.encode(delivered, forKey: .delivered)
        case .message(let roundCode, let message, let sentAt):
            try container.encode("message", forKey: .event)
            try container.encode(roundCode, forKey: .roundCode)
            try container.encode(message, forKey: .message)
            try container.encode(sentAt, forKey: .sentAt)
        case .pong:
            try container.encode("pong", forKey: .event)
        case .error(let code):
            try container.encode("error", forKey: .event)
            try container.encode(code, forKey: .code)
        }
    }
}
