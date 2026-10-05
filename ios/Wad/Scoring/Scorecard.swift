import Foundation

extension Round {
    static let frontNine = 1...9
    static let backNine = 10...18

    /// Every player has a gross score on the hole.
    func isHoleComplete(_ hole: Int) -> Bool {
        !players.isEmpty && players.allSatisfy { gross(playerID: $0.playerID, hole: hole) != nil }
    }

    var completedHoles: [Int] {
        orderedHoles.map(\.number).filter(isHoleComplete)
    }

    /// The hole to resume scoring on. Nil when every hole is complete.
    var firstIncompleteHole: Int? {
        orderedHoles.map(\.number).first { !isHoleComplete($0) }
    }
}

/// Gross scores, players by holes, with the strokes entered so far added up.
struct Scorecard: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        var playerID: String
        var name: String
        /// Gross score by hole number.
        var gross: [Int: Int]

        var id: String { playerID }

        /// Strokes entered on the holes, nil when there are none.
        func strokes(on holes: ClosedRange<Int>) -> Int? {
            let entered = holes.compactMap { gross[$0] }
            return entered.isEmpty ? nil : entered.reduce(0, +)
        }

        var out: Int? { strokes(on: Round.frontNine) }
        var back: Int? { strokes(on: Round.backNine) }
        var total: Int? { strokes(on: Round.frontNine.lowerBound...Round.backNine.upperBound) }

        /// The row read out: the name, each hole's score or "-", the strokes
        /// on the nine and, with `showsTotal`, the total.
        func readout(on holes: ClosedRange<Int>, showsTotal: Bool) -> String {
            var parts = [name] + holes.map { gross[$0].map(String.init) ?? "-" }
            parts.append(strokes(on: holes).map(String.init) ?? "-")
            if showsTotal {
                parts.append(total.map(String.init) ?? "-")
            }
            return parts.joined(separator: ", ")
        }
    }

    /// Par by hole number.
    var pars: [Int: Int]
    var rows: [Row]
    var completedHoleCount: Int
    var holeCount: Int

    @MainActor
    init(round: Round) {
        pars = Dictionary(round.holes.map { ($0.number, $0.par) }, uniquingKeysWith: { first, _ in first })
        rows = round.orderedPlayers.map { player in
            let scores = round.scores.filter { $0.playerID == player.playerID }
            return Row(
                playerID: player.playerID,
                name: player.displayName,
                gross: Dictionary(scores.map { ($0.hole, $0.gross) }, uniquingKeysWith: { first, _ in first })
            )
        }
        completedHoleCount = round.completedHoles.count
        holeCount = round.holes.count
    }

    func par(on holes: ClosedRange<Int>) -> Int {
        holes.compactMap { pars[$0] }.reduce(0, +)
    }

    /// A score that can be changed from the scorecard: a player of the round
    /// on a hole of the round. The out, in and total columns add up and are not.
    func isEditable(playerID: String, hole: Int) -> Bool {
        pars[hole] != nil && rows.contains { $0.playerID == playerID }
    }
}
