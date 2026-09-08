import Testing
@testable import Tuck

struct FuzzyMatcherTests {
    @Test func subsequenceMatchScoresNonNil() {
        #expect(FuzzyMatcher.score(query: "wf", candidate: "Wi-Fi") != nil)
        #expect(FuzzyMatcher.score(query: "wf", candidate: "Focus") == nil)
    }

    @Test func prefixMatchScoresHigherThanMidStringMatch() {
        let bluetooth = FuzzyMatcher.score(query: "blu", candidate: "Bluetooth")
        let globalBluetooth = FuzzyMatcher.score(query: "blu", candidate: "Global Bluetooth")
        #expect(bluetooth != nil)
        #expect(globalBluetooth != nil)
        #expect(bluetooth! > globalBluetooth!)
    }

    @Test func nonSubsequenceReturnsNil() {
        #expect(FuzzyMatcher.score(query: "xyz", candidate: "Bluetooth") == nil)
    }
}
