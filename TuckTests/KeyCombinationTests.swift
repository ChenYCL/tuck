import Foundation
import Testing
@testable import Tuck

struct KeyCombinationTests {
    @Test func encodesAsTwoElementIntArray() throws {
        let combination = KeyCombination(key: .a, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(combination)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "[0,12]")

        let decoded = try JSONDecoder().decode(KeyCombination.self, from: data)
        #expect(decoded == combination)
    }

    @Test func decodingWrongElementCountThrows() {
        let data = "[0,12,1]".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(KeyCombination.self, from: data)
        }
    }
}
