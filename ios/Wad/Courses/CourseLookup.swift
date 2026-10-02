import Foundation
import SwiftUI

/// The course the setup flow starts on.
enum CourseDefaults {
    /// Oak Glen Golf Course, Stillwater, MN: the provider's 18-hole course
    /// (the Executive Nine is a course of its own).
    static let courseID = "gca-y8jqwys2"
    /// What to search for when the course is not on the phone yet.
    static let searchText = "Oak Glen"
}

/// Course lookup through the cache first: a search or a course that the
/// phone has from the last 7 days costs no request, and anything cached, of
/// any age, stands in when the API cannot be reached.
@MainActor
final class CourseLookup {
    let service: any CourseLookupService
    let cache: CourseCache
    var now: () -> Date = { .now }

    init(service: any CourseLookupService, cache: CourseCache) {
        self.service = service
        self.cache = cache
    }

    var isConfigured: Bool { service.isConfigured }

    func search(query: String) async throws -> [CourseSummary] {
        let normalized = CourseCache.normalize(query: query)
        guard normalized.count >= CourseSearchModel.minimumQueryLength else { throw CourseLookupError.queryTooShort }
        let cached = cache.results(query: normalized)
        if let cached, cached.isFresh(at: now()) { return cached.value }
        do {
            let results = try await service.search(query: normalized)
            cache.store(results, query: normalized, at: now())
            return results
        } catch {
            if let cached, Self.servesStale(error) { return cached.value }
            throw Self.lookupError(error)
        }
    }

    func course(id: String) async throws -> Course {
        let cached = cache.course(id: id)
        if let cached, cached.isFresh(at: now()) { return cached.value }
        do {
            let course = try await service.course(id: id)
            cache.store(course, at: now())
            return course
        } catch {
            if let cached, Self.servesStale(error) { return cached.value }
            throw Self.lookupError(error)
        }
    }

    /// The course if the phone has it, however old.
    func cachedCourse(id: String) -> Course? {
        cache.course(id: id)?.value
    }

    func cachedCourses() -> [Course] {
        cache.courses()
    }

    /// A stale copy is better than nothing when the API cannot answer; it is
    /// not when the API says the thing does not exist.
    private static func servesStale(_ error: Error) -> Bool {
        switch lookupError(error) {
        case .notFound, .queryTooShort: false
        default: true
        }
    }

    private static func lookupError(_ error: Error) -> CourseLookupError {
        error as? CourseLookupError ?? .unavailable
    }
}

/// The search field: a query is looked up once typing has paused for the
/// debounce, and only from the API's minimum length.
@MainActor
@Observable
final class CourseSearchModel {
    nonisolated static let minimumQueryLength = 3
    static let defaultDebounce: Duration = .milliseconds(400)

    enum State: Equatable {
        case idle
        case tooShort
        case searching
        case results([CourseSummary])
        case failed(CourseLookupError)
    }

    var query = "" {
        didSet {
            guard query != oldValue, !isPrefilling else { return }
            queryChanged()
        }
    }

    private(set) var state = State.idle
    /// How many searches were sent to the lookup, for the tests.
    private(set) var searchCount = 0

    private let lookup: CourseLookup
    private let debounce: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isPrefilling = false

    init(lookup: CourseLookup, debounce: Duration = CourseSearchModel.defaultDebounce) {
        self.lookup = lookup
        self.debounce = debounce
    }

    static func isSearchable(_ query: String) -> Bool {
        CourseCache.normalize(query: query).count >= minimumQueryLength
    }

    /// Puts text in the field without searching for it; the search is offered instead.
    func prefill(_ text: String) {
        pending?.cancel()
        isPrefilling = true
        query = text
        isPrefilling = false
        state = .idle
    }

    private func queryChanged() {
        pending?.cancel()
        guard Self.isSearchable(query) else {
            state = query.isEmpty ? .idle : .tooShort
            return
        }
        let debounce = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.searchNow()
        }
    }

    /// Searches for the field's text right away.
    func searchNow() async {
        pending?.cancel()
        let query = query
        guard Self.isSearchable(query) else {
            state = .tooShort
            return
        }
        state = .searching
        searchCount += 1
        do {
            let results = try await lookup.search(query: query)
            guard self.query == query else { return }
            state = .results(results)
        } catch {
            guard self.query == query else { return }
            state = .failed(error as? CourseLookupError ?? .unavailable)
        }
    }
}

/// How "Near me" is doing, in the course step and on the Courses tab.
enum NearbyCoursesState: Equatable {
    case idle
    case locating
    case denied
    case failed
    /// Up to `CourseDistance.nearbyLimit` cached courses within reach, nearest first; empty when none is.
    case found([CourseDistance.Nearby])
}

/// Distances between a fix and the cached courses, on the phone only.
enum CourseDistance {
    static let metersPerMile = 1_609.344
    /// The "Near me" radii the group can pick from, in miles.
    static let radiusChoices = [1, 5, 10, 25, 50]
    static let defaultRadiusMiles = 5
    static let nearbyLimit = 3

    struct Nearby: Equatable, Identifiable {
        let course: Course
        let meters: Double

        var id: String { course.courseId }
    }

    /// Great-circle distance in meters (haversine).
    static func meters(fromLatitude lat1: Double, longitude lon1: Double, toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// The courses within reach of the fix, nearest first. Courses without coordinates are left out.
    static func nearby(_ courses: [Course], latitude: Double, longitude: Double, within limit: Double) -> [Nearby] {
        courses.compactMap { course -> Nearby? in
            guard let lat = course.location.latitude, let lon = course.location.longitude else { return nil }
            let distance = meters(fromLatitude: latitude, longitude: longitude, toLatitude: lat, longitude: lon)
            return distance <= limit ? Nearby(course: course, meters: distance) : nil
        }
        .sorted { $0.meters < $1.meters }
    }

    /// "350 yds" under a quarter mile, otherwise "1.2 mi".
    static func text(meters: Double) -> String {
        let miles = meters / metersPerMile
        if miles < 0.25 {
            return "\(Int((miles * 1_760 / 10).rounded()) * 10) yds"
        }
        return String(format: "%.1f mi", miles)
    }

    /// "1 mile" or "25 miles".
    static func text(miles: Int) -> String {
        miles == 1 ? "1 mile" : "\(miles) miles"
    }

    /// One fix, then the cached courses within the radius of it, nearest first.
    /// Nothing is selected: the group taps a suggestion or ignores it.
    @MainActor
    static func find(in lookup: CourseLookup, with location: any LocationProvider, withinMiles miles: Int) async -> NearbyCoursesState {
        do {
            let fix = try await location.currentFix()
            let nearby = nearby(
                lookup.cachedCourses(),
                latitude: fix.latitude,
                longitude: fix.longitude,
                within: Double(miles) * metersPerMile
            )
            return .found(Array(nearby.prefix(nearbyLimit)))
        } catch LocationError.denied {
            return .denied
        } catch {
            return .failed
        }
    }
}

// MARK: - Environment

private struct CourseLookupServiceKey: EnvironmentKey {
    static let defaultValue: any CourseLookupService = CourseLookupClient(configuration: .fromBundle)
}

extension EnvironmentValues {
    /// The API, or the fixtures under `-debugCourseLookup fixture`.
    var courseLookupService: any CourseLookupService {
        get { self[CourseLookupServiceKey.self] }
        set { self[CourseLookupServiceKey.self] = newValue }
    }
}
