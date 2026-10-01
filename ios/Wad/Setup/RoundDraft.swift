import Foundation

/// Something the group has to fix before the setup flow can move on.
enum SetupIssue: Hashable, Sendable {
    case courseNameMissing
    case ratingAndSlopeNotTogether
    case ratingInvalid
    case slopeOutOfRange
    case parOutOfRange(hole: Int)
    case strokeIndexMissing(holes: [Int])
    case strokeIndexOutOfRange(hole: Int)
    case strokeIndexDuplicate(strokeIndex: Int, holes: [Int])
    case playerCount
    case playerNameMissing(player: Int)
    case playerNameDuplicate(name: String)
    case handicapIndexInvalid(player: Int)
    case courseHandicapInvalid(player: Int)
    case venmoHandleInvalid(player: Int)
    case amountInvalid(game: String)

    var message: String {
        switch self {
        case .courseNameMissing:
            "Enter the course name."
        case .ratingAndSlopeNotTogether:
            "Enter both the rating and the slope, or leave both blank."
        case .ratingInvalid:
            "The rating is a number such as 72.5."
        case .slopeOutOfRange:
            "The slope is a whole number from 55 to 155."
        case .parOutOfRange(let hole):
            "Hole \(hole): par is 3, 4 or 5."
        case .strokeIndexMissing(let holes):
            "Stroke index missing on \(Self.list(holes))."
        case .strokeIndexOutOfRange(let hole):
            "Hole \(hole): stroke index is 1 to 18."
        case .strokeIndexDuplicate(let strokeIndex, let holes):
            "Stroke index \(strokeIndex) is used on \(Self.list(holes))."
        case .playerCount:
            "A round has 2 to 4 players."
        case .playerNameMissing(let player):
            "Player \(player): enter a name."
        case .playerNameDuplicate(let name):
            "More than one player is named \(name)."
        case .handicapIndexInvalid(let player):
            "Player \(player): the handicap index is a number up to 54.0, such as 15.4 (or +1.2)."
        case .courseHandicapInvalid(let player):
            "Player \(player): the course handicap is a whole number."
        case .venmoHandleInvalid(let player):
            "Player \(player): the Venmo handle is 5 to 30 letters, digits, hyphens or underscores, or blank."
        case .amountInvalid(let game):
            "\(game): enter dollars and cents, such as 7 or 7.50."
        }
    }

    private static func list(_ holes: [Int]) -> String {
        (holes.count == 1 ? "hole " : "holes ") + holes.map(String.init).joined(separator: ", ")
    }
}

enum SetupError: Error, Equatable {
    case invalid([SetupIssue])
}

/// The setup flow's working copy: what has been typed so far, as text. It is
/// validated step by step and turned into a `Round` at the end.
struct RoundDraft: Equatable, Sendable {
    static let holeCount = 18
    static let playerCountRange = 2...4
    static let parRange = 3...5
    static let slopeRange = 55...155

    struct Hole: Equatable, Identifiable, Sendable {
        let number: Int
        var par = 4
        var strokeIndexText = ""

        var id: Int { number }
        var strokeIndex: Int? { SetupText.digits(strokeIndexText.trimmingCharacters(in: .whitespaces)) }
    }

    struct Player: Equatable, Identifiable, Sendable {
        /// Becomes the player's stable id in the round.
        var id = UUID().uuidString
        var name = ""
        var handicapIndexText = ""
        var courseHandicapText = ""
        /// With a rated tee: use `courseHandicapText` instead of the computed course handicap.
        var overridesCourseHandicap = false
        /// Optional. With or without the leading "@".
        var venmoHandleText = ""

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var courseName = ""
    var ratingText = ""
    var slopeText = ""
    var holes = (1...RoundDraft.holeCount).map { Hole(number: $0) }
    /// The looked-up course and tee the fields above were filled from, if any.
    var course: CourseSelection?

    var players = [Player(), Player()]

    var wadStartText = Money.dollars(fromCents: GameSettings.defaults.wadStartCents)
    var wadStepText = Money.dollars(fromCents: GameSettings.defaults.wadStepCents)
    var skinsBaseText = Money.dollars(fromCents: GameSettings.defaults.skinsBaseCents)
    var greeniesAmountText = Money.dollars(fromCents: GameSettings.defaults.greeniesAmountCents)

