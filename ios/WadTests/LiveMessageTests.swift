import Foundation
import Testing
@testable import Wad

/// The frames and payloads of the relay (the contract in the backend), as
/// JSON and back.
struct LiveMessageTests {
    let birdie = GameEvent(kind: .birdie, hole: 4, playerIDs: ["p1"], playerNames: ["Zach"], otherNames: ["Sam", "Alex"])
    let skin = GameEvent(kind: .skinWon, hole: 9, playerIDs: ["p2"], playerNames: ["Sam"], amountCents: 1500)

    private func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func roundTrip(_ frame: LiveClientFrame) throws -> LiveClientFrame {
        try JSONDecoder().decode(LiveClientFrame.self, from: Data(try LiveFrameCoding.encode(frame).utf8))
    }

    private func roundTrip(_ frame: LiveServerFrame) throws -> LiveServerFrame {
        try LiveFrameCoding.decode(try #require(String(data: JSONEncoder().encode(frame), encoding: .utf8)))
    }

    // MARK: Client frames

    @Test func clientFramesRoundTripAndCarryTheAction() throws {
        let frames: [LiveClientFrame] = [
            .subscribe(roundCode: "ABC123"),
            .publish(roundCode: "ABC123", message: .gameEvent(LiveGameEventPayload(birdie))),
            .publish(roundCode: "ABC123", message: .score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: 3))),
            .ping,
        ]
        for frame in frames {
            #expect(try roundTrip(frame) == frame)
        }
        #expect(try json(LiveFrameCoding.encode(.subscribe(roundCode: "ABC123"))) as NSDictionary == ["action": "subscribe", "roundCode": "ABC123"])
        #expect(try json(LiveFrameCoding.encode(.ping)) as NSDictionary == ["action": "ping"])
        let publish = try json(LiveFrameCoding.encode(.publish(roundCode: "ABC123", message: .gameEvent(LiveGameEventPayload(birdie)))))
        #expect(publish["action"] as? String == "publish")
        #expect(publish["roundCode"] as? String == "ABC123")
        #expect((publish["message"] as? [String: Any])?["type"] as? String == "gameEvent")
    }

    @Test func serverFramesRoundTripAndDecodeAsTheRelaySendsThem() throws {
        let frames: [LiveServerFrame] = [
            .subscribed(roundCode: "ABC123", members: 2),
            .published(roundCode: "ABC123", delivered: 1),
            .message(roundCode: "ABC123", message: .gameEvent(LiveGameEventPayload(skin)), sentAt: "2026-10-05T15:04:05Z"),
            .message(roundCode: "ABC123", message: .score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: nil)), sentAt: ""),
            .pong,
            .error(code: "not_subscribed"),
        ]
        for frame in frames {
            #expect(try roundTrip(frame) == frame)
        }

        #expect(try LiveFrameCoding.decode(#"{"event":"subscribed","roundCode":"ABC123","members":2}"#) == .subscribed(roundCode: "ABC123", members: 2))
        #expect(try LiveFrameCoding.decode(#"{"event":"published","roundCode":"ABC123","delivered":1}"#) == .published(roundCode: "ABC123", delivered: 1))
        #expect(try LiveFrameCoding.decode(#"{"event":"pong"}"#) == .pong)
        #expect(try LiveFrameCoding.decode(#"{"event":"error","code":"invalid_message"}"#) == .error(code: "invalid_message"))
        let message = try LiveFrameCoding.decode(
            #"{"event":"message","roundCode":"ABC123","message":{"type":"gameEvent","kind":"birdie","hole":4,"playerIDs":["p1"],"playerNames":["Zach"],"otherNames":["Sam","Alex"],"amountCents":null},"sentAt":"2026-10-05T15:04:05Z"}"#
        )
        #expect(message == .message(roundCode: "ABC123", message: .gameEvent(LiveGameEventPayload(birdie)), sentAt: "2026-10-05T15:04:05Z"))

        #expect(throws: LiveFrameError.unknownEvent("later")) { try LiveFrameCoding.decode(#"{"event":"later"}"#) }
        #expect(throws: (any Error).self) { try LiveFrameCoding.decode("not json") }
    }

    // MARK: Payloads

    @Test func gameEventPayloadMapsBothWaysWithOtherNamesAndAmount() throws {
        for event in [birdie, skin, GameEvent(kind: .wolfHoleWon, hole: 6, playerIDs: ["p1", "p2"], playerNames: ["Zach", "Sam"])] {
            let payload = LiveGameEventPayload(event)
            #expect(payload.gameEvent == event)
            let data = try JSONEncoder().encode(LivePayload.gameEvent(payload))
            #expect(try JSONDecoder().decode(LivePayload.self, from: data) == .gameEvent(payload))
        }

        let text = try #require(String(data: JSONEncoder().encode(LivePayload.gameEvent(LiveGameEventPayload(birdie))), encoding: .utf8))
        let object = try json(text)
        #expect(object["type"] as? String == "gameEvent")
        #expect(object["kind"] as? String == "birdie")
        #expect(object["hole"] as? Int == 4)
        #expect(object["playerIDs"] as? [String] == ["p1"])
        #expect(object["playerNames"] as? [String] == ["Zach"])
        #expect(object["otherNames"] as? [String] == ["Sam", "Alex"])
        // Written as null, as the contract shows it, and read back as nil.
        #expect(object["amountCents"] is NSNull)
        #expect(text.contains(#""amountCents":null"#))

        let skinObject = try json(try #require(String(data: JSONEncoder().encode(LivePayload.gameEvent(LiveGameEventPayload(skin))), encoding: .utf8)))
        #expect(skinObject["amountCents"] as? Int == 1500)
        #expect(skinObject["otherNames"] as? [String] == [])

        // A payload without otherNames, from an older build.
        let bare = try JSONDecoder().decode(LivePayload.self, from: Data(#"{"type":"gameEvent","kind":"eagle","hole":2,"playerIDs":["p1"],"playerNames":["Zach"]}"#.utf8))
        #expect(bare == .gameEvent(LiveGameEventPayload(kind: "eagle", hole: 2, playerIDs: ["p1"], playerNames: ["Zach"])))
    }

    @Test func everyKindHasANameThatMapsBack() {
        for kind in GameEventKind.allCases {
            #expect(GameEventKind(liveName: kind.liveName) == kind)
        }
        #expect(GameEventKind.holeInOne.liveName == "holeInOne")
        #expect(GameEventKind.wadTaken.liveName == "wadTaken")
        #expect(GameEventKind.skinWon.liveName == "skinWon")
        #expect(GameEventKind.wolfHoleWon.liveName == "wolfHoleWon")
        #expect(GameEventKind(liveName: "chipIn") == nil)
        #expect(LiveGameEventPayload(kind: "chipIn", hole: 1, playerIDs: ["p1"], playerNames: ["Zach"]).gameEvent == nil)
    }

    @Test func scorePayloadRoundTripsWithAClearedScoreAsNull() throws {
        let set = LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: 3)
        let cleared = LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: nil)
        for payload in [set, cleared] {
            let data = try JSONEncoder().encode(LivePayload.score(payload))
            #expect(try JSONDecoder().decode(LivePayload.self, from: data) == .score(payload))
        }
        let text = try #require(String(data: JSONEncoder().encode(LivePayload.score(cleared)), encoding: .utf8))
        #expect(text.contains(#""gross":null"#))
        #expect(try json(text) as NSDictionary == ["type": "score", "playerID": "p1", "playerName": "Zach", "hole": 4, "par": 4, "gross": NSNull()])
        let decoded = try JSONDecoder().decode(LivePayload.self, from: Data(#"{"type":"score","playerID":"p1","playerName":"Zach","hole":4,"par":4,"gross":3}"#.utf8))
        #expect(decoded == .score(set))
    }

    @Test func anUnknownTypeDecodesAsUnknownAndIsLeftOutOfTheFeed() throws {
        let decoded = try JSONDecoder().decode(LivePayload.self, from: Data(#"{"type":"chat","text":"nice putt"}"#.utf8))
        #expect(decoded == .unknown(type: "chat"))
        #expect(LiveFeedText.line(decoded) == nil)
        let frame = try LiveFrameCoding.decode(#"{"event":"message","roundCode":"ABC123","message":{"type":"chat"},"sentAt":"2026-10-05T15:04:05Z"}"#)
        #expect(frame == .message(roundCode: "ABC123", message: .unknown(type: "chat"), sentAt: "2026-10-05T15:04:05Z"))
    }

    @Test func aFrameOverTheLimitDoesNotFit() throws {
        let short = try LiveFrameCoding.encode(.ping)
        #expect(LiveFrameCoding.fits(short))
        let long = String(repeating: "x", count: 4097)
        #expect(!LiveFrameCoding.fits(long))
        #expect(LiveFrameCoding.fits(String(repeating: "x", count: 4096)))
    }

    // MARK: Feed text

    @Test func feedLinesSayWhatHappened() {
        #expect(LiveFeedText.line(.gameEvent(LiveGameEventPayload(birdie))) == LiveFeedText.Line(title: "Birdie", detail: "From Zach to Sam and Alex"))
        #expect(LiveFeedText.line(.gameEvent(LiveGameEventPayload(skin))) == LiveFeedText.Line(title: "Skin", detail: "Sam takes $15.00 a head on hole 9"))
        #expect(LiveFeedText.line(.score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: 3)))
            == LiveFeedText.Line(title: "Zach: 3 on hole 4", detail: "Birdie, par 4"))
        #expect(LiveFeedText.line(.score(LiveScorePayload(playerID: "p1", playerName: "Zach", hole: 4, par: 4, gross: nil)))
            == LiveFeedText.Line(title: "Zach: score cleared on hole 4", detail: "Par 4"))
    }
}

/// The 6-character code and the build settings.
struct LiveCodeTests {
    @Test func generatedCodesHaveSixCharactersOfTheAlphabet() {
        for _ in 0..<50 {
            let code = LiveCode.generate()
            #expect(code.count == 6)
            #expect(code.allSatisfy { LiveCode.alphabet.contains($0) })
            #expect(LiveCode.isValid(code))
        }
        #expect(!LiveCode.alphabet.contains("0"))
        #expect(!LiveCode.alphabet.contains("O"))
        #expect(!LiveCode.alphabet.contains("1"))
        #expect(!LiveCode.alphabet.contains("I"))
        #expect(LiveCode.alphabet.count == 32)
    }

    @Test func generationFollowsTheGenerator() {
        struct Fixed: RandomNumberGenerator {
            mutating func next() -> UInt64 { 0 }
        }
        var generator = Fixed()
        #expect(LiveCode.generate(using: &generator) == "AAAAAA")
    }

    @Test func validationIsSixUppercaseLettersOrDigits() {
        #expect(LiveCode.isValid("ABC123"))
        #expect(LiveCode.isValid("000000"))
        #expect(!LiveCode.isValid("abc123"))
        #expect(!LiveCode.isValid("ABC12"))
        #expect(!LiveCode.isValid("ABC1234"))
        #expect(!LiveCode.isValid("ABC 12"))
        #expect(!LiveCode.isValid("ABC-12"))
        #expect(!LiveCode.isValid(""))
        #expect(!LiveCode.isValid("ÀBC123"))
    }

    @Test func typedInputIsUppercasedAndStripped() {
        #expect(LiveCode.normalize(" abc 123 ") == "ABC123")
        #expect(LiveCode.normalize("ab\tc1\n23") == "ABC123")
        #expect(LiveCode.normalize("") == "")
        #expect(LiveCode.isValid(LiveCode.normalize("abc123")))
    }

    @Test func configurationComesFromTheInfoPlistAndIsEmptyWithoutTheUrl() {
        let configured = LiveConfiguration(info: [
            LiveConfiguration.urlKey: " wss://example.test/dev ",
            CourseLookupConfiguration.clientTokenKey: "secret-token\n",
        ])
        #expect(configured.isConfigured)
        #expect(configured.url?.absoluteString == "wss://example.test/dev")
        #expect(configured.headers == ["x-wad-client": "secret-token"])

        for info: [String: Any] in [
            [:],
            [LiveConfiguration.urlKey: ""],
            [LiveConfiguration.urlKey: "wss://example.test/dev"],
            [CourseLookupConfiguration.clientTokenKey: "secret-token"],
        ] {
            #expect(!LiveConfiguration(info: info).isConfigured)
        }
        #expect(!LiveConfiguration.unconfigured.isConfigured)
    }
}
