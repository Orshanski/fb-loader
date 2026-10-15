import Testing
import Foundation
@testable import FB_Loader

@Suite("SpaceRoute")
struct SpaceRouteTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("без type-select — галочка")
    func noTypeSelect() {
        #expect(spaceRoute(lastTypeSelectKey: nil, now: t0) == .toggleCheck)
    }

    @Test("0,5 с после буквы — поиск")
    func withinWindow() {
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 0.5) == .typeSelect)
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 0.999) == .typeSelect)
    }

    @Test("1,0 с и позже — галочка")
    func afterWindow() {
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 1.0) == .toggleCheck)
        #expect(spaceRoute(lastTypeSelectKey: t0, now: t0 + 5) == .toggleCheck)
    }
}
