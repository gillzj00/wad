import SwiftUI

/// Wolf on the settlement screen: each player's points and what they come to
/// at the value per point, then the result of every hole. All from the engine.
struct WolfSettlementSections: View {
    let settlement: RoundSettlement

    var body: some View {
        if let wolf = settlement.wolf {
            Section {
                ForEach(wolf.teeOrder, id: \.self) { playerID in
                    let points = wolf.points[playerID] ?? 0
                    let cents = wolf.deltas[playerID] ?? 0
                    HStack {
                        Text(settlement.name(playerID))
                            .font(.body.weight(.medium))
                        Spacer(minLength: Theme.Spacing.s)
                        Text(WolfText.points(points))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.ash)
                        MoneyLabel(
                            text: SettlementText.signed(cents),
                            cents: cents,
                            font: .system(.body, design: .rounded, weight: .semibold)
                        )
                        .frame(minWidth: 80, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(settlement.name(playerID)): \(WolfText.result(points: points, cents: cents))")
                    .accessibilityIdentifier("settlement.wolf.points.\(settlement.name(playerID))")
                }
            } header: {
                SectionHeader("Wolf", systemImage: "pawprint.fill")
            } footer: {
                if let pointCents = settlement.wolfPointCents {
                    SectionFooter(WolfText.pointValue(pointCents) + (wolf.complete ? "" : " Not every hole is scored yet."))
                }
            }

            Section {
                ForEach(wolf.holes, id: \.hole) { hole in
                    HoleLineRow(hole: hole.hole, line: WolfText.hole(hole, name: settlement.name))
                        .accessibilityIdentifier("settlement.wolf.\(hole.hole)")
                }
            } header: {
                SectionHeader("Wolf, hole by hole", systemImage: "pawprint.fill")
            }
        } else if settlement.isWolfUnavailable {
            Section {
                StatusLineView(line: WolfText.unavailable)
                    .accessibilityIdentifier("settlement.wolf.unavailable")
            } header: {
                SectionHeader("Wolf", systemImage: "pawprint.fill")
            }
        }
    }
}

/// The Wolf holes that keep the settlement from being final, each a way to
/// the hole to fix it. For the settlement's list of what needs fixing.
struct WolfNeedsFixingRows: View {
    let round: Round
    let settlement: RoundSettlement

    var body: some View {
        ForEach(settlement.unscoredWolfHoles, id: \.hole) { hole in
            NavigationLink(value: RoundsRoute.scoringHole(round, hole.hole)) {
                StatusLineView(line: WolfText.needsFixing(hole, name: settlement.name))
            }
            .accessibilityIdentifier("settlement.fix.wolf.\(hole.hole)")
        }
    }
}
