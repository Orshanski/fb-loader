import Foundation
import Testing
@testable import FB_Loader

@Suite("MissingPaths")
struct MissingPathsTests {
    private let inpx = URL(fileURLWithPath: "/lib/flibusta.inpx")
    private let archives = URL(fileURLWithPath: "/disk/archives")

    private func check(inpx: URL?, archives: URL?, reachable: Set<URL>) -> MissingPaths? {
        MissingPaths.check(inpx: inpx, archives: archives) { reachable.contains($0) }
    }

    @Test("оба пути на месте — онбординг не нужен")
    func bothReachable() {
        #expect(check(inpx: inpx, archives: archives, reachable: [inpx, archives]) == nil)
    }

    @Test("недоступен только INPX — спрашивается только он")
    func onlyINPXMissing() {
        #expect(check(inpx: inpx, archives: archives, reachable: [archives]) == .inpx)
        #expect(check(inpx: nil, archives: archives, reachable: [archives]) == .inpx)
    }

    @Test("недоступна только папка архивов — спрашивается только она")
    func onlyArchivesMissing() {
        #expect(check(inpx: inpx, archives: archives, reachable: [inpx]) == .archives)
        #expect(check(inpx: inpx, archives: nil, reachable: [inpx]) == .archives)
    }

    @Test("не задано или недоступно оба — полный онбординг")
    func bothMissing() {
        #expect(check(inpx: nil, archives: nil, reachable: []) == .both)
        #expect(check(inpx: inpx, archives: archives, reachable: []) == .both)
    }

    @Test("сохранённого второго пути нет — resolve не собирает пару")
    func resolveWithoutCounterpart() {
        let picked = URL(fileURLWithPath: "/x")
        #expect(MissingPaths.inpx.resolve(picked: picked, inpx: nil, archives: nil) == nil)
        #expect(MissingPaths.archives.resolve(picked: picked, inpx: nil, archives: nil) == nil)
    }

    @Test("выбор INPX при .inpx папку архивов сохраняет")
    func resolveINPXKeepsArchives() {
        let picked = URL(fileURLWithPath: "/other/new.inpx")
        let r = MissingPaths.inpx.resolve(picked: picked, inpx: inpx, archives: archives)
        #expect(r?.inpx == picked)
        #expect(r?.archives == archives)
    }

    @Test("выбор папки при .archives INPX сохраняет")
    func resolveArchivesKeepsINPX() {
        let picked = URL(fileURLWithPath: "/new/archives")
        let r = MissingPaths.archives.resolve(picked: picked, inpx: inpx, archives: archives)
        #expect(r?.inpx == inpx)
        #expect(r?.archives == picked)
    }

    @Test("при .both папка архивов — директория INPX")
    func resolveBothDefaultsArchivesToINPXFolder() {
        let picked = URL(fileURLWithPath: "/other/new.inpx")
        let r = MissingPaths.both.resolve(picked: picked, inpx: nil, archives: nil)
        #expect(r?.inpx == picked)
        #expect(r?.archives.path == "/other")
    }
}
