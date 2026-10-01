import Foundation
import Testing
@testable import Wad

// MARK: - Client

struct CourseLookupClientTests {
    private let configuration = CourseLookupConfiguration(baseURL: URL(string: "https://example.test"), clientToken: "secret-token")

    @Test func requestsCarryTheClientTokenAndTheQuery() throws {
        let client = CourseLookupClient(configuration: configuration)
        let search = try client.request(path: "v1/courses", query: [URLQueryItem(name: "q", value: "oak glen")])
        #expect(search.url?.absoluteString == "https://example.test/v1/courses?q=oak%20glen")
        #expect(search.value(forHTTPHeaderField: CourseLookupClient.clientTokenHeader) == "secret-token")
        #expect(search.httpMethod == "GET")

        let course = try client.request(path: "v1/courses/gca-y8jqwys2", query: [])
        #expect(course.url?.absoluteString == "https://example.test/v1/courses/gca-y8jqwys2")
    }

    @Test func configurationComesFromTheInfoPlistKeysAndIsEmptyWithoutThem() {
        let configured = CourseLookupConfiguration(info: [
            CourseLookupConfiguration.baseURLKey: " https://example.test ",
            CourseLookupConfiguration.clientTokenKey: "secret-token\n",
        ])
        #expect(configured.isConfigured)
        #expect(configured.baseURL?.absoluteString == "https://example.test")
        #expect(configured.clientToken == "secret-token")

        for info: [String: Any] in [[:], [CourseLookupConfiguration.baseURLKey: ""], [CourseLookupConfiguration.baseURLKey: "https://example.test"]] {
            let configuration = CourseLookupConfiguration(info: info)
            #expect(!configuration.isConfigured)
            #expect(!CourseLookupClient(configuration: configuration).isConfigured)
        }
    }

    @Test func unconfiguredClientThrowsBeforeAnyRequest() async {
        let client = CourseLookupClient(configuration: CourseLookupConfiguration(baseURL: nil, clientToken: "")) { _ in
            Issue.record("No request should be sent")
            throw URLError(.badURL)
        }
        await #expect(throws: CourseLookupError.notConfigured) { try await client.search(query: "oak") }
        await #expect(throws: CourseLookupError.notConfigured) { try await client.course(id: "x") }
    }

    @Test func statusesMapToTheLookupErrors() {
        func body(_ code: String) -> Data {
            Data(#"{"error":{"code":"\#(code)","message":"m"}}"#.utf8)
        }
        #expect(CourseLookupClient.map(status: 401, body: body("invalid_client_token")) == .unauthorized)
        #expect(CourseLookupClient.map(status: 400, body: body("query_too_short")) == .queryTooShort)
        #expect(CourseLookupClient.map(status: 400, body: body("other")) == .unavailable)
        #expect(CourseLookupClient.map(status: 404, body: body("course_not_found")) == .notFound)
        #expect(CourseLookupClient.map(status: 429, body: Data()) == .rateLimited)
        #expect(CourseLookupClient.map(status: 503, body: body("course_provider_rate_limited")) == .rateLimited)
        #expect(CourseLookupClient.map(status: 502, body: body("course_provider_unavailable")) == .unavailable)
        #expect(CourseLookupClient.map(status: 500, body: Data("not json".utf8)) == .unavailable)

        #expect(CourseLookupClient.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(CourseLookupClient.map(URLError(.timedOut)) == .offline)
        #expect(CourseLookupClient.map(URLError(.cancelled)) == .unavailable)
    }

    @Test func decodesTheCoursesTheApiSends() async throws {
        let json = try JSONEncoder().encode(CourseResponse(course: CourseFixtures.oakGlen))
        let client = CourseLookupClient(configuration: configuration) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json, response)
        }
        let course = try await client.course(id: CourseFixtures.oakGlenID)
        #expect(course == CourseFixtures.oakGlen)

