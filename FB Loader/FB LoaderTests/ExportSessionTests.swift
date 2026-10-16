import Testing
import Foundation
@testable import FB_Loader

@Suite("ExportSession")
@MainActor
final class ExportSessionTests {
    private let dir: URL
    private let archivesRoot: URL
    private let paths: UserPaths
    private let library: Library

    private struct RunCall {
        let items: [ExportItem]
        let root: URL
        let progress: ExportProgress
        let onExported: @MainActor (Int32) -> Void
    }

    private final class Harness {
        var chooseCalls: [URL?] = []
        var chosen: URL?
        var runCalls: [RunCall] = []
        var madeFormats: [ExportFormat] = []
        var released = false
        var continuation: CheckedContinuation<Void, Never>?
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    private let h = Harness()

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        archivesRoot = dir.appendingPathComponent("archives", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("out"), withIntermediateDirectories: true)
        paths = UserPaths(defaults: UserDefaults(suiteName: "FB_Loader.test.\(UUID())")!)
        paths.archivesDirectoryURL = archivesRoot
        h.chosen = dir.appendingPathComponent("out")
        let authors = [Author.unknown, Author(id: 1, lastName: "Толстой", firstName: "Лев", middleName: ""),
                       Author(id: 2, lastName: "Дяченко", firstName: "Марина", middleName: "")]
        let books = [
            Book(libid: 1, title: "Война", authorIDs: [1], seriesID: nil, seriesNum: nil, genreIDs: [],
                 language: "ru", archiveIndex: 0, size: 0, dateAdded: nil),
            Book(libid: 2, title: "Мир", authorIDs: [1, 2], seriesID: nil, seriesNum: nil, genreIDs: [],
                 language: "ru", archiveIndex: 1, size: 0, dateAdded: nil),
        ]
        library = Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["fb2-001", "fb2-002"],
                          authors: authors, series: [], genres: [], books: books)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    private func makeSession() -> ExportSession {
        let h = h
        return ExportSession(
            userPaths: paths,
            chooseFolder: { initial in h.chooseCalls.append(initial); return h.chosen },
            makeConverter: { format in h.madeFormats.append(format); return PassthroughConverter() },
            run: { items, root, progress, _, onExported in
                h.runCalls.append(RunCall(items: items, root: root, progress: progress, onExported: onExported))
                if !h.released { await withCheckedContinuation { h.continuation = $0 } }
            })
    }

    private func request(_ libids: Set<Int32> = [1, 2], author: Int32? = nil,
                         format: ExportFormat = .fb2, origin: ExportOrigin = .main,
                         uncheck: @escaping @MainActor (Int32) -> Void = { _ in }) -> ExportRequest {
        ExportRequest(libids: libids, library: library, selectedAuthorID: author, selectedSeriesID: nil,
                      format: format, origin: origin, uncheck: uncheck)
    }

    private func finish(_ task: Task<Void, Never>?) async {
        h.release()
        await task?.value
    }

    @Test("пустые libids — отказ без панели")
    func emptyLibids() async {
        let s = makeSession()
        #expect(await s.start(request([])) == nil)
        #expect(h.chooseCalls.isEmpty)
        #expect(s.phase == .idle)
    }

    @Test("нет папки архивов — отказ без панели")
    func noArchives() async {
        paths.archivesDirectoryURL = nil
        let s = makeSession()
        #expect(await s.start(request()) == nil)
        #expect(h.chooseCalls.isEmpty)
    }

    @Test("начальная папка: последняя, иначе домашняя")
    func initialFolder() async {
        let s = makeSession()
        let home = FileManager.default.homeDirectoryForCurrentUser
        await finish(await s.start(request()))
        #expect(h.chooseCalls == [home])
        #expect(paths.lastExportDirectoryURL == dir.appendingPathComponent("out"))
        h.released = false
        await finish(await s.start(request()))
        #expect(h.chooseCalls.last! == dir.appendingPathComponent("out"))
    }

    @Test("недоступная запомненная папка заменяется домашней")
    func unavailableLast() async {
        paths.lastExportDirectoryURL = dir.appendingPathComponent("gone")
        let s = makeSession()
        await finish(await s.start(request()))
        #expect(h.chooseCalls == [FileManager.default.homeDirectoryForCurrentUser])
    }

    @Test("отмена панели ничего не меняет")
    func panelCancelled() async {
        let last = dir.appendingPathComponent("out")
        paths.lastExportDirectoryURL = last
        h.chosen = nil
        let s = makeSession()
        #expect(await s.start(request()) == nil)
        #expect(s.phase == .idle)
        #expect(s.progress == nil)
        #expect(paths.lastExportDirectoryURL == last)
        #expect(h.runCalls.isEmpty)
    }

