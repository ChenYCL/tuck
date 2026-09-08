import CoreGraphics
import Testing
@testable import Tuck

struct SectionAttributionTests {
    private let hiddenFrame = CGRect(x: 600, y: 0, width: 20, height: 24)
    private let alwaysHiddenFrame = CGRect(x: 300, y: 0, width: 20, height: 24)

    private func frame(x: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: 20, height: 24)
    }

    @Test func itemRightOfHiddenDividerIsVisible() {
        let section = ItemStore.section(forItemFrame: frame(x: 650), hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame)
        #expect(section == .visible)
    }

    @Test func itemBetweenDividersIsHidden() {
        let section = ItemStore.section(forItemFrame: frame(x: 400), hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame)
        #expect(section == .hidden)
    }

    @Test func itemLeftOfAlwaysHiddenDividerIsAlwaysHidden() {
        let section = ItemStore.section(forItemFrame: frame(x: 100), hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame)
        #expect(section == .alwaysHidden)
    }

    @Test func withoutAlwaysHiddenSectionEverythingLeftOfHiddenDividerIsHidden() {
        let section = ItemStore.section(forItemFrame: frame(x: 100), hiddenFrame: hiddenFrame, alwaysHiddenFrame: nil)
        #expect(section == .hidden)
    }

    @Test func itemStraddlingTheHiddenDividerIsUnresolved() {
        let straddling = CGRect(x: 610, y: 0, width: 20, height: 24)
        let section = ItemStore.section(forItemFrame: straddling, hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame)
        #expect(section == nil)
    }
}
