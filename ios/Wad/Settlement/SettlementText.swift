import Foundation

/// Wording of the settlement. Amounts are integer cents formatted by `Money`.
enum SettlementText {
    /// "+$45.00", "-$20.00" or "$0.00".
    static func signed(_ cents: Int) -> String {
        let amount = "$" + Money.dollars(fromCents: abs(cents))
        if cents > 0 { return "+" + amount }
        return cents < 0 ? "-" + amount : amount
    }

    /// "Won $20.00", "Owes $19.00" or "Even".
    static func position(_ cents: Int) -> String {
        let amount = "$" + Money.dollars(fromCents: abs(cents))
        if cents > 0 { return "Won " + amount }
        return cents < 0 ? "Owes " + amount : "Even"
    }

    static func payment(_ payment: RoundSettlement.Payment) -> String {
        "\(payment.fromName) pays \(payment.toName) \(ScoringText.dollars(payment.amountCents))"
    }

    /// A player's result per game, in one line.
    static func games(_ player: RoundSettlement.PlayerResult) -> String {
        "\(player.name): Skins \(signed(player.skinsCents)), Wad \(signed(player.wadCents)), "
            + "Greenies \(signed(player.greeniesCents))"
    }

    static func holes(_ holes: [Int]) -> String {
        (holes.count == 1 ? "hole " : "holes ") + holes.map(String.init).joined(separator: ", ")
    }

    static func status(_ settlement: RoundSettlement) -> StatusLine {
        let count = settlement.holeNumbers.count
        guard !settlement.isFinal else {
            return StatusLine(title: "Final", detail: "All \(count) holes are scored.")
        }
        if settlement.incompleteHoles.isEmpty {
            // Every score is in; Wolf holds the settlement back.
            return StatusLine(
                title: "Provisional, Wolf unfinished",
                detail: "Not final: \(WolfText.unfinished(settlement.unscoredWolfHoles, name: settlement.name)) "
                    + "The amounts change until every Wolf hole is scored.",
                isWarning: true
            )
        }
        let completed = settlement.completedHoleCount
        let progress = if completed == 0 {
            "no holes scored"
        } else if settlement.isScoredInOrder {
            "through \(completed) \(completed == 1 ? "hole" : "holes")"
        } else {
            "\(completed) of \(count) holes scored"
        }
        return StatusLine(
            title: "Provisional, \(progress)",
            detail: "Not final: scores are missing on \(holes(settlement.incompleteHoles)). "
                + "The amounts change as holes are scored. The Wad is collected only when its nine is finished.",
            isWarning: true
        )
    }

    static func paymentsHeader(_ settlement: RoundSettlement) -> String {
        settlement.isFinal ? "Who pays whom" : "Who would pay whom (provisional)"
    }

    static func noPayments(_ settlement: RoundSettlement) -> String {
        settlement.isFinal ? "Nobody owes anything" : "Nobody owes anything so far"
    }

    static func unresolvedCarryover(cents: Int, lastHole: Int) -> StatusLine {
        StatusLine(
            title: "\(ScoringText.dollars(cents)) skins carryover is unresolved",
            detail: "Hole \(lastHole) was pushed. This amount is NOT paid out and is not in any total. "
                + "It is awaiting a rules decision.",
            isWarning: true
        )
    }

    static func unpaidGreenie(_ result: Engine.GreenieHoleResult, name: (String) -> String) -> StatusLine {
        let winner = result.winnerUserId.map(name) ?? "-"
        let reason = result.status == .pending
            ? "\(winner) has no score on the hole"
            : "\(winner) did not score par or better"
        return StatusLine(
            title: "Hole \(result.hole) greenie is not paid",
            detail: "\(reason). Tap to fix it on hole \(result.hole).",
            isWarning: true
        )
    }

    static func wadMake(_ make: Engine.WadMake, name: (String) -> String) -> String {
        "Hole \(make.hole): \(name(make.userId)) holds at \(ScoringText.dollars(make.valueCents))"
    }
}
