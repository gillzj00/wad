import Foundation

/// Wording of the Wolf engine's results. The points come from the engine's
/// output; nothing is worked out here.
enum WolfText {
    static func points(_ points: Int) -> String {
        points == 1 ? "1 point" : "\(points) points"
    }

    /// "Zach", "Zach and Sam", "Zach, Sam and Alex".
    static func list(_ ids: [String], name: (String) -> String) -> String {
        let names = ids.map(name)
        guard names.count > 1 else { return names.first ?? "-" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// "Zach, Sam, Alex, Jo".
    static func teeOrder(_ ids: [String], name: (String) -> String) -> String {
        ids.map(name).joined(separator: ", ")
    }

    /// "Zach 6, Sam 5, Alex 1, Jo 5", in tee order.
    static func standings(_ points: [String: Int], order: [String], name: (String) -> String) -> String {
        order.map { "\(name($0)) \(points[$0] ?? 0)" }.joined(separator: ", ")
    }

    static func hole(_ result: Engine.WolfHoleResult, name: (String) -> String) -> StatusLine {
        let wolf = result.wolfUserId.map(name) ?? "-"
        let partner = result.partnerUserId.map(name)
        /// The Wolf's side as the group recorded it: "Zach and Sam" or "Lone Wolf Zach".
        let side = result.choice == .lone ? "Lone Wolf \(wolf)" : partner.map { "\(wolf) and \($0)" } ?? wolf
        /// The points one winner got, from the engine.
        let each = result.points.values.max() ?? 0

        switch result.status {
        case .pending:
            guard result.wolfUserId != nil else {
                return StatusLine(
                    title: "Waiting for earlier holes",
                    detail: "The Wolf is the player in last place on points once every earlier hole is scored."
                )
            }
            guard result.choice != nil else {
                return StatusLine(title: "\(wolf) is the Wolf", detail: "Choose a partner or go Lone Wolf.")
            }
            return StatusLine(title: "\(side) \(result.choice == .lone ? "alone" : "together")", detail: "Waiting for every player's score.")
        case .needsWolf:
            let tied = list(result.lastPlace ?? [], name: name)
            return StatusLine(
                title: "Needs a Wolf",
                detail: "\(tied) are tied for last place. Pick the Wolf among them; the hole scores nothing until then.",
                isWarning: true
            )
        case .tied:
            return StatusLine(
                title: "Tied, no points",
                detail: "\(side) \(net(result.wolfSideNet)) against \(net(result.opponentsNet)). Nothing carries over."
            )
        case .wonByWolfSide:
            let title = result.choice == .lone
                ? "Lone Wolf \(wolf) wins \(points(each))"
                : "\(side) win \(points(each)) each"
            return StatusLine(title: title, detail: "Net best ball \(net(result.wolfSideNet)) against \(net(result.opponentsNet)).")
        case .wonByOpponents:
            let opponents = list(result.opponents ?? [], name: name)
            let title = result.choice == .lone
                ? "Lone Wolf \(wolf) loses: \(points(each)) to each of \(opponents)"
                : "\(opponents) win \(points(each)) each"
            return StatusLine(
                title: title,
                detail: "\(side) lost the net best ball \(net(result.wolfSideNet)) to \(net(result.opponentsNet))."
            )
        case .invalid:
            return StatusLine(
                title: "Not scored: \(invalidReason(result.invalidReason, name: name, result: result))",
                detail: "Correct the record. The hole scores no points until then.",
                isWarning: true
            )
        }
    }

    private static func net(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    static func invalidReason(
        _ reason: Engine.WolfInvalidReason?,
        name: (String) -> String,
        result: Engine.WolfHoleResult
    ) -> String {
        switch reason {
        case .partnerAndLone: "a partner is recorded together with Lone Wolf"
        case .partnerMissing: "the partner choice names no partner"
        case .partnerNotAPlayer: "the partner is not in the round"
        case .wolfNotAPlayer: "the recorded Wolf is not in the round"
        case .partnerIsWolf: "the partner is the Wolf"
        case .wolfContradictsRotation: "the recorded Wolf is not the one the tee order gives"
        case .wolfNotInLastPlace:
            "the recorded Wolf is not in last place"
                + (result.lastPlace.map { " (\(list($0, name: name)) \($0.count == 1 ? "is" : "are"))" } ?? "")
        case nil: "the record breaks a rule"
        }
    }

    /// Why the settlement is not final, for `unscoredWolfHoles`.
    static func unfinished(_ holes: [Engine.WolfHoleResult], name: (String) -> String) -> String {
        let reasons = holes.map { hole -> String in
            switch hole.status {
            case .needsWolf:
                "hole \(hole.hole) needs a Wolf (\(list(hole.lastPlace ?? [], name: name)) are tied for last place)"
            case .invalid:
                "hole \(hole.hole) is not scored: \(invalidReason(hole.invalidReason, name: name, result: hole))"
            default:
                "the Wolf's choice is missing on hole \(hole.hole)"
            }
        }
        guard !reasons.isEmpty else { return "Wolf is not finished." }
        return "Wolf: " + reasons.joined(separator: "; ") + "."
    }

    /// A row of the settlement's list of what needs fixing.
    static func needsFixing(_ hole: Engine.WolfHoleResult, name: (String) -> String) -> StatusLine {
        let reason = switch hole.status {
        case .needsWolf: "\(list(hole.lastPlace ?? [], name: name)) are tied for last place; pick the Wolf"
        case .invalid: invalidReason(hole.invalidReason, name: name, result: hole)
        default: "the Wolf's choice is missing"
        }
        return StatusLine(
            title: "Hole \(hole.hole) Wolf is not scored",
            detail: "\(reason.prefix(1).uppercased() + reason.dropFirst()). Tap to fix it on hole \(hole.hole).",
            isWarning: true
        )
    }

    static let unavailable = StatusLine(
        title: "Wolf needs exactly four players",
        detail: "The round does not have four players, so Wolf is not scored and is not part of the settlement.",
        isWarning: true
    )

    /// "6 points, +$7.00".
    static func result(points: Int, cents: Int) -> String {
        "\(Self.points(points)), \(SettlementText.signed(cents))"
    }

    static func pointValue(_ cents: Int) -> String {
        "\(ScoringText.dollars(cents)) a point. Every pair of players settles the difference in their points."
    }
}