    @Test("папка выбрана: запись пути, фаза running, прогресс только у своего окна")
    func folderChosen() async {
        let s = makeSession()
        let task = await s.start(request(origin: .search))
        #expect(paths.lastExportDirectoryURL == h.chosen)
        #expect(s.phase == .running)
        #expect(s.progress(for: .search) != nil)
        #expect(s.progress(for: .main) == nil)
        await finish(task)
    }

    @Test("аргументы run: папка, archiveURL, набор книг")
    func runArguments() async {
        let s = makeSession()
        let task = await s.start(request())
        while h.runCalls.isEmpty { await Task.yield() }
        let call = h.runCalls[0]
        #expect(call.root == h.chosen)
        #expect(Set(call.items.map(\.book.libid)) == [1, 2])
        #expect(Set(call.items.map(\.archiveURL)) == [archivesRoot.appendingPathComponent("fb2-001.zip"),
                                                      archivesRoot.appendingPathComponent("fb2-002.zip")])
        await finish(task)
    }

    @Test("автор берётся из запроса")
    func authorFromRequest() async {
        let s = makeSession()
        let task = await s.start(request([2], author: 2))
        while h.runCalls.isEmpty { await Task.yield() }
        #expect(h.runCalls[0].items[0].destination.deletingLastPathComponent().lastPathComponent == "Дяченко Марина")
        await finish(task)
    }

    @Test("формат из запроса: конвертер, расширение имён")
    func formatFromRequest() async {
        let s = makeSession()
        let epub = ExportFormat(fileExtension: "epub")
        let task = await s.start(request([1], format: epub))
        while h.runCalls.isEmpty { await Task.yield() }
        #expect(h.madeFormats == [epub])
        #expect(h.runCalls[0].items[0].destination.pathExtension == "epub")
        await finish(task)
    }

    @Test("повторный start во время панели — отказ")
    func secondStartDuringPanel() async {
        let h = h
        var panelContinuation: CheckedContinuation<URL?, Never>?
        let s = ExportSession(userPaths: paths, chooseFolder: { _ in
            h.chooseCalls.append(nil)
            return await withCheckedContinuation { panelContinuation = $0 }
        }, run: { _, _, _, _, _ in })
        let first = Task { await s.start(request()) }
        while panelContinuation == nil { await Task.yield() }
        #expect(s.phase == .choosingFolder)
        #expect(await s.start(request()) == nil)
        #expect(h.chooseCalls.count == 1)
        panelContinuation?.resume(returning: nil)
        _ = await first.value
        #expect(s.phase == .idle)
    }

    @Test("повторный start во время runner'а — отказ")
    func secondStartDuringRun() async {
        let s = makeSession()
        let task = await s.start(request())
        while h.runCalls.isEmpty { await Task.yield() }
        #expect(await s.start(request()) == nil)
        #expect(h.runCalls.count == 1)
        await finish(task)
    }

    @Test("окно закрыто, runner жив: занято до возврата runner'а")
    func closeWhileRunning() async {
        let s = makeSession()
        let task = await s.start(request())
        while h.runCalls.isEmpty { await Task.yield() }
        s.closeProgress(origin: .main)
        #expect(s.progress == nil)
        #expect(s.isBusy)
        #expect(await s.start(request()) == nil)
        await finish(task)
        #expect(s.phase == .idle)
        h.released = false
        let next = await s.start(request())
        #expect(next != nil)
        #expect(h.chooseCalls.count == 2)
        await finish(next)
    }

    @Test("closeProgress с чужим origin не трогает прогресс")
    func closeForeignOrigin() async {
        let s = makeSession()
        let task = await s.start(request(origin: .main))
        s.closeProgress(origin: .search)
        #expect(s.progress(for: .main) != nil)
        await finish(task)
    }

    @Test("runner вернулся при открытом окне: idle, прогресс остался")
    func runnerReturnsWindowOpen() async {
        let s = makeSession()
        let task = await s.start(request())
        let p = s.progress
        await finish(task)
        #expect(s.phase == .idle)
        #expect(s.progress === p)
    }

    @Test("start при показанном итоге заменяет прогресс")
    func startReplacesProgress() async {
        let s = makeSession()
        await finish(await s.start(request(origin: .main)))
        let old = s.progress
        h.released = false
        let task = await s.start(request(origin: .search))
        #expect(s.progress !== old)
        #expect(s.progress != nil)
        #expect(s.origin == .search)
        await finish(task)
    }

    @Test("uncheck доходит до runner'а, в том числе после closeProgress")
    func uncheckPassThrough() async {
        var unchecked: [Int32] = []
        let s = makeSession()
        let task = await s.start(request(uncheck: { unchecked.append($0) }))
        while h.runCalls.isEmpty { await Task.yield() }
        s.closeProgress(origin: .main)
        h.runCalls[0].onExported(7)
        #expect(unchecked == [7])
        await finish(task)
    }
}
