import Foundation

/// The course and tee that filled the draft's course fields, so the step can
/// say where the values came from. The fields stay editable: the selection is
/// a note, not a lock.
struct CourseSelection: Equatable, Sendable {
    var courseID: String
    var courseName: String
    var teeID: String
    var teeName: String
    var gender: TeeGender

    /// "Blue tees (men's)".
    var teeText: String {
        "\(teeName) tees (\(gender == .male ? "men's" : "women's"))"
    }
}

enum CourseFillError: Error, Equatable {
    /// The tee cannot fill a round: no stroke indexes, or not 18 holes.
    case teeNotUsable(String)
}

extension CourseDefaults {
    /// The name the course field falls back on when the default course cannot be looked up.
    static let courseName = "Oak Glen Golf Course"
}

extension Course {
    var usableTees: [CourseTee] { tees.filter(\.isSelectable) }

    /// The tee a round starts on: the one asked for if it is usable, else the
    /// first usable men's tee, else the first usable tee.
    func defaultTee(preferring teeID: String? = nil) -> CourseTee? {
        if let teeID, let tee = tee(id: teeID), tee.isSelectable { return tee }
        return usableTees.first { $0.gender == .male } ?? usableTees.first
    }
}

extension RoundDraft {
    /// Nothing has been typed into the course fields: a new draft, or one
    /// holding only the default course's name.
    var isCourseUntouched: Bool {
        guard course == nil else { return false }
        let name = trimmedCourseName
        return (name.isEmpty || name == CourseDefaults.courseName)
            && ratingText.trimmingCharacters(in: .whitespaces).isEmpty
            && slopeText.trimmingCharacters(in: .whitespaces).isEmpty
            && holes == RoundDraft().holes
    }

    /// Fills the course name, rating, slope and every hole's par and stroke
    /// index from the tee. A tee that cannot give handicap strokes is refused.
    mutating func fill(course: Course, tee: CourseTee) throws {
        guard tee.isSelectable else {
            throw CourseFillError.teeNotUsable(tee.unavailableReason ?? "Not usable")
        }
        let holesByNumber = Dictionary(tee.holes.map { ($0.hole, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(holesByNumber.keys) == Set(1...Self.holeCount) else {
            throw CourseFillError.teeNotUsable("Holes are not numbered 1 to \(Self.holeCount)")
        }
        courseName = course.displayName
        if let rating = tee.courseRating, let slope = tee.slope {
            ratingText = SetupText.display(handicapIndex: rating)
            slopeText = String(slope)
        } else {
            ratingText = ""
            slopeText = ""
        }
        holes = (1...Self.holeCount).map { number in
            let hole = holesByNumber[number]!
            return Hole(number: number, par: hole.par, strokeIndexText: hole.strokeIndex.map(String.init) ?? "")
        }
        self.course = CourseSelection(
            courseID: course.courseId,
            courseName: course.displayName,
            teeID: tee.teeId,
            teeName: tee.name,
            gender: tee.gender
        )
    }
}

/// The last course and tee picked on this phone, which the next round starts on.
struct CourseMemory {
    static let courseKey = "lastCourseID"
    static let teeKey = "lastTeeID"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastCourseID: String? { defaults.string(forKey: Self.courseKey) }
    var lastTeeID: String? { defaults.string(forKey: Self.teeKey) }

    func remember(courseID: String, teeID: String) {
        defaults.set(courseID, forKey: Self.courseKey)
        defaults.set(teeID, forKey: Self.teeKey)
    }
}
