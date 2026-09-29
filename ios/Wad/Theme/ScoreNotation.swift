import SwiftUI

/// How a scorecard marks a gross score against par: a circle for a birdie, two
/// for an eagle or better, a square for a bogey and two for a double bogey or
/// worse. For display only; no game uses it.
enum ScoreNotation: Equatable, Sendable {
    case eagleOrBetter
    case birdie
    case par
    case bogey
    case doubleBogeyOrWorse

    init(gross: Int, par: Int) {
        switch gross - par {
        case ...(-2): self = .eagleOrBetter
        case -1: self = .birdie
        case 0: self = .par
        case 1: self = .bogey
        default: self = .doubleBogeyOrWorse
        }
    }

    /// What golfers call the score: "Birdie", "Double bogey", "3 over par".
    static func name(gross: Int, par: Int) -> String {
        if gross == 1 { return "Hole in one" }
        switch gross - par {
        case ...(-4): return "\(par - gross) under par"
        case -3: return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        case 3: return "Triple bogey"
        default: return "\(gross - par) over par"
        }
    }

    fileprivate var isRound: Bool { self == .birdie || self == .eagleOrBetter }
    fileprivate var isDouble: Bool { self == .eagleOrBetter || self == .doubleBogeyOrWorse }
}

/// The circles or squares of a score, to put behind its number.
struct ScoreMark: View {
    let notation: ScoreNotation
    var lineWidth: CGFloat = 1.5
    /// Between the two outlines of an eagle or a double bogey.
    var gap: CGFloat = 2.5

    private var color: Color {
        notation.isRound ? Theme.Palette.flagRed : Theme.Palette.ink
    }

    var body: some View {
        if notation != .par {
            ZStack {
                outline
                if notation.isDouble {
                    outline.padding(lineWidth + gap)
                }
            }
            .foregroundStyle(color)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var outline: some View {
        if notation.isRound {
            Circle().strokeBorder(lineWidth: lineWidth)
        } else {
            Rectangle().strokeBorder(lineWidth: lineWidth)
        }
    }
}
