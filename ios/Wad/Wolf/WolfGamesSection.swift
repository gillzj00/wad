import SwiftUI

/// Wolf in the games step of the setup flow: on or off, the value of a point
/// and the tee order. The toggle is enabled with exactly four players.
struct WolfGamesSection: View {
    @Binding var draft: RoundDraft

    private var canBePlayed: Bool { WolfDraft.canBePlayed(playerCount: draft.players.count) }

    var body: some View {
        Section {
            Toggle("Wolf", isOn: $draft.wolf.isEnabled)
                .disabled(!canBePlayed && !draft.wolf.isEnabled)
                .accessibilityIdentifier("setup.wolf")
            if draft.wolf.isEnabled {
                AmountRow(title: "Per point", identifier: "setup.amount.wolfPoint", text: $draft.wolf.pointText)
                WolfTeeOrderRows(
                    order: draft.wolf.teeOrder(for: draft.players),
                    name: name,
                    move: { playerID, offset in draft.wolf.move(playerID, by: offset, players: draft.players) }
                )
            }
        } header: {
            SectionHeader("Wolf", systemImage: "pawprint.fill")
        } footer: {
            if canBePlayed {
                SectionFooter(
                    "Four players, 18 holes. The Wolf rotates through the tee order on holes 1 to 16 and is the player "
                        + "in last place on 17 and 18. Every pair settles the difference in their points."
                )
            } else {
                SectionFooter("Wolf is played with exactly 4 players; the round has \(draft.players.count).")
            }
        }
    }

    private func name(_ playerID: String) -> String {
        guard let offset = draft.players.firstIndex(where: { $0.id == playerID }) else { return "-" }
        let name = draft.players[offset].trimmedName
        return name.isEmpty ? "Player \(offset + 1)" : name
    }
}

/// The tee order, one row per player with a place number and arrows to move
/// the player up or down.
struct WolfTeeOrderRows: View {
    let order: [String]
    let name: (String) -> String
    /// Called with the player and -1 (up) or +1 (down).
    let move: (String, Int) -> Void

    var body: some View {
        ForEach(Array(order.enumerated()), id: \.element) { offset, playerID in
            HStack(spacing: Theme.Spacing.m) {
                Text("\(offset + 1)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 24, minHeight: 24)
                    .foregroundStyle(Theme.Palette.crimson)
                    .background(Theme.Palette.bone, in: Circle())
                Text(name(playerID))
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                arrow("chevron.up", enabled: offset > 0, label: "Move \(name(playerID)) up", id: "wolf.teeOrder.up.\(name(playerID))") {
                    move(playerID, -1)
                }
                arrow("chevron.down", enabled: offset < order.count - 1, label: "Move \(name(playerID)) down", id: "wolf.teeOrder.down.\(name(playerID))") {
                    move(playerID, 1)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tee order \(offset + 1): \(name(playerID))")
            .accessibilityIdentifier("wolf.teeOrder.\(offset + 1)")
        }
    }

    private func arrow(_ systemImage: String, enabled: Bool, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(enabled ? Theme.Palette.blood : Theme.Palette.ash)
                .background(Theme.Palette.blood.opacity(enabled ? 0.14 : 0.05), in: Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
