import Foundation
import SwiftData
@testable import Wad

/// The courses API as the tests script it: the fixtures, or an error for
/// every call. Records what was asked.
@MainActor
final class FakeCourseLookupService: CourseLookupService {
    nonisolated let isConfigured: Bool
    var courses: [Course]
    var summaries: [CourseSummary]
    /// Thrown by every call while set.
    var error: CourseLookupError?
    private(set) var searches: [String] = []
    private(set) var courseRequests: [String] = []

    init(
        courses: [Course] = CourseFixtures.courses,
        summaries: [CourseSummary] = CourseFixtures.summaries,
        isConfigured: Bool = true,
        error: CourseLookupError? = nil
    ) {
        self.courses = courses
        self.summaries = summaries
        self.isConfigured = isConfigured
        self.error = error
    }

    func search(query: String) async throws -> [CourseSummary] {
        searches.append(query)
        if let error { throw error }
        let words = CourseCache.normalize(query: query).split(separator: " ")
        return summaries.filter { summary in
            let haystack = [summary.clubName, summary.courseName, summary.location.city ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    func course(id: String) async throws -> Course {
        courseRequests.append(id)
        if let error { throw error }
        guard let course = courses.first(where: { $0.courseId == id }) else { throw CourseLookupError.notFound }
        return course
    }
}

struct FakeLocationProvider: LocationProvider {
    var result: Result<LocationFix, LocationError>

    func currentFix() async throws -> LocationFix {
        try result.get()
    }
}

@MainActor
enum CourseTestSupport {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func cache() throws -> CourseCache {
        CourseCache(context: try WadSchema.inMemoryContainer().mainContext)
    }

    static func lookup(service: FakeCourseLookupService, cache: CourseCache? = nil, now: Date = now) throws -> CourseLookup {
        let lookup = CourseLookup(service: service, cache: try cache ?? self.cache())
        lookup.now = { now }
        return lookup
    }

    /// Defaults of its own, so a test's memory does not reach the next one.
    static func memory() -> CourseMemory {
        let suite = "CourseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CourseMemory(defaults: defaults)
    }

    static func model(
        service: FakeCourseLookupService = FakeCourseLookupService(),
        cache: CourseCache? = nil,
        location: any LocationProvider = FakeLocationProvider(result: .failure(.unavailable)),
        memory: CourseMemory? = nil
    ) throws -> CourseStepModel {
        CourseStepModel(
            lookup: try lookup(service: service, cache: cache),
            location: location,
            memory: memory ?? self.memory(),
            debounce: .milliseconds(20)
        )
    }
}
