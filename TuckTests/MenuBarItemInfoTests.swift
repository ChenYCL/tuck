import Foundation
import Testing
@testable import Tuck

struct MenuBarItemInfoTests {
    @Test func clockRoundTripsThroughCoding() throws {
        let data = try JSONEncoder().encode(MenuBarItemInfo.clock)
        let decoded = try JSONDecoder().decode(MenuBarItemInfo.self, from: data)
        #expect(decoded == .clock)

        let string = try JSONDecoder().decode(String.self, from: data)
        #expect(string == "com.apple.controlcenter:com.apple.menuextra.clock")
    }

    @Test func decodingSplitsAtFirstColon() throws {
        let data = "\"com.foo:a:b\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MenuBarItemInfo.self, from: data)
        #expect(decoded.namespace.rawValue == "com.foo")
        #expect(decoded.title == "a:b")
    }

    @Test func decodingWithoutColonThrows() {
        let data = "\"nocolon\"".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MenuBarItemInfo.self, from: data)
        }
    }
}
