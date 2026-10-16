import Testing
import Foundation
@testable import FB_Loader

@Suite("PaneDimension")
struct PaneDimensionTests {
    private let dim = PaneDimension(key: "test.pane", min: 280, ideal: 300, max: 480)

    @Test("без сохранённого значения — идеальный размер")
    func defaultWhenMissing() {
        withTestDefaults { d in
            #expect(dim.restore(from: d) == 300)
        }
    }

    @Test("сохранённое значение в пределах возвращается как есть")
    func roundTrip() {
        withTestDefaults { d in
            dim.save(412, to: d)
            #expect(dim.restore(from: d) == 412)
        }
    }

    @Test("значение за пределами прижимается к min/max")
    func clampsOnRestore() {
        withTestDefaults { d in
            d.set(900.0, forKey: "test.pane")
            #expect(dim.restore(from: d) == 480)
            d.set(100.0, forKey: "test.pane")
            #expect(dim.restore(from: d) == 280)
        }
    }

    @Test("мусор в defaults — идеальный размер")
    func garbageFallsBackToIdeal() {
        withTestDefaults { d in
            d.set("wide", forKey: "test.pane")
            #expect(dim.restore(from: d) == 300)
            d.set(0.0, forKey: "test.pane")
            #expect(dim.restore(from: d) == 300)
            d.set(Double.nan, forKey: "test.pane")
            #expect(dim.restore(from: d) == 300)
        }
    }

    @Test("сохраняется прижатое и округлённое значение")
    func savesClampedRounded() {
        withTestDefaults { d in
            dim.save(333.7, to: d)
            #expect(d.double(forKey: "test.pane") == 334)
            dim.save(2000, to: d)
            #expect(d.double(forKey: "test.pane") == 480)
        }
    }

    @Test("нулевой и нечисловой замер не затирают сохранённое")
    func ignoresDegenerateMeasurements() {
        withTestDefaults { d in
            dim.save(350, to: d)
            dim.save(0, to: d)
            dim.save(.nan, to: d)
            dim.save(.infinity, to: d)
            #expect(dim.restore(from: d) == 350)
        }
    }
}
