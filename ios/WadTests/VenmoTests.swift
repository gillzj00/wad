import Foundation
import Testing
@testable import Wad

struct VenmoHandleTests {
    @Test(arguments: [
        ("zach-g", "zach-g"),
        ("@zach-g", "zach-g"),
        ("  @Sam_Golfs  ", "Sam_Golfs"),
        ("12345", "12345"),
        ("a-b_c", "a-b_c"),
        (String(repeating: "a", count: 30), String(repeating: "a", count: 30)),
    ])
    func acceptsAHandleAndStoresItWithoutTheAt(text: String, handle: String) {
        #expect(VenmoHandle.parse(text) == .valid(handle))
        #expect(VenmoHandle.normalized(text) == handle)
    }

    @Test(arguments: [
        "abcd",
        "@abcd",
        String(repeating: "a", count: 31),
        "@@zach-g",
        "zach g",
        "zach.g",
        "zach@g",
        "zach-g!",
        "zäch-g",
        "zach/golf",
        "zach&amount=1",
        "@",
    ])
    func rejectsAnythingElse(text: String) {
        #expect(VenmoHandle.parse(text) == .invalid)
        #expect(VenmoHandle.normalized(text) == nil)
    }

    @Test(arguments: ["", "   ", "\n"])
    func nothingTypedMeansNoHandle(text: String) {
        #expect(VenmoHandle.parse(text) == VenmoHandle.Parsed.none)
        #expect(VenmoHandle.normalized(text) == nil)
    }

    @Test func onlyOneLeadingAtIsStripped() {
        #expect(VenmoHandle.parse("@zach-@") == .invalid)
        #expect(VenmoHandle.display("zach-g") == "@zach-g")
    }
}

struct VenmoLinkTests {
    @Test func payGoesToThePayeeAndRequestIsACharge() throws {
        let pay = try #require(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: 2800, note: "Wad"))
        #expect(pay.absoluteString == "venmo://paycharge?txn=pay&recipients=zach-golf&amount=28.00&note=Wad")

        let request = try #require(VenmoLink.appURL(kind: .request, recipient: "sam_golfs", amountCents: 2800, note: "Wad"))
        #expect(request.absoluteString == "venmo://paycharge?txn=charge&recipients=sam_golfs&amount=28.00&note=Wad")
    }

    @Test(arguments: [
        (1, "0.01"),
        (5, "0.05"),
        (100, "1.00"),
        (2800, "28.00"),
        (12345, "123.45"),
        (6700, "67.00"),
        (999_999, "9999.99"),
    ])
    func theAmountIsDollarsAndCentsFromIntegerCents(cents: Int, text: String) throws {
        let url = try #require(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: cents, note: "Wad"))
        #expect(queryItems(url)["amount"] == text)
        #expect(url.absoluteString.contains("&amount=\(text)&"))
    }

    @Test func theNoteIsPercentEncoded() throws {
        let note = "Wad: Tom & Jerry's + 50% = \"fun\"? #1 Sep 26"
        let url = try #require(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: 100, note: note))
        #expect(url.absoluteString == "venmo://paycharge?txn=pay&recipients=zach-golf&amount=1.00"
            + "&note=Wad%3A%20Tom%20%26%20Jerry%27s%20%2B%2050%25%20%3D%20%22fun%22%3F%20%231%20Sep%2026")
        // It comes back as typed, and adds no parameter of its own.
        let items = queryItems(url)
        #expect(items["note"] == note)
        #expect(items.count == 4)
    }

    @Test func aNoteCannotChangeTheAmountOrTheRecipient() throws {
        let note = "x&amount=999.00&recipients=someone-else"
        let url = try #require(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: 100, note: note))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.filter { $0.name == "amount" }.map(\.value) == ["1.00"])
        #expect(components.queryItems?.filter { $0.name == "recipients" }.map(\.value) == ["zach-golf"])
    }

    @Test func theNoteIsEncodedAsUTF8() throws {
        let url = try #require(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: 100, note: "Wad: Açaí"))
        #expect(url.absoluteString.hasSuffix("&note=Wad%3A%20A%C3%A7a%C3%AD"))
    }

    @Test func theWebLinkHasTheRecipientInThePath() throws {
        let pay = try #require(
            VenmoLink.webURL(kind: .pay, recipient: "zach-golf", amountCents: 12345, note: "Wad: Pebble Beach Sep 26")
        )
        #expect(pay.absoluteString
            == "https://venmo.com/zach-golf?txn=pay&amount=123.45&note=Wad%3A%20Pebble%20Beach%20Sep%2026")
        let request = try #require(VenmoLink.webURL(kind: .request, recipient: "sam_golfs", amountCents: 100, note: "Wad"))
        #expect(request.absoluteString == "https://venmo.com/sam_golfs?txn=charge&amount=1.00&note=Wad")
    }

    @Test func thereIsNoLinkWithoutAValidHandleOrAnAmount() {
        #expect(VenmoLink.appURL(kind: .pay, recipient: "", amountCents: 100, note: "Wad") == nil)
        #expect(VenmoLink.appURL(kind: .pay, recipient: "a/b?c=d", amountCents: 100, note: "Wad") == nil)
        #expect(VenmoLink.webURL(kind: .pay, recipient: "../x", amountCents: 100, note: "Wad") == nil)
        #expect(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: 0, note: "Wad") == nil)
        #expect(VenmoLink.appURL(kind: .pay, recipient: "zach-golf", amountCents: -100, note: "Wad") == nil)
    }

    @Test func theNoteNamesTheCourseAndTheDay() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        // 2026-09-26 12:00:00 UTC
        let date = Date(timeIntervalSince1970: 1_790_424_000)
        #expect(VenmoLink.note(courseName: "Pebble Beach", date: date, timeZone: utc) == "Wad: Pebble Beach Sep 26")
        #expect(VenmoLink.note(courseName: "  Pebble Beach ", date: date, timeZone: utc) == "Wad: Pebble Beach Sep 26")

        let long = String(repeating: "Long ", count: 20)
        let note = VenmoLink.note(courseName: long, date: date, timeZone: utc)
        #expect(note == "Wad: " + long.prefix(40) + " Sep 26")
        #expect(note.count <= 52)
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

@MainActor
struct VenmoHandleSetupTests {
    @Test func aDraftTakesAnOptionalHandlePerPlayer() throws {
        var draft = RoundFixtures.threePlayerDraft()
        draft.players[0].venmoHandleText = "@zach-golf"
        draft.players[1].venmoHandleText = "  "
        #expect(draft.playerIssues().isEmpty)

        let round = try draft.makeRound(using: EngineBridge())
        #expect(round.orderedPlayers.map(\.venmoHandle) == ["zach-golf", nil, nil])
    }

    @Test func anInvalidHandleIsAnIssueOfThePlayersStep() {
        var draft = RoundFixtures.threePlayerDraft()
        draft.players[1].venmoHandleText = "sam"
        #expect(draft.playerIssues() == [.venmoHandleInvalid(player: 2)])
        #expect(SetupIssue.venmoHandleInvalid(player: 2).message
            == "Player 2: the Venmo handle is 5 to 30 letters, digits, hyphens or underscores, or blank.")
    }
}
