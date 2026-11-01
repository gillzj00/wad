import SwiftData
import SwiftUI

/// Who is in Skins, Wad and Greenies, and the skins carryover, for a round
/// that exists: before the first score, during the round or when settling up.
/// Nothing changes until Done; taking a player out of a game first lists what
/// of theirs is removed. Saving plays no show: shows come only from score changes.
struct GamesEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let round: Round

    @State private var games: RoundGames
    @State private var pendingRemovals: [GamesRemoval] = []
    @State private var failure: String?

    init(round: Round) {
        self.round = round
        _games = State(initialValue: RoundGames(round: round))
    }

    private var editor: RoundGamesEditor { RoundGamesEditor(round: round) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Carry pushed holes over", isOn: $games.skinsCarryover)
                        .accessibilityIdentifier("games.skinsCarryover")
                    whosIn(.skins)
                } header: {
                    SectionHeader("Skins", systemImage: "dollarsign.circle")
                } footer: {
                    footer(.skins, "The whole round is rescored with the carryover as set here.")
                }

                Section {
                    whosIn(.wad)
                } header: {
                    SectionHeader("Wad", systemImage: "banknote")
                } footer: {
                    footer(.wad, "A player taken out loses their Wad makes in this round.")
                }

                Section {
                    whosIn(.greenies)
                } header: {
                    SectionHeader("Greenies", systemImage: "flag.fill")
                } footer: {
                    footer(.greenies, "A player taken out loses their greenies in this round.")
                }
            }
            .themedRows()
            .themedList()
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("games.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                        .accessibilityIdentifier("games.done")
                }
            }
            .alert(
                "Remove recorded results?",
                isPresented: Binding { !pendingRemovals.isEmpty } set: { if !$0 { pendingRemovals = [] } }
            ) {
                Button("Remove and save", role: .destructive, action: save)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pendingRemovals.map(\.sentence).joined(separator: "\n"))
            }
            .alert("Could not save", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
                Button("OK") {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func whosIn(_ game: SideGame) -> some View {
        WhosInRow(
            entries: games.players.map { WhosInRow.Entry(id: $0.id, name: $0.name, isIn: $0.plays(game)) },
            scope: "games",
            game: game
        ) { id in
            guard let index = games.players.firstIndex(where: { $0.id == id }) else { return }
            games.players[index].setPlays(game, !games.players[index].plays(game))
        }
    }

    @ViewBuilder
    private func footer(_ game: SideGame, _ text: String) -> some View {
        SectionFooter(games.isPlayed(game) ? text : SetupText.notPlayedDetail)
    }

    private func done() {
        guard games != RoundGames(round: round) else {
            dismiss()
            return
        }
        let removals = editor.removals(for: games)
        if removals.isEmpty {
            save()
        } else {
            pendingRemovals = removals
        }
    }

    private func save() {
        do {
            try editor.apply(games)
            dismiss()
        } catch {
            failure = String(describing: error)
        }
    }
}
