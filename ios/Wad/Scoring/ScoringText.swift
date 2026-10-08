import Foundation

/// A game's status on the scoring screen: a headline and the detail under it.
struct StatusLine: Equatable, Sendable {
    var title: String
    var detail: String?
    /// Something the group has to fix; shown as a warning.
    var isWarning = false
}

/// Wording of the engine results. Amounts are integer cents formatted by `Money`.
enum ScoringText {
    static func dollars(_ cents: Int) -> String {
        "$" + Money.dollars(fromCents: cents)
    }

    static func ticks(_ ticks: Int) -> String {
        switch ticks {
        case 0: "No ticks"
        case 1: "1 tick"
        default: "\(ticks) ticks"
        }
    }

    /// `carryover` is the round's skins setting. Off, a push pays nothing and
    /// nothing is ever carried in, so the wording says nothing about carrying.
    static func skins(
        _ result: Engine.SkinHoleResult, lastHole: Int, carryover: Bool, name: (String) -> String
    ) -> StatusLine {
        guard let carriedIn = result.carriedInCents, let atStake = result.atStakeCents else {
            return StatusLine(
                title: "Waiting for earlier holes",
                detail: "The amount at stake is known once every earlier hole is scored."
            )
        }
        let carried: String? = carryover ? (carriedIn > 0 ? "\(dollars(carriedIn)) carried in." : "Nothing carried in.") : nil

        switch result.status {
        case .pending:
            return StatusLine(
                title: "\(dollars(atStake)) at stake",
                detail: sentences(carried, "Waiting for every player's score.")
            )
        case .won:
            let winner = result.winnerUserId.map(name) ?? "-"
            return StatusLine(
                title: "\(winner) wins \(dollars(atStake)) from each other player",
                detail: sentences("\(dollars(atStake)) at stake.", carried)
            )
        case .pushed:
            let isLast = result.hole >= lastHole
            let next: String? = if !carryover {
                isLast ? nil : "Hole \(result.hole + 1) is worth \(dollars(atStake)) again."
            } else if isLast {
                "Last hole: \(dollars(atStake)) is unresolved and is not paid out."
            } else {
                "\(dollars(atStake)) carries to hole \(result.hole + 1)."
            }
            return StatusLine(
                title: "Pushed",
                detail: sentences(carryover ? carried : "Carryover is off: nothing is paid.", next)
            )
        }
    }

    private static func sentences(_ parts: String?...) -> String {
        parts.compactMap { $0 }.joined(separator: " ")
    }

    static func wad(
        _ instance: Engine.WadInstanceResult,
        makesOnHole: [Engine.WadMake],
        name: (String) -> String
    ) -> StatusLine {
        let nine = instance.segment == .front ? "Front nine" : "Back nine"
        let lastHole = instance.segment == .front ? 9 : 18
        let title: String
        var detail: String
        if let holder = instance.holderUserId {
            title = "\(name(holder)) holds the Wad at \(dollars(instance.valueCents))"
            detail = instance.complete
                ? "\(nine), finished: collected from each other player."
                : "\(nine). Collected from each other player after hole \(lastHole)."
        } else {
            title = "Nobody holds the Wad"
            detail = instance.complete
                ? "\(nine), finished: nothing is owed."
                : "\(nine). The first make takes it at \(dollars(instance.valueCents))."
        }
        if !makesOnHole.isEmpty {
            let makes = makesOnHole.map { "\(name($0.userId)) \(dollars($0.valueCents))" }.joined(separator: ", ")
            detail += " This hole: \(makes)."
        }
        return StatusLine(title: title, detail: detail)
    }

    static func greenie(_ result: Engine.GreenieHoleResult, amountCents: Int, name: (String) -> String) -> StatusLine {
        let winner = result.winnerUserId.map(name) ?? "-"
        switch result.status {
        case .none:
            return StatusLine(title: "No greenie", detail: "Worth \(dollars(amountCents)) from each other player.")
        case .awarded:
            return StatusLine(
                title: "\(winner) wins the greenie",
                detail: "\(dollars(amountCents)) from each other player."
            )
        case .pending:
            return StatusLine(
                title: "\(winner) is recorded, but has no score",
                detail: "Nothing is paid until \(winner) has a score of par or better on this hole.",
                isWarning: true
            )
        case .invalid:
            return StatusLine(
                title: "Not paid: \(winner) did not score par or better",
                detail: "Choose another winner or none, or correct the score.",
                isWarning: true
            )
        }
    }
}
