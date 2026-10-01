import SwiftUI

/// Wolf on the scoring screen: who the Wolf is, the choice (a partner or Lone
/// Wolf), the hole's result and the running points. On holes 17 and 18 with a
/// tie for last place the group picks the Wolf here. Everything shown comes
/// from the engine through `RoundStatus`.
struct WolfHoleSection: View {
    let round: Round
    let hole: RoundHole
    let status: RoundStatus?
    /// Runs a change and reports a failure to the screen.
    let perform: (() throws -> Void) -> Void

    @State private var editsTeeOrder = false

    private var scorer: RoundScorer { RoundScorer(round: round) }

    private func name(_ playerID: String) -> String {
        round.players.first { $0.playerID == playerID }?.displayName ?? "Unknown player"
    }

    var body: some View {
        Section {
            if let status, let game = status.wolf, let result = status.wolfHole(hole.number) {
                content(WolfHoleModel(result: result, game: game, recordedWolfID: hole.wolfPlayerID, name: name))
            } else {
                StatusLineView(line: status == nil ? StatusLine(title: "Wolf could not be computed") : WolfText.unavailable)
                    .accessibilityIdentifier("status.wolf")
            }
        } header: {
            SectionHeader("Wolf", systemImage: "pawprint.fill")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                SectionFooter("Tee order: \(WolfText.teeOrder(round.wolfTeeOrder, name: name)).")
                if !round.isWolfTeeOrderLocked {
                    Button("Change the tee order") { editsTeeOrder = true }
                        .font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("wolf.teeOrder.change")
                }
            }
        }
        .sheet(isPresented: $editsTeeOrder) {
            WolfTeeOrderSheet(round: round)
        }
    }

    @ViewBuilder
    private func content(_ model: WolfHoleModel) -> some View {
        if !model.tiedForLast.isEmpty {
            tiePrompt(model)
        } else {
            wolfRow(model)
        }

        if model.canChoose {
            choice(model)
        }

        StatusLineView(line: model.line)
            .accessibilityIdentifier("status.wolf")
        if model.hasRefusedWolf {
            Button("Clear the recorded Wolf", role: .destructive) {
                perform { try scorer.setWolf(nil, hole: hole.number) }
            }
            .accessibilityIdentifier("wolf.clearWolf")
        }

        WolfStandingsView(standings: model.standings)
    }

    /// Holes 1 to 16, and 17 and 18 with one player in last place.
    private func wolfRow(_ model: WolfHoleModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("The Wolf")
                .font(Theme.Typography.overline)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.ash)
            Spacer(minLength: Theme.Spacing.s)
            Text(model.wolf?.name ?? "Not known yet")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(model.wolf == nil ? Theme.Palette.ash : Theme.Palette.bone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Wolf: \(model.wolf?.name ?? "not known yet")")
        .accessibilityIdentifier("wolf.wolf")
    }

    /// Holes 17 and 18 with a tie for last place: the group picks the Wolf
    /// among the tied players (Open Question 4 in docs/domain-model.md).
    @ViewBuilder
    private func tiePrompt(_ model: WolfHoleModel) -> some View {
        Text(model.needsWolf ? "Tied for last place: pick the Wolf" : "The Wolf, picked among those tied for last place")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(model.needsWolf ? Theme.Palette.blood : Theme.Palette.bone)
            .accessibilityIdentifier("wolf.tiePrompt")
        ChoiceGrid {
            ForEach(model.tiedForLast) { player in
                ChoiceChip(title: player.name, badge: nil, isSelected: model.recordedWolfID == player.playerID) {
                    let next = model.recordedWolfID == player.playerID ? nil : player.playerID
                    perform { try scorer.setWolf(next, hole: hole.number) }
                }
                .accessibilityIdentifier("wolf.pick.\(player.name)")
                .accessibilityValue(model.recordedWolfID == player.playerID ? "The Wolf" : "Not the Wolf")
            }
        }
    }

    /// One partner, or Lone Wolf. Tapping the selected chip clears the choice.
    private func choice(_ model: WolfHoleModel) -> some View {
        ChoiceGrid {
            ChoiceChip(title: "Lone Wolf", badge: nil, isSelected: model.isLone) {
                perform { try scorer.setWolfChoice(model.isLone ? nil : .lone, hole: hole.number) }
            }
            .accessibilityIdentifier("wolf.choice.lone")
            .accessibilityValue(model.isLone ? "Chosen" : "Not chosen")
            ForEach(model.partnerCandidates) { player in
                let isPartner = model.isPartner(player.playerID)
                ChoiceChip(title: player.name, badge: nil, isSelected: isPartner) {
                    perform { try scorer.setWolfChoice(isPartner ? nil : .partner(player.playerID), hole: hole.number) }
                }
                .accessibilityIdentifier("wolf.choice.\(player.name)")
                .accessibilityValue(isPartner ? "Partner" : "Not the partner")
            }
        }
    }
}

/// The running points of the four players in tee order. The leader is ember,
/// last place (who is the Wolf on 17 and 18) is blood.
struct WolfStandingsView: View {
    let standings: [WolfHoleModel.Standing]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            ForEach(standings) { standing in
                VStack(spacing: 2) {
                    Text("\(standing.points)")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(color(standing))
                    Text(standing.player.name)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Theme.Palette.ash)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Points: " + standings.map { "\($0.player.name) \($0.points)" }.joined(separator: ", "))
        .accessibilityIdentifier("wolf.points")
    }

    private func color(_ standing: WolfHoleModel.Standing) -> Color {
        if standing.isFirst, !standing.isLast { return Theme.Palette.ember }
        if standing.isLast, !standing.isFirst { return Theme.Palette.blood }
        return Theme.Palette.bone
    }
}

/// Reorders the tee order of a round that has no score and no Wolf record yet.
struct WolfTeeOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let round: Round
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WolfTeeOrderRows(order: round.wolfTeeOrder, name: name) { playerID, offset in
                        do {
                            try RoundScorer(round: round).moveWolfTeeOrder(playerID, by: offset)
                        } catch {
                            failure = String(describing: error)
                        }
                    }
                    .themedRows()
                } footer: {
                    SectionFooter("The Wolf is the first player on hole 1, the second on hole 2, and so on through hole 16. Locked once a score is saved.")
                }
            }
            .themedList()
            .navigationTitle("Tee order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("wolf.teeOrder.done")
                }
            }
            .alert("Could not save", isPresented: .constant(failure != nil)) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func name(_ playerID: String) -> String {
        round.players.first { $0.playerID == playerID }?.displayName ?? "Unknown player"
    }
}