        let failing = CourseLookupClient(configuration: configuration) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":{"code":"course_provider_rate_limited","message":"m"}}"#.utf8), response)
        }
        await #expect(throws: CourseLookupError.rateLimited) { try await failing.search(query: "oak") }
    }

    @Test func everyErrorHasItsOwnMessage() {
        let errors: [CourseLookupError] = [.notConfigured, .offline, .unauthorized, .queryTooShort, .notFound, .rateLimited, .unavailable]
        #expect(Set(errors.map(\.message)).count == errors.count)
        #expect(CourseLookupError.queryTooShort.message.contains("3"))
    }
}

// MARK: - Cache-first lookup

@MainActor
struct CourseLookupTests {
    @Test func aFreshCachedCourseCostsNoRequest() async throws {
        let service = FakeCourseLookupService()
        let cache = try CourseTestSupport.cache()
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now.addingTimeInterval(-6 * 24 * 60 * 60))
        let lookup = try CourseTestSupport.lookup(service: service, cache: cache)

        let course = try await lookup.course(id: CourseFixtures.oakGlenID)
        #expect(course == CourseFixtures.oakGlen)
        #expect(service.courseRequests.isEmpty)
    }

    @Test func aStaleCourseIsFetchedAgainAndStored() async throws {
        let service = FakeCourseLookupService()
        let cache = try CourseTestSupport.cache()
        var old = CourseFixtures.oakGlen
        old.fetchedAt = "old"
        cache.store(old, at: CourseTestSupport.now.addingTimeInterval(-8 * 24 * 60 * 60))
        let lookup = try CourseTestSupport.lookup(service: service, cache: cache)

        let course = try await lookup.course(id: CourseFixtures.oakGlenID)
        #expect(course == CourseFixtures.oakGlen)
        #expect(service.courseRequests == [CourseFixtures.oakGlenID])
        #expect(cache.course(id: CourseFixtures.oakGlenID) == CachedEntry(value: CourseFixtures.oakGlen, cachedAt: CourseTestSupport.now))
    }

    @Test func aStaleCourseStandsInWhenTheApiCannotAnswer() async throws {
        let cache = try CourseTestSupport.cache()
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now.addingTimeInterval(-30 * 24 * 60 * 60))

        for error: CourseLookupError in [.offline, .rateLimited, .unavailable, .unauthorized, .notConfigured] {
            let service = FakeCourseLookupService(error: error)
            let lookup = try CourseTestSupport.lookup(service: service, cache: cache)
            let course = try await lookup.course(id: CourseFixtures.oakGlenID)
            #expect(course == CourseFixtures.oakGlen, "\(error)")
        }

        // Not when the API says the course is gone.
        let gone = try CourseTestSupport.lookup(service: FakeCourseLookupService(error: .notFound), cache: cache)
        await #expect(throws: CourseLookupError.notFound) { try await gone.course(id: CourseFixtures.oakGlenID) }

        // And nothing stands in for a course the phone never had.
        let empty = try CourseTestSupport.lookup(service: FakeCourseLookupService(error: .offline))
        await #expect(throws: CourseLookupError.offline) { try await empty.course(id: CourseFixtures.oakGlenID) }
        #expect(empty.cachedCourse(id: CourseFixtures.oakGlenID) == nil)
    }

    @Test func searchesAreNormalizedCachedAndServedStale() async throws {
        let service = FakeCourseLookupService()
        let lookup = try CourseTestSupport.lookup(service: service)

        let first = try await lookup.search(query: "  Oak   Glen ")
        #expect(first == [CourseFixtures.oakGlenSummary, CourseFixtures.oakGlenExecutiveSummary])
        #expect(service.searches == ["oak glen"])

        let again = try await lookup.search(query: "oak glen")
        #expect(again == first)
        #expect(service.searches == ["oak glen"])

        await #expect(throws: CourseLookupError.queryTooShort) { try await lookup.search(query: "oa") }
        #expect(service.searches == ["oak glen"])

        service.error = .rateLimited
        lookup.now = { CourseTestSupport.now.addingTimeInterval(10 * 24 * 60 * 60) }
        let stale = try await lookup.search(query: "oak glen")
        #expect(stale == first)
        #expect(service.searches == ["oak glen", "oak glen"])
        await #expect(throws: CourseLookupError.rateLimited) { try await lookup.search(query: "stillwater") }
    }

    @Test func cachedCoursesListsEveryCourseOnThePhone() throws {
        let cache = try CourseTestSupport.cache()
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now.addingTimeInterval(-100 * 24 * 60 * 60))
        cache.store(CourseFixtures.stillwater, at: CourseTestSupport.now)
        let lookup = try CourseTestSupport.lookup(service: FakeCourseLookupService(), cache: cache)
        #expect(lookup.cachedCourses().map(\.courseId) == [CourseFixtures.stillwater.courseId, CourseFixtures.oakGlenID])
        #expect(lookup.cachedCourse(id: CourseFixtures.oakGlenID) == CourseFixtures.oakGlen)
    }

}

