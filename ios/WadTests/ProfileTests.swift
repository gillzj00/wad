import Foundation
import Testing
@testable import Wad

/// The profile kept on the phone.
@MainActor
struct ProfileTests {
    let suite = "ProfileTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    @Test func startsEmpty() {
        let store = ProfileStore(defaults: defaults)
        #expect(store.name.isEmpty)
        #expect(store.handicapIndexText.isEmpty)
        #expect(store.venmoHandleText.isEmpty)
        #expect(store.profile.isEmpty)
    }

    @Test func eachFieldPersistsAsTyped() {
        let store = ProfileStore(defaults: defaults)
        store.name = "Zach "
        store.handicapIndexText = "+1."
        store.venmoHandleText = "@zach_g"

        let reloaded = ProfileStore(defaults: defaults)
        #expect(reloaded.profile == Profile(name: "Zach ", handicapIndexText: "+1.", venmoHandleText: "@zach_g"))

        reloaded.name = ""
        #expect(ProfileStore(defaults: defaults).name.isEmpty)
        #expect(ProfileStore(defaults: defaults).venmoHandleText == "@zach_g")
    }

    @Test func isEmptyIgnoresWhitespace() {
        #expect(Profile().isEmpty)
        #expect(Profile(name: "  ", handicapIndexText: " ", venmoHandleText: "\n").isEmpty)
        #expect(!Profile(name: "Zach").isEmpty)
        #expect(!Profile(handicapIndexText: "15.4").isEmpty)
        #expect(!Profile(venmoHandleText: "zach_g").isEmpty)
        #expect(Profile(name: " Zach ").trimmedName == "Zach")
    }

    @Test func advisesOnAHandicapIndexOrVenmoHandleThatDoesNotParse() {
        #expect(ProfileView.advisories(for: Profile()).isEmpty)
        #expect(ProfileView.advisories(for: Profile(handicapIndexText: "+1.2", venmoHandleText: "@zach_g")).isEmpty)
        #expect(ProfileView.advisories(for: Profile(handicapIndexText: "15.4")).isEmpty)
        #expect(ProfileView.advisories(for: Profile(handicapIndexText: "60")) == [ProfileView.handicapIndexAdvice])
        #expect(ProfileView.advisories(for: Profile(venmoHandleText: "zg")) == [VenmoHandle.rule])
        #expect(
            ProfileView.advisories(for: Profile(handicapIndexText: "abc", venmoHandleText: "no spaces"))
                == [ProfileView.handicapIndexAdvice, VenmoHandle.rule]
        )
    }
}
