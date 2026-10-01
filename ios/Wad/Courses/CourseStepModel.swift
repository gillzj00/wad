import Foundation

/// The course step's lookup: the default course, the search, the course whose
/// tees are shown, and the cached courses near the phone. It fills the draft
/// through `fill(_:)`, so the view keeps the draft and the model keeps the state.
@MainActor
@Observable
final class CourseStepModel {
    enum DefaultState: Equatable {
        case idle
        case loading
        case ready(Course)
        case failed(CourseLookupError)
    }

    enum DetailState: Equatable {
        case idle
        case loading(CourseSummary)
        case failed(CourseLookupError)
    }

    enum NearbyState: Equatable {
        case idle
        case locating
        case denied
        case failed
        /// Up to three cached courses within reach, nearest first; empty when none is.
        case found([CourseDistance.Nearby])
    }

    static let nearbyLimit = 3

    let lookup: CourseLookup
    let search: CourseSearchModel
    let memory: CourseMemory
    private let location: any LocationProvider

    /// The course whose tees are shown.
    private(set) var course: Course?
    private(set) var selectedTeeID: String?
    private(set) var defaultState = DefaultState.idle
    private(set) var detailState = DetailState.idle
    private(set) var nearbyState = NearbyState.idle
    /// Why the last tee tapped could not be used.
    private(set) var teeProblem: String?
    private var appliedDefault = false

    init(
        lookup: CourseLookup,
        location: any LocationProvider = CoreLocationProvider(),
        memory: CourseMemory = CourseMemory(),
        debounce: Duration = CourseSearchModel.defaultDebounce
    ) {
        self.lookup = lookup
        self.location = location
        self.memory = memory
        search = CourseSearchModel(lookup: lookup, debounce: debounce)
    }

    var isConfigured: Bool { lookup.isConfigured }

    /// The last course picked on this phone, or Oak Glen.
    var defaultCourseID: String { memory.lastCourseID ?? CourseDefaults.courseID }

    var selectedTee: CourseTee? {
        guard let course, let selectedTeeID else { return nil }
        return course.tee(id: selectedTeeID)
    }

    // MARK: Default course

    /// The default course from the phone if it has it, whatever its age;
    /// otherwise one request for it. Runs once.
    func loadDefaultCourse() async {
        guard defaultState == .idle else { return }
        if let cached = lookup.cachedCourse(id: defaultCourseID) {
            defaultState = .ready(cached)
            return
        }
        defaultState = .loading
        do {
            defaultState = .ready(try await lookup.course(id: defaultCourseID))
        } catch {
            defaultState = .failed(error as? CourseLookupError ?? .unavailable)
        }
    }

    /// Fills a draft nothing has been typed into with the default course on
    /// its default tee, or with the course's name alone when it could not be
    /// looked up. Done once; a draft with edits is left alone.
    @discardableResult
    func applyDefault(to draft: inout RoundDraft) -> Bool {
        guard !appliedDefault, draft.isCourseUntouched else { return false }
        switch defaultState {
        case .idle, .loading:
            return false
        case .ready(let course):
            appliedDefault = true
            show(course, tee: course.defaultTee(preferring: memory.lastTeeID))
            if selectedTee != nil {
                return fill(&draft)
            }
            draft.courseName = course.displayName
            return true
        case .failed:
            appliedDefault = true
            draft.courseName = CourseDefaults.courseName
            return true
        }
    }

    // MARK: Picking a course

    /// Fetches the course of a search result and shows its tees, with its
    /// default tee selected. False when it could not be fetched.
    func load(_ summary: CourseSummary) async -> Bool {
        detailState = .loading(summary)
        do {
            let course = try await lookup.course(id: summary.courseId)
            guard detailState == .loading(summary) else { return false }
            detailState = .idle
            show(course, tee: course.defaultTee(preferring: memory.lastTeeID))
            return true
        } catch {
            guard detailState == .loading(summary) else { return false }
            detailState = .failed(error as? CourseLookupError ?? .unavailable)
            return false
        }
    }

    /// Shows a course the phone already has, such as one nearby.
    func show(_ course: Course) {
        detailState = .idle
        show(course, tee: course.defaultTee(preferring: memory.lastTeeID))
    }

    private func show(_ course: Course, tee: CourseTee?) {
        self.course = course
        selectedTeeID = tee?.teeId
        teeProblem = nil
        search.prefill(course.displayName)
    }

    /// Selects a tee of the shown course. False, with `teeProblem` set, when
    /// the tee cannot give handicap strokes.
    @discardableResult
    func select(teeID: String) -> Bool {
        guard let course, let tee = course.tee(id: teeID) else { return false }
        guard tee.isSelectable else {
            teeProblem = "\(tee.name) tees: \(tee.unavailableReason ?? "not usable"), so handicap strokes cannot be allocated."
            return false
        }
        teeProblem = nil
        selectedTeeID = tee.teeId
        return true
    }

    /// Fills the draft from the shown course and the selected tee, and
    /// remembers them for the next round.
    @discardableResult
    func fill(_ draft: inout RoundDraft) -> Bool {
        guard let course, let tee = selectedTee else { return false }
        do {
            try draft.fill(course: course, tee: tee)
        } catch CourseFillError.teeNotUsable(let reason) {
            teeProblem = "\(tee.name) tees: \(reason)."
            return false
        } catch {
            teeProblem = "\(tee.name) tees cannot be used."
            return false
        }
        memory.remember(courseID: course.courseId, teeID: tee.teeId)
        return true
    }

    // MARK: Nearby

    /// Ranks the cached courses by distance from the phone. Nothing is
    /// selected: the group taps a suggestion or ignores it.
    func findNearby() async {
        guard nearbyState != .locating else { return }
        nearbyState = .locating
        do {
            let fix = try await location.currentFix()
            let courses = lookup.cachedCourses()
            let nearby = CourseDistance.nearby(courses, latitude: fix.latitude, longitude: fix.longitude)
            nearbyState = .found(Array(nearby.prefix(Self.nearbyLimit)))
        } catch LocationError.denied {
            nearbyState = .denied
        } catch {
            nearbyState = .failed
        }
    }
}
