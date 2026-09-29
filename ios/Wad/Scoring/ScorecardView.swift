import SwiftUI

/// Compact scorecard: one grid per nine, players by holes, with the out, in
/// and total strokes entered so far. Ruled like a paper scorecard, and a score
/// is marked against par the way it is on one (`ScoreNotation`).
struct ScorecardView: View {
    let scorecard: Scorecard

    @ScaledMetric(relativeTo: .caption) private var markSize: CGFloat = 21
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 50

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            nine(Round.frontNine, title: "Out", strokes: \.out, showsTotal: false)
            nine(Round.backNine, title: "In", strokes: \.back, showsTotal: true)
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(Theme.Palette.ink)
    }

    private func nine(
        _ holes: ClosedRange<Int>,
        title: String,
        strokes: KeyPath<Scorecard.Row, Int?>,
        showsTotal: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                label("Hole")
                ForEach(Array(holes), id: \.self) { cell("\($0)") }
                cell(title.uppercased())
                    .font(.caption2)
                cell(showsTotal ? "TOT" : "")
                    .font(.caption2)
            }
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Palette.onGreen)
            .background(Theme.Palette.deepGreen)
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                label("Par")
                ForEach(Array(holes), id: \.self) { cell(scorecard.pars[$0].map(String.init) ?? "") }
                cell("\(scorecard.par(on: holes))")
                    .fontWeight(.semibold)
                cell(showsTotal ? "\(scorecard.par(on: Round.frontNine) + scorecard.par(on: Round.backNine))" : "")
                    .fontWeight(.semibold)
            }
            .background(Theme.Palette.fairway.opacity(0.14))
            .accessibilityElement(children: .combine)

            ForEach(scorecard.rows) { row in
                Theme.Palette.rule.frame(height: 1)
                HStack(spacing: 0) {
                    label(row.name)
                        .fontWeight(.semibold)
                    ForEach(Array(holes), id: \.self) { hole in
                        cell(row.gross[hole].map(String.init) ?? "-", notation: notation(row, hole: hole))
                    }
                    summary(row[keyPath: strokes].map(String.init) ?? "-")
                    summary(showsTotal ? (row.total.map(String.init) ?? "-") : "")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scorecard.\(title).\(row.name)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.rule, lineWidth: 1)
        }
    }

    private func notation(_ row: Scorecard.Row, hole: Int) -> ScoreNotation? {
        guard let gross = row.gross[hole], let par = scorecard.pars[hole] else { return nil }
        return ScoreNotation(gross: gross, par: par)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.leading, Theme.Spacing.s)
            .frame(width: min(labelWidth, 84), alignment: .leading)
            .padding(.vertical, 7)
    }

    private func cell(_ text: String, notation: ScoreNotation? = nil) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if let notation {
                    ScoreMark(notation: notation, lineWidth: 1, gap: 1.5)
                        .frame(width: min(markSize, 28), height: min(markSize, 28))
                }
            }
    }

    /// Out, in and total: what the row adds up to.
    private func summary(_ text: String) -> some View {
        cell(text)
            .fontWeight(.bold)
            .background(Theme.Palette.fairway.opacity(0.14))
    }
}
