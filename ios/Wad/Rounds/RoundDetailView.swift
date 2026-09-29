import SwiftData
import SwiftUI

/// A round: the way into scoring, its progress and scorecard, and its setup
/// (course, players with the handicaps and ticks they play with, game amounts).
struct RoundDetailView: View {
    let round: Round

    /// Total ticks per player id, from the engine. Nil if the engine failed.
    private var totalTicks: [String: Int]? {
        guard
            let bridge = SharedEngine.bridge,
            let ticks = try? bridge.allocateTicks(players: round.enginePlayers, holes: round.engineHoles)
        else { return nil }
        return ticks.mapValues { $0.values.reduce(0, +) }
    }

    var body: some View {
        let totalTicks = totalTicks
        let scorecard = Scorecard(round: round)
        List {
            Section {
                NavigationLink(value: RoundsRoute.scoring(round)) {
                    Label(
                        scorecard.completedHoleCount == 0 ? "Score round" : "Continue scoring",
                        systemImage: "pencil.and.list.clipboard"
                    )
                }
                .accessibilityIdentifier("detail.scoreRound")
                LabeledContent(
                    "Holes completed",
                    value: "\(scorecard.completedHoleCount) of \(scorecard.holeCount)"
                )
                .accessibilityIdentifier("detail.holesCompleted")
            } header: {
                Text("Round")
            }

            Section("Scorecard") {
                ScorecardView(scorecard: scorecard)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 8))
            }

            Section("Course") {
                LabeledContent("Name", value: round.courseName)
                LabeledContent("Holes", value: "\(round.holes.count)")
                LabeledContent("Par", value: "\(round.totalPar)")
                if let tee = round.engineTeeRating {
                    LabeledContent("Rating / slope", value: "\(SetupText.display(handicapIndex: tee.courseRating)) / \(tee.slope)")
                }
            }

            Section {
                ForEach(round.orderedPlayers) { player in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.displayName)
                            if let index = player.handicapIndex {
                                Text("Index \(SetupText.display(handicapIndex: index))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Course handicap \(SetupText.display(courseHandicap: player.courseHandicap))")
                            Text(ticksText(totalTicks?[player.playerID]))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                }
            } header: {
                Text("Players")
            } footer: {
                if totalTicks == nil {
                    Text("Ticks could not be computed.")
                } else {
                    Text("Ticks are strokes received relative to the lowest course handicap in the group.")
                }
            }

            Section("Games") {
                LabeledContent("Wad start", value: "$" + Money.dollars(fromCents: round.wadStartCents))
                LabeledContent("Wad step", value: "$" + Money.dollars(fromCents: round.wadStepCents))
                LabeledContent("Skins, per skin", value: "$" + Money.dollars(fromCents: round.skinsBaseCents))
                LabeledContent("Greenies, per greenie", value: "$" + Money.dollars(fromCents: round.greeniesAmountCents))
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ticksText(_ ticks: Int?) -> String {
        guard let ticks else { return "-" }
        return ticks == 1 ? "1 tick" : "\(ticks) ticks"
    }
}
