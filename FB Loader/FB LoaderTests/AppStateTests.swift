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
