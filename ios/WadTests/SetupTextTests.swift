import Testing
@testable import Wad

struct SetupTextTests {
    @Test(arguments: [
        ("7", 700),
        ("7.5", 750),
        ("7.50", 750),
        ("7.05", 705),
        ("0", 0),
        ("0.01", 1),
        ("0.5", 50),
        ("12.34", 1234),
        ("007", 700),
        ("9999.99", 999_999),
        ("$7.50", 750),
        (" 7.50 ", 750),
    ])
    func parsesDollarsToCents(text: String, cents: Int) {
        #expect(Money.cents(fromDollars: text) == cents)
    }

    @Test(arguments: [
        "", " ", "$", ".", "7.", ".5", "7.505", "7.5.0", "-7", "-7.50", "+7", "7,50", "1,000",
        "abc", "7a", "7.5a", "1e3", "0x10", "7 50", "10000", "٧", "NaN",
    ])
    func rejectsTextThatIsNotDollarsAndCents(text: String) {
        #expect(Money.cents(fromDollars: text) == nil)
    }

    @Test(arguments: [(700, "7.00"), (750, "7.50"), (705, "7.05"), (0, "0.00"), (5, "0.05"), (123_456, "1234.56"), (-1350, "-13.50")])
    func formatsCentsAsDollars(cents: Int, text: String) {
        #expect(Money.dollars(fromCents: cents) == text)
    }

    @Test func formattedDefaultsParseBack() {
        for cents in [700, 200, 500, 1, 99, 100, 999_999] {
            #expect(Money.cents(fromDollars: Money.dollars(fromCents: cents)) == cents)
        }
    }

    @Test func parsesHandicapIndex() {
        #expect(SetupText.handicapIndex("15.4") == 15.4)
        #expect(SetupText.handicapIndex("7") == 7)
        #expect(SetupText.handicapIndex("0.0") == 0)
        #expect(SetupText.handicapIndex("54.0") == 54)
        #expect(SetupText.handicapIndex("+1.2") == -1.2)

        for text in ["", "+", "54.1", "15.45", "-2", "abc", "15.", "1e1"] {
            #expect(SetupText.handicapIndex(text) == nil, "\(text)")
        }
    }

    @Test func parsesCourseHandicapAsWholeNumber() {
        #expect(SetupText.courseHandicap("15") == 15)
        #expect(SetupText.courseHandicap("0") == 0)
        #expect(SetupText.courseHandicap(" 7 ") == 7)
        #expect(SetupText.courseHandicap("+3") == -3)
        #expect(SetupText.courseHandicap("-3") == -3)

        for text in ["", "15.0", "15.5", "abc", "+", "100", "1 5"] {
            #expect(SetupText.courseHandicap(text) == nil, "\(text)")
        }
    }

    @Test func displaysPlusHandicaps() {
        #expect(SetupText.display(courseHandicap: 15) == "15")
        #expect(SetupText.display(courseHandicap: -3) == "+3")
        #expect(SetupText.display(handicapIndex: 15.4) == "15.4")
        #expect(SetupText.display(handicapIndex: 7) == "7.0")
        #expect(SetupText.display(handicapIndex: -1.2) == "+1.2")
    }
}
