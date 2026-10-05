import SwiftUI

/// Compact scorecard: one grid per nine, players by holes, with the out, in
/// and total strokes entered so far. Ruled like a paper scorecard, and a score
/// is marked against par the way it is on one (`ScoreNotation`). With
/// `onEditScore` each score is a button; the sums never are.
struct ScorecardView: View {
    let scorecard: Scorecard
    var onEditScore: ((_ playerID: String, _ hole: Int) -> Void)? = nil

    @ScaledMetric(relativeTo: .caption) private var markSize: CGFloat = 21
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 50

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            nine(Round.frontNine, title: "Out", strokes: \.out, showsTotal: false)
            nine(Round.backNine, title: "In", strokes: \.back, showsTotal: true)
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(Theme.Palette.bone)
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
            .foregroundStyle(Theme.Palette.bone)
            .background(Theme.Palette.maroon)
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                label("Par")
                ForEach(Array(holes), id: \.self) { cell(scorecard.pars[$0].map(String.init) ?? "") }
                cell("\(scorecard.par(on: holes))")
                    .fontWeight(.semibold)
                cell(showsTotal ? "\(scorecard.par(on: Round.frontNine) + scorecard.par(on: Round.backNine))" : "")
                    .fontWeight(.semibold)
            }
            .background(Theme.Palette.crimson.opacity(0.3))
            .accessibilityElement(children: .combine)

            ForEach(scorecard.rows) { row in
                Theme.Palette.rule.frame(height: 1)
                playerRow(row, holes: holes, title: title, strokes: strokes, showsTotal: showsTotal)
                    .accessibilityIdentifier("scorecard.\(title).\(row.name)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.rule, lineWidth: 1)
        }
    }

    /// Read-only, the row is one element that reads its scores. With scores to
    /// edit it contains them as buttons, and reads the same as a whole.
    @ViewBuilder
    private func playerRow(
        _ row: Scorecard.Row,
        holes: ClosedRange<Int>,
        title: String,
        strokes: KeyPath<Scorecard.Row, Int?>,
        showsTotal: Bool
    ) -> some View {
        let content = HStack(spacing: 0) {
            label(row.name)
                .fontWeight(.semibold)
            ForEach(Array(holes), id: \.self) { hole in
                score(row, hole: hole)
            }
            summary(row[keyPath: strokes].map(String.init) ?? "-", title: title)
            summary(showsTotal ? (row.total.map(String.init) ?? "-") : "", title: "Total")
        }
        if onEditScore == nil {
            content
                .accessibilityElement(children: .combine)
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(row.readout(on: holes, showsTotal: showsTotal))
        }
    }

    @ViewBuilder
    private func score(_ row: Scorecard.Row, hole: Int) -> some View {
        let text = row.gross[hole].map(String.init) ?? "-"
        if let onEditScore, scorecard.isEditable(playerID: row.playerID, hole: hole) {
            Button {
                onEditScore(row.playerID, hole)
            } label: {
                cell(text, notation: notation(row, hole: hole))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Score of \(row.name) on hole \(hole)")
            .accessibilityValue(row.gross[hole].map(String.init) ?? "Not set")
            .accessibilityIdentifier("scorecard.cell.\(row.name).\(hole)")
        } else {
            cell(text, notation: notation(row, hole: hole))
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
    private func summary(_ text: String, title: String) -> some View {
        cell(text)
            .fontWeight(.bold)
            .background(Theme.Palette.crimson.opacity(0.3))
            .accessibilityLabel(text.isEmpty ? "" : "\(title) \(text)")
            .accessibilityHidden(text.isEmpty)
    }
}
