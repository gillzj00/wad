import SwiftData
import SwiftUI

/// The score the scorecard opens for editing.
struct ScoreEdit: Identifiable, Hashable {
    var playerID: String
    var hole: Int

    var id: String { "\(playerID).\(hole)" }
}

/// One player's gross score on one hole, with the scoring screen's controls.
/// Every tap is saved straight away, as on the scoring screen.
struct ScoreEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EventCenter.self) private var events

    let round: Round
    let edit: ScoreEdit

    @State private var failure: String?

    private var scorer: RoundScorer { RoundScorer(round: round) }

    var body: some View {
        let status = SharedEngine.bridge.flatMap { try? RoundStatus(round: round, bridge: $0) }
        NavigationStack {
            List {
                if let hole = round.hole(edit.hole),
                   let player = round.players.first(where: { $0.playerID == edit.playerID }) {
                    Section {
                        HoleHeader(number: hole.number, par: hole.par, strokeIndex: hole.strokeIndex)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                    Section {
                        PlayerScoreRow(
                            name: player.displayName,
                            par: hole.par,
                            gross: round.gross(playerID: player.playerID, hole: hole.number),
                            ticks: status?.ticks(playerID: player.playerID, hole: hole.number),
                            net: status?.net(playerID: player.playerID, hole: hole.number),
                            onStep: { delta in
                                perform { try scorer.stepGross(by: delta, playerID: player.playerID, hole: hole.number) }
                            },
                            onClear: {
                                perform { try scorer.setGross(nil, playerID: player.playerID, hole: hole.number) }
                            }
                        )
                    } header: {
                        SectionHeader("Score", systemImage: "pencil.and.list.clipboard")
                    }
                    .themedRows()
                }
            }
            .listSectionSpacing(.compact)
            .themedList()
            .navigationTitle("Edit score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("scoreEdit.done")
                }
            }
            .alert("Could not save", isPresented: .constant(failure != nil)) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
        .accessibilityIdentifier("scoreEdit.sheet")
        .presentationDetents([.medium])
    }

    /// Saves a change and plays what it newly triggered: the games are scored
    /// before and after, and only an event that was not there before plays.
    private func perform(_ change: () throws -> Void) {
        let before = events.snapshot(of: round)
        do {
            try change()
        } catch {
            failure = String(describing: error)
            return
        }
        events.record(round, before: before)
    }
}