// MARK: - Debounced search

@MainActor
struct CourseSearchModelTests {
    @Test func typingSearchesOnceAfterThePause() async throws {
        let service = FakeCourseLookupService()
        let model = try CourseTestSupport.model(service: service)
        let search = model.search

        search.query = "oa"
        #expect(search.state == .tooShort)
        search.query = "oak"
        search.query = "oak g"
        search.query = "oak gl"
        try await Task.sleep(for: .milliseconds(250))

        #expect(search.searchCount == 1)
        #expect(service.searches == ["oak gl"])
        #expect(search.state == .results([CourseFixtures.oakGlenSummary, CourseFixtures.oakGlenExecutiveSummary]))

        search.query = ""
        #expect(search.state == .idle)
    }

    @Test func aFailedSearchShowsItsError() async throws {
        let service = FakeCourseLookupService(error: .rateLimited)
        let model = try CourseTestSupport.model(service: service)
        model.search.query = "stillwater"
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.search.state == .failed(.rateLimited))
    }

    @Test func prefillingDoesNotSearch() async throws {
        let service = FakeCourseLookupService()
        let model = try CourseTestSupport.model(service: service)
        model.search.prefill("Oak Glen Golf Course")
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.search.state == .idle)
        #expect(model.search.searchCount == 0)
        #expect(service.searches.isEmpty)

        await model.search.searchNow()
        #expect(service.searches == ["oak glen golf course"])
    }
}

// MARK: - Distance

struct CourseDistanceTests {
    @Test func haversineMatchesADegreeOfLatitude() {
        let meters = CourseDistance.meters(fromLatitude: 45, longitude: -93, toLatitude: 46, longitude: -93)
        #expect(abs(meters - 111_195) < 100)
        #expect(CourseDistance.meters(fromLatitude: 45, longitude: -93, toLatitude: 45, longitude: -93) == 0)
    }

    @Test func nearbyRanksTheCoursesWithinReachNearestFirst() {
        var far = CourseFixtures.stillwater
        far.courseId = "far"
        far.location.latitude = 44.9
        var unlocated = CourseFixtures.stillwater
        unlocated.courseId = "unlocated"
        unlocated.location.latitude = nil

        let nearby = CourseDistance.nearby(
            [far, CourseFixtures.stillwater, unlocated, CourseFixtures.oakGlen],
            latitude: 45.0702,
            longitude: -92.8341
        )
        #expect(nearby.map(\.course.courseId) == [CourseFixtures.oakGlenID, CourseFixtures.stillwater.courseId])
        #expect(nearby[0].meters < 5)
        #expect(abs(nearby[1].meters - 1_550) < 100)
    }

    @Test func distancesReadInMetersThenKilometers() {
        #expect(CourseDistance.text(meters: 347) == "350 m")
        #expect(CourseDistance.text(meters: 1_234) == "1.2 km")
        #expect(CourseDistance.text(meters: 5_000) == "5.0 km")
    }
}
