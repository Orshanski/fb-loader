import Foundation
import Testing
@testable import FB_Loader

@Suite("AppStateTests")
@MainActor
struct AppStateTests {

    @Test("Дефолт: .authors(nil), пустые per-tab поля")
    func defaultState() {
        let s = AppState()
        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "ru")
    }

    @Test("isAnySheetPresented: настройки и поиск поднимают флаг, без sheet — ложь")
    func anySheetPresented() {
        let s = AppState()
        #expect(!s.isAnySheetPresented)
        s.isSearchPresented = true
        #expect(s.isAnySheetPresented)
        s.isSearchPresented = false
        s.isSettingsPresented = true
        #expect(s.isAnySheetPresented)
    }

    @Test("isAnySheetPresented следует за выгрузкой: выбор папки, ход, итог, закрыт")
    func sheetFollowsExport() async throws {
        let box = TestDefaults()
        defer { box.cleanUp() }
        let paths = UserPaths(defaults: box.defaults)
        paths.archivesDirectoryURL = FileManager.default.temporaryDirectory
        let gate = Gate()
        let session = ExportSession(
            userPaths: paths,
            chooseFolder: { _ in await gate.waitFolder(); return FileManager.default.temporaryDirectory },
            makeConverter: { _ in PassthroughConverter() },
            run: { _, _, _, _, _ in await gate.waitRun() })
        let s = AppState(exportSession: session)
        let library = Library(inpxHash: Data(count: 32), inpxVersion: "v", archives: ["a"],
                              authors: [Author.unknown], series: [], genres: [], books: [])
        let request = ExportRequest(libids: [1], library: library, selectedAuthorID: nil, selectedSeriesID: nil,
                                    format: .fb2, origin: .main, uncheck: { _ in })
        #expect(!s.isAnySheetPresented)

        let starting = Task { await session.start(request) }
        while session.phase != .choosingFolder { await Task.yield() }
        #expect(s.isAnySheetPresented)

        await gate.releaseFolder()
        let run = try #require(await starting.value)
        #expect(session.phase == .running)
        #expect(s.isAnySheetPresented)

        await gate.releaseRun()
        await run.value
        #expect(session.phase == .idle)
        #expect(s.isAnySheetPresented)

        session.closeProgress(origin: .main)
        #expect(!s.isAnySheetPresented)
    }

    private actor Gate {
        private var folder: CheckedContinuation<Void, Never>?
        private var run: CheckedContinuation<Void, Never>?
        private var folderOpen = false
        private var runOpen = false
        func waitFolder() async {
            if folderOpen { return }
            await withCheckedContinuation { folder = $0 }
        }
        func waitRun() async {
            if runOpen { return }
            await withCheckedContinuation { run = $0 }
        }
        func releaseFolder() { folderOpen = true; folder?.resume(); folder = nil }
        func releaseRun() { runOpen = true; run?.resume(); run = nil }
    }

    @Test("selectSection — смена case'а сбрасывает per-tab")
    func selectSectionSwitchesCase() {
        let s = AppState()
        s.selectLanguage("en")
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "abc"
        s.checkedBookLibids = [1, 2]

        s.selectSection(.authors(nil))

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "en")
    }

    @Test("selectSection — точный no-op при равном sidebar")
    func selectSectionExactNoop() {
        let s = AppState()
        s.selectLanguage("en")
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectSection(.authors(10))

        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "x")
        #expect(s.checkedBookLibids == [1])
        #expect(s.selectedBookLibid == 7)
        #expect(s.languageFilter == "en")
    }

    @Test("selectSection — same-case другой ID: полный сброс")
    func selectSectionSameCaseDifferentID() {
        let s = AppState()
        s.selectLanguage("en")
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectSection(.authors(nil))

        #expect(s.sidebar == .authors(nil))
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == nil)
        #expect(s.languageFilter == "en")
    }

    @Test("selectAuthor без имени — same-case другой ID: гасит preview и галочки")
    func selectAuthorClickInList() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(42)

        #expect(s.sidebar == .authors(42))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor без имени — same-ID no-op")
    func selectAuthorSameIDNoop() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(10)

        #expect(s.sidebar == .authors(10))
        #expect(s.selectedBookLibid == 7)
        #expect(s.checkedBookLibids == [1])
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor с именем — cross-section: фильтр в имя, preview сохраняется")
    func selectAuthorDeepLinkCrossSection() {
        let s = AppState()
        s.selectLanguage("en")
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(42))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
        #expect(s.languageFilter == "en")
    }

    @Test("selectAuthor с именем — same-section: фильтр перезаписан, preview сохранён")
    func selectAuthorDeepLinkSameSection() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "Толстой"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(42))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectAuthor с именем — same-ID re-click: идемпотентный прицел")
    func selectAuthorDeepLinkSameIDIdempotent() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "Толстой"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(10, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectSeries с именем — симметрично selectAuthor")
    func selectSeriesDeepLink() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectSeries(55, deepLinkName: "Ахейский цикл")

        #expect(s.sidebar == .series(55))
        #expect(s.sidebarFilter == "Ахейский цикл")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectGenre — без имени, как клик в списке")
    func selectGenreClickInList() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1]
        s.sidebarFilter = "x"

        s.selectGenre(7)

        #expect(s.sidebar == .genres(7))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor(nil) внутри секции — same-section с nil ID")
    func selectAuthorNilInsideSection() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(nil)

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    private var someFilter: DateRangeFilter {
        let cal = Calendar.current
        return DateRangeFilter(
            from: cal.date(from: DateComponents(year: 2013, month: 3, day: 1))!,
            to: cal.date(from: DateComponents(year: 2015, month: 6, day: 30))!)
    }

    @Test("applyDateFilter гасит галочки и превью")
    func applyDateFilterClearsSelection() {
        let s = AppState()
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1, 2]

        s.applyDateFilter(someFilter)

        #expect(s.dateFilter == someFilter)
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
    }

    @Test("applyDateFilter тем же значением — no-op")
    func applyDateFilterSameValueNoop() {
        let s = AppState()
        s.applyDateFilter(someFilter)
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1]

        s.applyDateFilter(someFilter)

        #expect(s.selectedBookLibid == 7)
        #expect(s.checkedBookLibids == [1])
    }

    @Test("клик по другому автору снимает фильтр")
    func selectAuthorClearsDateFilter() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.applyDateFilter(someFilter)

        s.selectAuthor(42)

        #expect(s.dateFilter == nil)
    }

    @Test("клик по тому же автору фильтр сохраняет")
    func selectSameAuthorKeepsDateFilter() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.applyDateFilter(someFilter)

        s.selectAuthor(10)

        #expect(s.dateFilter == someFilter)
    }

    @Test("deep-link снимает фильтр, но превью книги сохраняет")
    func deepLinkClearsFilterKeepsPreview() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.applyDateFilter(someFilter)
        s.selectedBookLibid = 7

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.dateFilter == nil)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("смена языка фильтр дат не трогает")
    func languageChangeKeepsDateFilter() {
        let s = AppState()
        s.applyDateFilter(someFilter)

        s.selectLanguage("en")

        #expect(s.dateFilter == someFilter)
    }

    @Test("reset — sidebar=.authors(nil), все per-tab и language к дефолтам")
    func resetState() {
        let s = AppState()
        s.selectLanguage("en")
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]

        s.reset()

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "ru")
    }

    @Test("reset снимает фильтр дат")
    func resetClearsDateFilter() {
        let s = AppState()
        s.applyDateFilter(someFilter)

        s.reset()

        #expect(s.dateFilter == nil)
    }

    @Test("смена вкладки снимает фильтр дат")
    func selectSectionClearsDateFilter() {
        let s = AppState()
        s.applyDateFilter(someFilter)

        s.selectSection(.series(nil))

        #expect(s.dateFilter == nil)
    }

    @Test("смена языка гасит галочки и превью, фильтр сайдбара и вкладку не трогает")
    func selectLanguageClearsChecksAndPreview() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1, 2]

        s.selectLanguage("en")

        #expect(s.languageFilter == "en")
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "x")
    }

    @Test("тот же язык — no-op")
    func selectSameLanguageNoop() {
        let s = AppState()
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1]

        s.selectLanguage("ru")

        #expect(s.selectedBookLibid == 7)
        #expect(s.checkedBookLibids == [1])
    }

    @Test("пересборка каталога доступна только при открытом каталоге")
    func rebuildAvailableOnlyWhenReady() throws {
        let s = AppState()
        #expect(!s.canRebuildCatalog)
        s.stage = .onboarding(.both)
        #expect(!s.canRebuildCatalog)
        s.stage = .loading(progress: "")
        #expect(!s.canRebuildCatalog)
        s.stage = .failed("x")
        #expect(!s.canRebuildCatalog)
        let url = try #require(TestBundleAnchor.bundle.url(forResource: "tiny", withExtension: "inpx"))
        s.stage = .ready(try INPXImporter.parse(inpxURL: url, genres: GenreDictionary.loadFromBundle()))
        #expect(s.canRebuildCatalog)
    }
}
