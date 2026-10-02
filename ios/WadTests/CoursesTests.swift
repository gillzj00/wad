import Foundation
import Testing
@testable import Wad

// MARK: - The scorecard

struct TeeScorecardTests {
    @Test func theNinesAndTheCardAddUpTheHoles() throws {
        let black = try #require(CourseFixtures.oakGlen.tee(id: "male-black"))
        let card = TeeScorecard(tee: black)

        #expect(card.front.holes.map(\.hole) == Array(1...9))
        #expect(card.back?.holes.map(\.hole) == Array(10...18))
        #expect(card.front.par == CourseFixtures.pars[0..<9].reduce(0, +))
        #expect(card.back?.par == CourseFixtures.pars[9..<18].reduce(0, +))
        #expect(card.totalPar == 72)
        #expect(card.totalPar == black.par)
        #expect(card.front.yardage == CourseFixtures.blackYards[0..<9].reduce(0, +))
        #expect(card.back?.yardage == CourseFixtures.blackYards[9..<18].reduce(0, +))
        #expect(card.totalYardage == CourseFixtures.blackYards.reduce(0, +))
        #expect(card.totalYardage == black.totalYards)
        #expect(card.front.title == "Out")
        #expect(card.back?.title == "In")
    }

    @Test func theHolesAreOrderedAndANineHoleCourseHasNoBack() throws {
        var shuffled = try #require(CourseFixtures.oakGlen.tee(id: "male-blue"))
        shuffled.holes.reverse()
        let card = TeeScorecard(tee: shuffled)
        #expect(card.front.holes.map(\.hole) == Array(1...9))
        #expect(card.back?.holes.map(\.hole) == Array(10...18))

        let nine = try #require(CourseFixtures.oakGlenExecutive.tees.first)
        let short = TeeScorecard(tee: nine)
        #expect(short.back == nil)
        #expect(short.front.holes.count == 9)
        #expect(short.totalPar == 28)
        #expect(short.totalPar == nine.par)
        #expect(short.totalYardage == nine.holes.compactMap(\.yardage).reduce(0, +))
    }

    @Test func yardageIsUnknownWhenNoHoleHasOne() throws {
        var tee = try #require(CourseFixtures.oakGlen.tee(id: "male-blue"))
        for offset in tee.holes.indices { tee.holes[offset].yardage = nil }
        let card = TeeScorecard(tee: tee)
        #expect(card.front.yardage == nil)
        #expect(card.totalYardage == nil)
        #expect(TeeScorecard.text(yards: nil) == "-")
        #expect(TeeScorecard.text(yards: 6872) == "6,872 yds")
    }
}

// MARK: - The address

struct CourseAddressTests {
    @Test func theLinesLeaveOutWhatTheAddressAlreadySays() {
        var location = CourseFixtures.oakGlenLocation
        #expect(location.addressLines == ["1599 McKusick Rd N", "Stillwater, MN", "United States"])

        location.address = "1599 McKusick Rd N, Stillwater, MN 55082, USA"
        #expect(location.addressLines == ["1599 McKusick Rd N, Stillwater, MN 55082, USA"])

        location.address = nil
        #expect(location.addressLines == ["Stillwater, MN", "United States"])

        location = CourseLocation(city: "Stillwater")
        #expect(location.addressLines == ["Stillwater"])
        #expect(CourseLocation().addressLines.isEmpty)
    }
}

// MARK: - The Courses tab

