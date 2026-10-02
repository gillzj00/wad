import Foundation

/// The Courses tab: the search, the courses near the phone and the courses
/// already on it, which keep the tab useful offline. A course is opened from
/// the phone when it has it, whatever its age; only a course the phone does
/// not have costs a request.
@MainActor
@Observable
final class CoursesModel {
    let lookup: CourseLookup
    let search: CourseSearchModel
    let memory: CourseMemory
    private let location: any LocationProvider

    /// The courses on this phone, most recently cached first.
    private(set) var recent: [Course] = []
    private(set) var nearbyState = NearbyCoursesState.idle
    /// How far "Near me" looks, in miles; remembered on the phone.
    private(set) var nearbyRadiusMiles: Int

    init(
        lookup: CourseLookup,
        location: any LocationProvider = CoreLocationProvider(),
        memory: CourseMemory = CourseMemory(),
        debounce: Duration = CourseSearchModel.defaultDebounce
    ) {
        self.lookup = lookup
        self.location = location
        self.memory = memory
        nearbyRadiusMiles = memory.nearbyRadiusMiles
        search = CourseSearchModel(lookup: lookup, debounce: debounce)
    }

    var isConfigured: Bool { lookup.isConfigured }

    func refreshRecent() {
        recent = lookup.cachedCourses()
    }

    /// The course of a row: the phone's copy, or one request for it.
    func course(for summary: CourseSummary) async throws -> Course {
        if let cached = lookup.cachedCourse(id: summary.courseId) { return cached }
        let course = try await lookup.course(id: summary.courseId)
        refreshRecent()
        return course
    }

    func findNearby() async {
        guard nearbyState != .locating else { return }
        nearbyState = .locating
        nearbyState = await CourseDistance.find(in: lookup, with: location, withinMiles: nearbyRadiusMiles)
    }

    /// Remembers the radius, and looks again when courses are already listed.
    func setNearbyRadius(_ miles: Int) async {
        nearbyRadiusMiles = miles
        memory.remember(nearbyRadiusMiles: miles)
        if case .found = nearbyState { await findNearby() }
    }

    /// A new round's draft on the course and tee, which the setup flow opens
    /// on. The course and tee are remembered for the next round as well.
    func draft(for course: Course, tee: CourseTee) throws -> RoundDraft {
        var draft = RoundDraft()
        try draft.fill(course: course, tee: tee)
        memory.remember(courseID: course.courseId, teeID: tee.teeId)
        return draft
    }
}

/// A tee's scorecard: its holes in order, as nines, with the par and yardage
/// of each nine and of the card. Computed from the holes, not read from the
/// tee's totals, so the card adds up.
struct TeeScorecard: Equatable {
    struct Nine: Equatable {
        /// "Out" or "In".
        let title: String
        let holes: [CourseHole]

        var par: Int { holes.reduce(0) { $0 + $1.par } }

        /// The yardages added up; nil when no hole has one.
        var yardage: Int? {
            let known = holes.compactMap(\.yardage)
            return known.isEmpty ? nil : known.reduce(0, +)
        }
    }

    let front: Nine
    /// Nil on a nine-hole course.
    let back: Nine?

    init(tee: CourseTee) {
        let holes = tee.holes.sorted { $0.hole < $1.hole }
        front = Nine(title: "Out", holes: Array(holes.prefix(9)))
        let rest = Array(holes.dropFirst(9))
        back = rest.isEmpty ? nil : Nine(title: "In", holes: rest)
    }

    var totalPar: Int { front.par + (back?.par ?? 0) }

    var totalYardage: Int? {
        let known = [front.yardage, back?.yardage].compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// "6,872 yds" or "-".
    static func text(yards: Int?) -> String {
        guard let yards else { return "-" }
        return "\(yards.formatted(.number.grouping(.automatic))) yds"
    }
}