    /// Save par for every player on every hole when the round is created, so
    /// that scoring is changing the holes that went differently.
    var startsEveryHoleAtPar = true

    // MARK: Course

    var trimmedCourseName: String { courseName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var totalPar: Int { holes.reduce(0) { $0 + $1.par } }

    private var hasRatingText: Bool { !ratingText.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasSlopeText: Bool { !slopeText.trimmingCharacters(in: .whitespaces).isEmpty }
    private var rating: Double? { SetupText.oneDecimal(ratingText).flatMap { $0 > 0 ? $0 : nil } }
    private var slope: Int? {
        SetupText.digits(slopeText.trimmingCharacters(in: .whitespaces)).flatMap { Self.slopeRange.contains($0) ? $0 : nil }
    }

    /// The tee's rating when a valid rating and slope have been entered.
    var tee: Engine.TeeRating? {
        guard let rating, let slope else { return nil }
        return Engine.TeeRating(slope: slope, courseRating: rating, par: totalPar)
    }

    func courseIssues() -> [SetupIssue] {
        var issues: [SetupIssue] = []
        if trimmedCourseName.isEmpty { issues.append(.courseNameMissing) }

        if hasRatingText != hasSlopeText {
            issues.append(.ratingAndSlopeNotTogether)
        } else if hasRatingText {
            if rating == nil { issues.append(.ratingInvalid) }
            if slope == nil { issues.append(.slopeOutOfRange) }
        }

        if holes.map(\.number) != Array(1...Self.holeCount) {
            // The editor cannot produce this; it guards the 18-hole assumption.
            issues.append(.strokeIndexMissing(holes: Array(1...Self.holeCount)))
            return issues
        }

        for hole in holes where !Self.parRange.contains(hole.par) {
            issues.append(.parOutOfRange(hole: hole.number))
        }

        let missing = holes.filter { $0.strokeIndexText.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.number)
        if !missing.isEmpty { issues.append(.strokeIndexMissing(holes: missing)) }

        var holesByStrokeIndex: [Int: [Int]] = [:]
        for hole in holes where !missing.contains(hole.number) {
            guard let strokeIndex = hole.strokeIndex, (1...Self.holeCount).contains(strokeIndex) else {
                issues.append(.strokeIndexOutOfRange(hole: hole.number))
                continue
            }
            holesByStrokeIndex[strokeIndex, default: []].append(hole.number)
        }
        for (strokeIndex, holes) in holesByStrokeIndex.sorted(by: { $0.key < $1.key }) where holes.count > 1 {
            issues.append(.strokeIndexDuplicate(strokeIndex: strokeIndex, holes: holes))
        }
        return issues
    }

    /// Stroke indexes not used by any hole yet, ascending.
    var unusedStrokeIndexes: [Int] {
        let used = Set(holes.compactMap(\.strokeIndex))
        return (1...Self.holeCount).filter { !used.contains($0) }
    }

    // MARK: Players

    /// Whether this player's course handicap is typed in rather than computed from the index.
    func entersCourseHandicapDirectly(_ player: Player) -> Bool {
        tee == nil || player.overridesCourseHandicap
    }

    func playerIssues() -> [SetupIssue] {
        var issues: [SetupIssue] = []
        if !Self.playerCountRange.contains(players.count) { issues.append(.playerCount) }

        var seen: [String: Int] = [:]
        for (offset, player) in players.enumerated() {
            let number = offset + 1
            if player.trimmedName.isEmpty {
                issues.append(.playerNameMissing(player: number))
            } else {
                let key = player.trimmedName.lowercased()
                seen[key, default: 0] += 1
                if seen[key] == 2 { issues.append(.playerNameDuplicate(name: player.trimmedName)) }
            }

            if entersCourseHandicapDirectly(player) {
                if SetupText.courseHandicap(player.courseHandicapText) == nil {
                    issues.append(.courseHandicapInvalid(player: number))
                }
            } else if SetupText.handicapIndex(player.handicapIndexText) == nil {
                issues.append(.handicapIndexInvalid(player: number))
            }

            if VenmoHandle.parse(player.venmoHandleText) == .invalid {
                issues.append(.venmoHandleInvalid(player: number))
            }
        }
        return issues
    }

    /// The course handicap computed by the engine from the player's index and the
    /// tee. Nil without a rated tee or a valid index.
    func computedCourseHandicap(for player: Player, using bridge: EngineBridge) throws -> Int? {
        guard let tee, let index = SetupText.handicapIndex(player.handicapIndexText) else { return nil }
        return try bridge.courseHandicap(handicapIndex: index, tee: tee)
    }

    /// The course handicap the player will play the round with.
    func courseHandicap(for player: Player, using bridge: EngineBridge) throws -> Int? {
        if entersCourseHandicapDirectly(player) {
            return SetupText.courseHandicap(player.courseHandicapText)
        }
        return try computedCourseHandicap(for: player, using: bridge)
    }

    // MARK: Games

    var settings: GameSettings? {
        guard
            let wadStart = Money.cents(fromDollars: wadStartText),
            let wadStep = Money.cents(fromDollars: wadStepText),
            let skinsBase = Money.cents(fromDollars: skinsBaseText),
            let greenies = Money.cents(fromDollars: greeniesAmountText)
        else { return nil }
        return GameSettings(
            wadStartCents: wadStart,
            wadStepCents: wadStep,
            skinsBaseCents: skinsBase,
            greeniesAmountCents: greenies
        )
    }

    func gameIssues() -> [SetupIssue] {
        [
            ("Wad start", wadStartText),
            ("Wad step", wadStepText),
            ("Skins", skinsBaseText),
            ("Greenies", greeniesAmountText),
        ]
        .filter { Money.cents(fromDollars: $0.1) == nil }
        .map { .amountInvalid(game: $0.0) }
    }

    // MARK: Round

    var allIssues: [SetupIssue] { courseIssues() + playerIssues() + gameIssues() }

    /// Builds the round. The caller inserts it into a model context.
    func makeRound(using bridge: EngineBridge, startedAt: Date = .now) throws -> Round {
        let issues = allIssues
        guard issues.isEmpty, let settings else { throw SetupError.invalid(issues) }

        let tee = tee
        let round = Round(
            courseName: trimmedCourseName,
            startedAt: startedAt,
            courseRating: tee?.courseRating,
            slope: tee?.slope,
            settings: settings,
            startsEveryHoleAtPar: startsEveryHoleAtPar
        )
        round.holes = holes.map { RoundHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex ?? 0) }
        round.players = try players.enumerated().map { offset, player in
            guard let courseHandicap = try courseHandicap(for: player, using: bridge) else {
                throw SetupError.invalid([.courseHandicapInvalid(player: offset + 1)])
            }
            return RoundPlayer(
                playerID: player.id,
                displayName: player.trimmedName,
                position: offset,
                handicapIndex: tee == nil ? nil : SetupText.handicapIndex(player.handicapIndexText),
                courseHandicap: courseHandicap,
                venmoHandle: VenmoHandle.normalized(player.venmoHandleText)
            )
        }
        if startsEveryHoleAtPar {
            for hole in round.holes {
                for player in round.players {
                    round.setGross(hole.par, playerID: player.playerID, hole: hole.number)
                }
            }
        }
        return round
    }
}

#if DEBUG
extension RoundDraft {
    /// A filled-in draft for simulator runs and previews. Its holes start
    /// unscored, so the seeded rounds and the UI tests record every score.
    static var sample: RoundDraft {
        let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4]
        let strokeIndexes = [7, 11, 17, 3, 1, 15, 9, 5, 13, 8, 18, 2, 10, 6, 12, 16, 4, 14]
        var draft = RoundDraft()
        draft.startsEveryHoleAtPar = false
        draft.courseName = "Sample Links"
        draft.ratingText = "72.5"
        draft.slopeText = "131"
        draft.holes = (0..<holeCount).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndexText: String(strokeIndexes[$0]))
        }
        draft.players = [
            Player(name: "Zach", handicapIndexText: "15.4"),
            Player(name: "Sam", handicapIndexText: "7.0"),
            Player(name: "Alex", handicapIndexText: "22.3", courseHandicapText: "20", overridesCourseHandicap: true),
            Player(name: "Jo", handicapIndexText: "+1.2"),
        ]
        return draft
    }
}
#endif
