import SwiftData
import SwiftUI

/// A round: the way into scoring, its progress and scorecard, and its setup
/// (course, players with the handicaps and ticks they play with, game amounts).
struct RoundDetailView: View {
    let round: Round

    @State private var handleEdit: VenmoHandleEdit?
    @State private var scoreEdit: ScoreEdit?

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
                header(scorecard)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Group {
                Section {
                    NavigationLink(value: RoundsRoute.scoring(round)) {
                        Label(
                            scorecard.completedHoleCount == 0 ? "Score round" : "Continue scoring",
                            systemImage: "pencil.and.list.clipboard"
                        )
                        .font(.headline)
                    }
                    .accessibilityIdentifier("detail.scoreRound")
                    LabeledContent(
                        "Holes completed",
                        value: "\(scorecard.completedHoleCount) of \(scorecard.holeCount)"
                    )
                    .accessibilityIdentifier("detail.holesCompleted")
                    NavigationLink(value: RoundsRoute.settlement(round)) {
                        Label(
                            scorecard.completedHoleCount == scorecard.holeCount ? "Settlement" : "Settlement (provisional)",
                            systemImage: "dollarsign.circle"
                        )
                    }
                    .accessibilityIdentifier("detail.settlement")
                } header: {
                    SectionHeader("Round", systemImage: "flag.fill")
                }

                Section {
                    ScorecardView(scorecard: scorecard) { playerID, hole in
                        scoreEdit = ScoreEdit(playerID: playerID, hole: hole)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                } header: {
                    SectionHeader("Scorecard", systemImage: "tablecells")
                } footer: {
                    SectionFooter("A circle is a birdie and two an eagle or better. A square is a bogey and two a double bogey or worse. Tap a score to change it.")
                }

                Section {
                    LabeledContent("Name", value: round.courseName)
                    LabeledContent("Holes", value: "\(round.holes.count)")
                    LabeledContent("Par", value: "\(round.totalPar)")
                    if let tee = round.engineTeeRating {
                        LabeledContent("Rating / slope", value: "\(SetupText.display(handicapIndex: tee.courseRating)) / \(tee.slope)")
                    }
                } header: {
                    SectionHeader("Course", systemImage: "map")
                }

                Section {
                    ForEach(round.orderedPlayers) { player in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.displayName)
                                if let index = player.handicapIndex {
                                    Text("Index \(SetupText.display(handicapIndex: index))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.ash)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Course handicap \(SetupText.display(courseHandicap: player.courseHandicap))")
                                Text(ticksText(totalTicks?[player.playerID]))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.ash)
                            }
                            .monospacedDigit()
                        }
                        Button {
                            handleEdit = VenmoHandleEdit(playerID: player.playerID, name: player.displayName)
                        } label: {
                            Label(
                                player.venmoHandle.map { "Venmo \(VenmoHandle.display($0))" }
                                    ?? "Add \(player.displayName)'s Venmo handle",
                                systemImage: "at"
                            )
                            .font(.subheadline)
                        }
                        .accessibilityIdentifier("detail.venmoHandle.\(player.displayName)")
                    }
                } header: {
                    SectionHeader("Players", systemImage: "person.2.fill")
                } footer: {
                    if totalTicks == nil {
                        SectionFooter("Ticks could not be computed.")
                    } else {
                        SectionFooter("Ticks are strokes received relative to the lowest course handicap in the group.")
                    }
                }

                Section {
                    LabeledContent("Wad start", value: "$" + Money.dollars(fromCents: round.wadStartCents))
                    LabeledContent("Wad step", value: "$" + Money.dollars(fromCents: round.wadStepCents))
                    LabeledContent("Skins, per skin", value: "$" + Money.dollars(fromCents: round.skinsBaseCents))
                    LabeledContent("Skins carryover", value: round.skinsCarryover ? "On" : "Off")
                    LabeledContent("Greenies, per greenie", value: "$" + Money.dollars(fromCents: round.greeniesAmountCents))
                    if let pointCents = round.wolfPointCents {
                        LabeledContent("Wolf, per point", value: "$" + Money.dollars(fromCents: pointCents))
                            .accessibilityIdentifier("detail.wolfPoint")
                        LabeledContent(
                            "Wolf tee order",
                            value: round.wolfTeeOrder.map { id in
                                round.players.first { $0.playerID == id }?.displayName ?? "-"
                            }.joined(separator: ", ")
                        )
                        .accessibilityIdentifier("detail.wolfTeeOrder")
                    }
                } header: {
                    SectionHeader("Games", systemImage: "dollarsign.circle")
                }

                LiveShareSection(round: round)
            }
            .themedRows()
        }
        .labeledContentStyle(ThemedLabeledContentStyle())
        .themedList()
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $handleEdit) { edit in
            VenmoHandleEditor(round: round, edit: edit)
        }
        .sheet(item: $scoreEdit) { edit in
            ScoreEditSheet(round: round, edit: edit)
        }
    }

    /// The course, the day and how far the round is.
    private func header(_ scorecard: Scorecard) -> some View {
        Card(emphasized: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(round.courseName)
                    .font(Theme.Typography.display)
                Text(RoundHistoryRow.date(round.startedAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.bone.opacity(0.85))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.s) { facts(scorecard) }
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) { facts(scorecard) }
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func facts(_ scorecard: Scorecard) -> some View {
        StatPill(text: "Par \(round.totalPar)", tone: .bone)
        StatPill(text: "\(round.players.count) players", systemImage: "person.2.fill", tone: .bone)
        StatPill(
            text: "\(scorecard.completedHoleCount) of \(scorecard.holeCount) holes",
            systemImage: "flag.fill",
            tone: .bone
        )
    }

    private func ticksText(_ ticks: Int?) -> String {
        guard let ticks else { return "-" }
        return ticks == 1 ? "1 tick" : "\(ticks) ticks"
    }
}