@MainActor
struct CoursesModelTests {
    @Test func recentCoursesAreTheCachedOnesMostRecentlyCachedFirst() async throws {
        let cache = try CourseTestSupport.cache()
        let now = CourseTestSupport.now
        cache.store(CourseFixtures.stillwater, at: now.addingTimeInterval(-2 * 24 * 60 * 60))
        cache.store(CourseFixtures.oakGlen, at: now.addingTimeInterval(-1 * 24 * 60 * 60))
        cache.store(CourseFixtures.oakGlenExecutive, at: now)
        let model = try CourseTestSupport.coursesModel(cache: cache)

        #expect(model.recent.isEmpty)
        model.refreshRecent()
        #expect(model.recent.map(\.courseId) == [
            CourseFixtures.oakGlenExecutiveID, CourseFixtures.oakGlenID, CourseFixtures.stillwaterSummary.courseId,
        ])

        // Looking a course up again moves it to the front.
        cache.store(CourseFixtures.stillwater, at: now.addingTimeInterval(60))
        model.refreshRecent()
        #expect(model.recent.first?.courseId == CourseFixtures.stillwaterSummary.courseId)
    }

    @Test func withoutTheApiSettingsTheCachedCoursesAreStillListed() async throws {
        let service = FakeCourseLookupService(isConfigured: false, error: .notConfigured)
        let cache = try CourseTestSupport.cache()
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now)
        let model = try CourseTestSupport.coursesModel(service: service, cache: cache)

        #expect(!model.isConfigured)
        model.refreshRecent()
        #expect(model.recent == [CourseFixtures.oakGlen])

        // Opening a cached course costs no request; an uncached one reports the problem.
        #expect(try await model.course(for: CourseFixtures.oakGlenSummary) == CourseFixtures.oakGlen)
        #expect(service.courseRequests.isEmpty)
        await #expect(throws: CourseLookupError.notConfigured) {
            try await model.course(for: CourseFixtures.stillwaterSummary)
        }
    }

    @Test func aCourseThePhoneHasIsServedWhateverItsAgeAndOneItDoesNotIsFetched() async throws {
        let service = FakeCourseLookupService()
        let cache = try CourseTestSupport.cache()
        var old = CourseFixtures.oakGlen
        old.tees.removeLast()
        cache.store(old, at: CourseTestSupport.now.addingTimeInterval(-90 * 24 * 60 * 60))
        let model = try CourseTestSupport.coursesModel(service: service, cache: cache)

        #expect(try await model.course(for: CourseFixtures.oakGlenSummary) == old)
        #expect(service.courseRequests.isEmpty)

        #expect(try await model.course(for: CourseFixtures.stillwaterSummary) == CourseFixtures.stillwater)
        #expect(service.courseRequests == [CourseFixtures.stillwaterSummary.courseId])
        // And it is on the phone now, at the front of the recent courses.
        #expect(model.recent.map(\.courseId) == [CourseFixtures.stillwaterSummary.courseId, CourseFixtures.oakGlenID])
    }

    @Test func nearMeRanksTheCachedCoursesWithoutPickingOne() async throws {
        let cache = try CourseTestSupport.cache()
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now)
        cache.store(CourseFixtures.stillwater, at: CourseTestSupport.now)
        let fix = LocationFix(latitude: 45.0670, longitude: -92.8160)
        let model = try CourseTestSupport.coursesModel(cache: cache, location: FakeLocationProvider(result: .success(fix)))

        await model.findNearby()
        guard case .found(let nearby) = model.nearbyState else {
            Issue.record("Expected nearby courses, got \(model.nearbyState)")
            return
        }
        #expect(nearby.map(\.course.courseId) == [CourseFixtures.stillwaterSummary.courseId, CourseFixtures.oakGlenID])

        let denied = try CourseTestSupport.coursesModel(location: FakeLocationProvider(result: .failure(.denied)))
        await denied.findNearby()
        #expect(denied.nearbyState == .denied)
    }

    @Test func theDraftForARoundHereIsFilledFromTheCourseAndTee() throws {
        let memory = CourseTestSupport.memory()
        let model = try CourseTestSupport.coursesModel(memory: memory)
        let blue = try #require(CourseFixtures.oakGlen.tee(id: "male-blue"))

        let draft = try model.draft(for: CourseFixtures.oakGlen, tee: blue)
        #expect(draft.courseName == "Oak Glen Golf Course")
        #expect(draft.ratingText == "71.3")
        #expect(draft.slopeText == "131")
        #expect(draft.holes.map(\.par) == CourseFixtures.pars)
        #expect(draft.holes.map(\.strokeIndexText) == CourseFixtures.strokeIndexes.map(String.init))
        #expect(draft.course?.teeID == "male-blue")
        #expect(draft.courseIssues().isEmpty)
        // Untouched otherwise: the players and games are still to come.
        #expect(draft.players.count == RoundDraft().players.count)
        #expect(draft.players.allSatisfy { $0.trimmedName.isEmpty })
        #expect(memory.lastCourseID == CourseFixtures.oakGlenID)
        #expect(memory.lastTeeID == "male-blue")

        let junior = try #require(CourseFixtures.oakGlen.tee(id: "male-junior"))
        #expect(throws: CourseFillError.teeNotUsable("No stroke indexes")) {
            try model.draft(for: CourseFixtures.oakGlen, tee: junior)
        }
    }

    @Test func theSetupFlowShowsThePrefilledCourseWithoutChangingTheDraft() async throws {
        let memory = CourseTestSupport.memory()
        let cache = try CourseTestSupport.cache()
        cache.store(CourseFixtures.oakGlen, at: CourseTestSupport.now)
        let courses = try CourseTestSupport.coursesModel(cache: cache, memory: memory)
        let red = try #require(CourseFixtures.oakGlen.tee(id: "female-red"))
        var draft = try courses.draft(for: CourseFixtures.oakGlen, tee: red)
        let filled = draft

        // What RoundSetupView does with the draft it is handed.
        let service = FakeCourseLookupService()
        let step = try CourseTestSupport.model(service: service, cache: cache, memory: memory)
        await step.loadDefaultCourse()
        #expect(!step.applyDefault(to: &draft))
        #expect(draft == filled)
        #expect(step.course == CourseFixtures.oakGlen)
        #expect(step.selectedTeeID == "female-red")
        #expect(step.search.query == "Oak Glen Golf Course")
        #expect(service.courseRequests.isEmpty)

        // Once, like the default.
        var another = RoundDraft()
        #expect(!step.applyDefault(to: &another))
        #expect(another.isCourseUntouched)
    }
}
