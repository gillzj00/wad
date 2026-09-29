import Testing
@testable import Wad

/// The marks of the scorecard: gross against par, for display only.
struct ScoreNotationTests {
    @Test(arguments: [
        // Par 3.
        (1, 3, ScoreNotation.eagleOrBetter),
        (2, 3, .birdie),
        (3, 3, .par),
        (4, 3, .bogey),
        (5, 3, .doubleBogeyOrWorse),
        (6, 3, .doubleBogeyOrWorse),
        // Par 4.
        (1, 4, .eagleOrBetter),
        (2, 4, .eagleOrBetter),
        (3, 4, .birdie),
        (4, 4, .par),
        (5, 4, .bogey),
        (6, 4, .doubleBogeyOrWorse),
        (9, 4, .doubleBogeyOrWorse),
        // Par 5.
        (1, 5, .eagleOrBetter),
        (2, 5, .eagleOrBetter),
        (3, 5, .eagleOrBetter),
        (4, 5, .birdie),
        (5, 5, .par),
        (6, 5, .bogey),
        (7, 5, .doubleBogeyOrWorse),
        (20, 5, .doubleBogeyOrWorse),
    ])
    func marksGrossAgainstPar(gross: Int, par: Int, notation: ScoreNotation) {
        #expect(ScoreNotation(gross: gross, par: par) == notation)
    }

    @Test(arguments: [
        (1, 3, "Hole in one"),
        (1, 4, "Hole in one"),
        (1, 5, "Hole in one"),
        (2, 5, "Albatross"),
        (2, 4, "Eagle"),
        (3, 5, "Eagle"),
        (2, 3, "Birdie"),
        (4, 4, "Par"),
        (6, 5, "Bogey"),
        (5, 3, "Double bogey"),
        (7, 4, "Triple bogey"),
        (8, 4, "4 over par"),
        (20, 5, "15 over par"),
    ])
    func namesTheScore(gross: Int, par: Int, name: String) {
        #expect(ScoreNotation.name(gross: gross, par: par) == name)
    }

    /// A hole in one is marked like an eagle or better, on a par 3 too.
    @Test(arguments: [3, 4, 5])
    func aHoleInOneHasTheDoubleCircle(par: Int) {
        #expect(ScoreNotation(gross: 1, par: par) == .eagleOrBetter)
    }
}
