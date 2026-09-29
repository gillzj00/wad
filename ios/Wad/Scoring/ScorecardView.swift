import SwiftUI

/// Compact scorecard: one grid per nine, players by holes, with the out, in
/// and total strokes entered so far.
struct ScorecardView: View {
    let scorecard: Scorecard

    var body: some View {
        VStack(spacing: 14) {
            nine(Round.frontNine, title: "Out", strokes: \.out, showsTotal: false)
            nine(Round.backNine, title: "In", strokes: \.back, showsTotal: true)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func nine(
        _ holes: ClosedRange<Int>,
        title: String,
        strokes: KeyPath<Scorecard.Row, Int?>,
        showsTotal: Bool
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                label("Hole")
                ForEach(Array(holes), id: \.self) { cell("\($0)") }
                cell(title)
                cell(showsTotal ? "Tot" : "")
            }
            .fontWeight(.semibold)

            HStack(spacing: 0) {
                label("Par")
                ForEach(Array(holes), id: \.self) { cell(scorecard.pars[$0].map(String.init) ?? "") }
                cell("\(scorecard.par(on: holes))")
                cell(showsTotal ? "\(scorecard.par(on: Round.frontNine) + scorecard.par(on: Round.backNine))" : "")
            }
            .foregroundStyle(.secondary)

            Divider()

            ForEach(scorecard.rows) { row in
                HStack(spacing: 0) {
                    label(row.name)
                    ForEach(Array(holes), id: \.self) { cell(row.gross[$0].map(String.init) ?? "-") }
                    cell(row[keyPath: strokes].map(String.init) ?? "-")
                        .fontWeight(.semibold)
                    cell(showsTotal ? (row.total.map(String.init) ?? "-") : "")
                        .fontWeight(.semibold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scorecard.\(title).\(row.name)")
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .frame(width: 50, alignment: .leading)
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }
}
